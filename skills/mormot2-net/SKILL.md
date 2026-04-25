---
name: mormot2-net
description: Use for HTTP transport in mORMot 2: TRestHttpServer modes (useHttpAsync, useBidirAsync), WebSockets, OpenAPI, TLS/ACME. Do NOT use for SOA shape (mormot2-rest-soa) or crypto (mormot2-auth-security).
---

# mormot2-net

mORMot 2 networking and transport layer: HTTP/HTTPS servers and clients, WebSocket protocols, OpenAPI client generation, ACME (Let's Encrypt / ZeroSSL) certificate automation, and HTTP tunnels. This skill is authoritative for the `mormot.net.*` namespace plus `mormot.rest.http.server` and `mormot.rest.http.client` (the HTTP wrappers around `TRestServer` / `TRestClientUri`). It assumes the conventions defined in `mormot2-core` (RawUtf8, RTTI). Sibling skills cover adjacent concerns: `mormot2-rest-soa` defines the REST and SOA service shape that this skill transports, `mormot2-auth-security` covers cryptographic primitives (JWT, AES, ECC) that may sit on top of TLS, and `mormot2-deploy` covers reverse-proxy fronting and OS-level service hosting.

## When to use

- Choosing among `useHttpAsync`, `useBidirAsync`, `useHttpSocket`, or `useHttpApi` (Windows HTTP.SYS) when constructing a `TRestHttpServer`.
- Standing up a raw `THttpAsyncServer` or `THttpServer` outside of REST, e.g. for a static-file endpoint, a webhook receiver, or a custom router.
- Adding a WebSocket upgrade path with `TWebSocketAsyncServerRest` (modern, async) or `TWebSocketServerRest` (classic threaded), and registering a `TWebSocketProtocolJson` / `TWebSocketProtocolBinary`.
- Generating Pascal client code from an OpenAPI / Swagger JSON file via `TOpenApiParser` in `mormot.net.openapi`.
- Automating Let's Encrypt / ZeroSSL certificate issuance and renewal with `TAcmeLetsEncryptServer` (port 80 challenge listener) plus `OnNetTlsAcceptServerName` SNI hook.
- Running an HTTP request through `TSimpleHttpClient`, `THttpClientSocket`, or the higher-level `IJsonClient` / `TJsonClient`.
- Setting up a tunneled or relayed TCP connection with `mormot.net.tunnel`, `mormot.net.relay`, or DNS/DHCP/TFTP services.

## When NOT to use

- Defining the REST routes, method-based services, or `IInvokable` contracts that the HTTP server transports. Use **mormot2-rest-soa**.
- Generating or verifying JWTs, ECC key pairs, AES-GCM payloads, password hashes. Use **mormot2-auth-security**.
- Choosing the deployment topology (nginx/IIS reverse proxy, systemd unit, Windows service install). Use **mormot2-deploy**.
- Selecting a SQL provider or tuning a connection pool. Use **mormot2-db**.
- Foundational types and JSON conventions (`RawUtf8`, `TDocVariant`, RTTI registration). Use **mormot2-core**.

## Core idioms

### 1. TRestHttpServer engine selection

`TRestHttpServer` (unit `mormot.rest.http.server`) wraps any `TRestServer` and serves it over HTTP. The fifth constructor argument picks the engine. Pick by traffic profile, not by feel.

```pascal
uses
  mormot.rest.http.server;

var
  HttpServer: TRestHttpServer;
begin
  HttpServer := TRestHttpServer.Create(
    '8080',           // port
    [RestServer],     // one or more TRestServer instances
    '+',              // domain name ('+' = bind all)
    useHttpAsync,     // engine: event-driven, scales to many concurrent connections
    32);              // worker thread count
  try
    // server is running; HttpServer.Shutdown is implicit on Free
  finally
    HttpServer.Free;  // free the HTTP wrapper BEFORE the TRestServer
  end;
end;
```

Engines, in one line each:
- `useHttpAsync`: event-driven sockets, best general-purpose choice for many connections.
- `useBidirAsync`: same as above plus WebSocket upgrade (`TWebSocketAsyncServerRest`).
- `useHttpSocket`: classic one-thread-per-connection server (`THttpServer`); simple, scales worse.
- `useHttpApi` / `useHttpApiRegisteringURI`: Windows HTTP.SYS kernel listener; only on Windows, integrates with IIS-style URL ACLs.

### 2. WebSocket upgrade with async server

`useBidirAsync` swaps in `TWebSocketAsyncServerRest`. Register protocols by name; the client negotiates them in the `Sec-WebSocket-Protocol` header.

```pascal
uses
  mormot.rest.http.server,
  mormot.net.ws.async,
  mormot.net.ws.core;

var
  HttpServer: TRestHttpServer;
  Ws: TWebSocketAsyncServerRest;
begin
  HttpServer := TRestHttpServer.Create('8080', [RestServer], '+', useBidirAsync);
  Ws := HttpServer.WebSocketsEnable(RestServer, 'encryption-key', false);
  // Ws.WebSocketProtocols.Add(TWebSocketProtocolJson.Create('chat', '/chatroom'));
  // Now /chatroom accepts WebSocket upgrades using TWebSocketProtocolJson.
end;
```

Use `TWebSocketProtocolJson` for human-readable framing during development and `TWebSocketProtocolBinary` for production: it adds optional AES encryption and is significantly more compact on the wire.

### 3. Generate a Pascal client from OpenAPI

`TOpenApiParser` reads a Swagger 2 or OpenAPI 3 JSON document and emits two Pascal units: a DTO unit (records and enums) and a client unit (one method per operation). The client speaks JSON via `IJsonClient`.

```pascal
uses
  mormot.net.openapi;

var
  Parser: TOpenApiParser;
begin
  Parser := TOpenApiParser.Create('Petstore', [opoClientOnlySummary]);
  try
    Parser.ParseFile('petstore.openapi.json');
    Parser.ExportToDirectory('generated/');
    // emits Petstore.dto.pas + Petstore.client.pas
  finally
    Parser.Free;
  end;
end;
```

Add the generated units to your project, then construct `TPetstoreClient.Create(IJsonClient.Create('https://api.example.com'))` and call methods directly.

### 4. ACME (Let's Encrypt / ZeroSSL) automation

`TAcmeLetsEncryptServer` runs a small HTTP listener on port 80, answers the HTTP-01 challenge, redirects everything else to HTTPS, and renews certificates twice a day in the background. The HTTPS server itself stays a normal `THttpAsyncServer` / `TRestHttpServer`.

```pascal
uses
  mormot.net.acme,
  mormot.net.async,
  mormot.core.log;

var
  Acme: TAcmeLetsEncryptServer;
  Https: THttpAsyncServer;
begin
  // HTTPS server is set up first; pass nil HttpsServer here and assign later if needed.
  Acme := TAcmeLetsEncryptServer.Create(
    TSynLog,
    '/var/lib/myapp/acme/',     // key store folder (one set per domain)
    ACME_LETSENCRYPT_URL,        // production directory; use ACME_LETSENCRYPT_DEBUG_URL while testing
    'x509-es256',
    '');                         // optional private-key password
  Acme.LoadFromKeyStoreFolder;
  Acme.CheckCertificatesBackground;  // renews any cert within RenewBeforeEndDays of expiry
  // Wire the SNI callback into the HTTPS listener so it picks the right cert per host.
  Https.SetTlsServerNameCallback(Acme.OnNetTlsAcceptServerName);
end;
```

Set `Acme.RenewBeforeEndDays` (default 30) and `Acme.RenewWaitForSeconds` (default 30) when tuning. The folder layout is one `##.json` + `##.acme.pem` + `##.crt.pem` + `##.key.pem` per domain.

### 5. JSON HTTP client

For raw HTTP+JSON without REST/SOA, use `TJsonClient`. It owns the connection, retries, sets `Content-Type`, and rolls in custom RTTI for the request/response records.

```pascal
uses
  mormot.net.client;

var
  Client: IJsonClient;
  Out: TMyResponse;
begin
  Client := TJsonClient.Create('https://api.example.com');
  Client.Request('GET', 'v1/items/42', [], [], TypeInfo(TMyResponse), Out);
end;
```

The interface is reference-counted, so no explicit `Free`. Pass `[jcoNoEncodeUriQuery]` and friends in `TJsonClientOptions` to tune URI encoding and error handling.

## Common pitfalls

- **Picking `useHttpSocket` for a high-connection workload.** `useHttpSocket` runs one thread per connection. Under a few hundred concurrent connections you exhaust the thread pool and tail latencies explode. Use `useHttpAsync` for almost any modern server; reserve `useHttpSocket` for low-connection-count internal services where its simpler accept loop is easier to reason about.
- **Freeing `TRestServer` before `TRestHttpServer`.** The HTTP server holds references into the REST server; free it first, then the REST server, then the model. The wrong order leaves the listener accepting requests that dispatch into freed memory.
- **Mixing `TWebSocketProtocolJson` and `TWebSocketProtocolBinary` clients on the same path.** Negotiation uses the `Sec-WebSocket-Protocol` header. If a JSON client connects to a binary-only path, the upgrade succeeds but every frame fails to deserialize. Pin protocols per route, or accept both and dispatch on `Sender.ClassType`.
- **Forgetting to call `WebSocketsEnable` after `TRestHttpServer.Create(useBidirAsync)`.** `useBidirAsync` allocates the WebSocket-capable server instance, but the route table is empty until you call `WebSocketsEnable` (and add protocols). Without it, the server happily serves HTTP and rejects every WebSocket upgrade.
- **Skipping the ACME staging directory.** `ACME_LETSENCRYPT_URL` is the production endpoint and rate-limits issuance per domain (50 certs/week). During development, point `DirectoryUrl` at `ACME_LETSENCRYPT_DEBUG_URL` so a misconfigured deploy loop does not get you blocked.
- **No HTTP-01 listener on port 80.** ACME HTTP-01 requires a publicly reachable listener at `http://<domain>/.well-known/acme-challenge/<token>`. If port 80 is firewalled or already taken (often by an old web server), `CheckCertificates` raises and renewal silently stops. Either bind `TAcmeLetsEncryptServer` on port 80 directly or proxy that one path through your reverse proxy.
- **Calling `OnNetTlsAcceptServerName` only at startup.** The callback must remain wired for the lifetime of the listener, not just at construction. If the HTTPS server is recreated (graceful restart, hot reload), reattach `Acme.OnNetTlsAcceptServerName` on the new listener instance.
- **IPv6 binding on dual-stack hosts.** mORMot binds to `0.0.0.0` (IPv4) by default. To accept IPv6, pass `'::'` (or `'[::]:8080'`) as the port argument. On Linux, also confirm `net.ipv6.bindv6only=0` if you want a single socket to serve both stacks.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-11.md` - Client-Server Architecture
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-20.md` - Hosting
- `references/async-http.md`
- `references/websockets.md`
- `references/openapi-export.md`
- `references/tls-acme.md`
- `mormot2-rest-soa` for service contracts on top of this transport
- `mormot2-auth-security` for JWT, ECC, AES primitives
- `mormot2-deploy` for reverse-proxy fronting and OS-level service hosting
