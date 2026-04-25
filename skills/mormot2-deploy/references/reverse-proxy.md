# Reverse proxy

mORMot's HTTP servers (`useHttpAsync`, `useBidirAsync`, `useHttpSocket`, `useHttpApi`) are production listeners. You still want a reverse proxy when:

- TLS lives at the edge (single cert renewal, central audit).
- One IP serves many backend services (path-based routing).
- An admin team owns L7 policy (rate limits, bot blocking, geofencing).
- You need HTTP/3 termination today (mORMot speaks HTTP/1.1 + WebSockets).

Pick TLS termination at exactly one layer. If the proxy terminates TLS, run mORMot as plain HTTP on `127.0.0.1` and disable in-process ACME. If you want certs inside the binary (`mormot2-net` `TAcmeLetsEncryptServer`), use TCP passthrough at the proxy or remove the proxy entirely.

## nginx

`useHttpAsync` and `useBidirAsync` work without surprises behind nginx, provided you re-set the upgrade headers and forward client identity.

```nginx
upstream mormot {
  server 127.0.0.1:8080;
  keepalive 32;
}

server {
  listen 443 ssl http2;
  server_name api.example.com;

  ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

  # Cap request body for JSON APIs; mORMot has its own limit too.
  client_max_body_size 16m;

  location / {
    proxy_pass         http://mormot;
    proxy_http_version 1.1;

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket upgrade path (useBidirAsync). Required even on '/' if any
    # subpath upgrades. nginx maps $http_upgrade to "" when absent, which
    # is correct for non-WS requests.
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        "upgrade";

    proxy_read_timeout  3600s;  # idle WS connections
    proxy_send_timeout  3600s;
  }
}

# Optional: redirect plain HTTP to HTTPS.
server {
  listen 80;
  server_name api.example.com;
  return 301 https://$host$request_uri;
}
```

If you run multiple WebSocket sub-paths through nginx and only some upgrade, you can scope the `Upgrade`/`Connection` headers to a `location /ws/ { ... }` block; for most setups, leaving them on the parent `location /` is harmless because nginx only sets them when the client sent `Upgrade:`.

## HAProxy

HAProxy is the right choice when you need fine-grained L7/L4 control or sub-millisecond latency. WebSocket upgrade is automatic; you mostly tune timeouts.

```
global
  maxconn 50000

defaults
  mode    http
  option  httplog
  option  forwardfor       except 127.0.0.1
  option  http-server-close
  timeout connect 5s
  timeout client  3600s
  timeout server  3600s

frontend fe_https
  bind *:443 ssl crt /etc/haproxy/certs/api.example.com.pem
  http-request set-header X-Forwarded-Proto https
  default_backend be_mormot

backend be_mormot
  option httpchk GET /health
  http-check expect status 200
  server mormot1 127.0.0.1:8080 check inter 5s fall 3 rise 2
```

Notes:

- `option forwardfor except 127.0.0.1` adds `X-Forwarded-For` for all but loopback (avoids stamping it twice if you chain proxies).
- `timeout client / server 3600s` keeps long-lived WebSockets alive. Drop them to 60s for plain JSON APIs.
- For TCP passthrough (in-process ACME on the mORMot side), use `mode tcp` in both frontend and backend, and `bind *:443` without `ssl crt`.

## IIS with Application Request Routing (ARR)

Windows shops sometimes terminate at IIS for AD integration, then proxy to mORMot. The two non-default boxes to check:

1. **Install ARR + URL Rewrite** (`Microsoft.Web.Iis.Arr` + `URLRewrite`). They are not part of the IIS role; download from MS Web Platform Installer or chocolatey.
2. **Enable WebSocket support** at the Server level (`AppCmd set config -section:system.webServer/webSocket /enabled:true`).

Then add a rewrite rule that proxies `/api/*` to mORMot:

```xml
<system.webServer>
  <rewrite>
    <rules>
      <rule name="ReverseProxyToMormot" stopProcessing="true">
        <match url="api/(.*)" />
        <serverVariables>
          <set name="HTTP_X_FORWARDED_PROTO" value="https" />
          <set name="HTTP_X_FORWARDED_FOR"   value="{REMOTE_ADDR}" />
        </serverVariables>
        <action type="Rewrite" url="http://127.0.0.1:8080/{R:1}" />
      </rule>
    </rules>
  </rewrite>
</system.webServer>
```

`<serverVariables>` requires those names to be in the IIS allowList (`Configuration Editor -> system.webServer/rewrite/allowedServerVariables`). Without that, IIS strips them silently and your daemon sees nothing.

For raw HTTP.SYS sharing (mORMot using `useHttpApi` while IIS owns port 80/443), register a URL ACL with `netsh http add urlacl url=http://+:8080/api/ user=NT AUTHORITY\NETWORK SERVICE`. This is rare; prefer the rewrite approach.

## Caddy

If you want one-line TLS without thinking about ACME, Caddy is the path of least friction. It auto-issues from Let's Encrypt and reloads on file change.

```caddy
api.example.com {
  reverse_proxy 127.0.0.1:8080 {
    header_up Host              {host}
    header_up X-Real-IP         {remote_host}
    header_up X-Forwarded-For   {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

WebSocket upgrade is automatic; no extra config. The cert lives under `/var/lib/caddy/certificates/`. Back that folder up.

## What to forward, every time

| Header                      | Source       | mORMot use                                     |
|-----------------------------|--------------|------------------------------------------------|
| `Host`                      | original     | `Sender.Call.LowLevelInHeaders` host parsing   |
| `X-Real-IP`                 | client       | one IP, set explicitly                         |
| `X-Forwarded-For`           | chain        | comma-delimited; right-most is client          |
| `X-Forwarded-Proto`         | `http`/`https` | so server-side cookie `Secure` flag is right |
| `Upgrade`, `Connection`     | client       | required for `useBidirAsync` to accept upgrade |

Code that reads the TCP peer IP for rate limiting or geo decisions MUST be routed through an X-Forwarded-For parser. `Sender.Call.LowLevelRemoteIP` shows the proxy on every request once the proxy is in front; that is correct behavior, not a bug.

## Health checks

Expose a cheap endpoint inside mORMot that does not hit the database. Most proxies expect `200 OK` with any body:

```pascal
procedure TMyRestServer.Health(Ctxt: TRestServerUriContext);
begin
  Ctxt.Returns('{"ok":true}', HTTP_SUCCESS, JSON_CONTENT_TYPE_HEADER);
end;
```

Wire `GET /health` and point nginx `proxy_next_upstream`, HAProxy `option httpchk`, or your load balancer's health probe at it. Do NOT stuff DB pings into health checks; that turns one slow query into a cascading outage.
