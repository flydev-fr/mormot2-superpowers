---
name: mormot2-deploy
description: Use for deployment: static libs (SQLite, OpenSSL, Zstd), Windows service / systemd, fronting with nginx / HAProxy. Do NOT use for in-process TLS (mormot2-net) or compiler flags (use *-build skills).
---

# mormot2-deploy

mORMot 2 deployment and hosting layer: bundling C dependencies (SQLite3, OpenSSL, Zstd, libdeflate, QuickJS, libgss) into a single binary via the `mormot.lib.static` linkage, running the binary as a Windows Service or POSIX daemon through `mormot.app.daemon` and `mormot.core.os` (`TServiceController`, `TServiceSingle`, `TSynDaemon`), supervising children with `mormot.app.agl` (`TSynAngelize`), and fronting the listener with a reverse proxy (nginx, IIS ARR, HAProxy, Caddy). This skill is authoritative for the `mormot.app.*` namespace plus the deployment-time aspects of `mormot.lib.static`. It assumes the conventions of `mormot2-core` (logging via `TSynLog`, RawUtf8) and stops where build-time flags begin: those belong in `delphi-build` / `fpc-build`. TLS termination has two homes: in-process via `mormot2-net` (`TAcmeLetsEncryptServer` + OpenSSL), or at the reverse proxy. Pick one and document it.

## When to use

- Bundling SQLite, OpenSSL, Zstd, libdeflate, QuickJS, or libgss into the executable so the binary ships without runtime DLL/.so dependencies (see `mormot.lib.static.pas`).
- Standing up a Windows Service via `TServiceController.Install` / `TServiceSingle` / `ServiceSingleRun`, or running the same code as a POSIX daemon via `TSynDaemon` (`mormot.app.daemon`).
- Writing a `systemd` unit, `launchd` plist, or Windows Service registration that targets a mORMot binary, with the right `User=`, `WorkingDirectory=`, and restart policy.
- Fronting a `TRestHttpServer` with nginx, IIS (with ARR), HAProxy, Caddy, or Cloudflare Tunnel, including the `Upgrade` / `Connection` headers needed for `useBidirAsync` WebSocket traffic.
- Supervising one or more mORMot processes with `TSynAngelize` (`mormot.app.agl`): start / stop ordering, HTTP health checks, auto-restart with backoff, log redirection.
- Packaging for distribution: Inno Setup / WiX / `.deb` / `.rpm` / Docker layers; choosing between `mormot2static` archive download and per-platform package managers.

## When NOT to use

- In-process TLS termination, ACME certificate automation, SNI dispatch. Use **mormot2-net** (`TAcmeLetsEncryptServer`, `OnNetTlsAcceptServerName`).
- Selecting a database driver, sizing the connection pool, or wiring `TSqlDBConnectionProperties`. Use **mormot2-db**.
- Compiler search paths, `.dproj` / `.lpi` configuration, `dcc64` or `fpc` flags. Use **delphi-build** / **fpc-build**.
- Defining REST routes, SOA contracts, or `TRestServer` lifecycle inside the daemon's `Start` / `Stop`. Use **mormot2-rest-soa**.
- JWT, AES-GCM, ECC keypair generation. Use **mormot2-auth-security**.
- Foundational types (`RawUtf8`, `TSynLog` setup, `TDocVariant`). Use **mormot2-core**.

## Core idioms

### 1. Run as Windows Service or POSIX daemon with `TSynDaemon`

`TSynDaemon` (unit `mormot.app.daemon`) is the cross-platform shape: same code installs as a Windows Service and runs as a POSIX daemon. Override `Start` and `Stop`; let `CommandLine` parse `/install`, `/uninstall`, `/console` (Windows) or `--run`, `--fork`, `--kill` (POSIX).

```pascal
program myserver;
{$I mormot.defines.inc}
uses
  {$I mormot.uses.inc}
  mormot.core.base,
  mormot.core.log,
  mormot.app.daemon,
  mormot.rest.http.server,
  myserver.rest in 'myserver.rest.pas';

type
  TMyDaemon = class(TSynDaemon)
  protected
    fHttp: TRestHttpServer;
    fRest: TMyRestServer;
  public
    procedure Start; override;
    procedure Stop; override;
  end;

procedure TMyDaemon.Start;
begin
  fRest := TMyRestServer.Create;
  fHttp := TRestHttpServer.Create('8080', [fRest], '+', useHttpAsync, 32);
  TSynLog.Add.Log(sllInfo, 'listening on :8080', self);
end;

procedure TMyDaemon.Stop;
begin
  FreeAndNil(fHttp); // free HTTP wrapper before REST server
  FreeAndNil(fRest);
end;

begin
  with TMyDaemon.Create(TSynDaemonSettings, '', '', '') do
  try
    CommandLine; // dispatches /install /console /run /kill /state ...
  finally
    Free;
  end;
end.
```

`Stop` MUST be safe to call multiple times. Settings live in `<exename>.settings` (JSON, INI fallback): `ServiceName`, `ServiceDisplayName`, `Log`, `LogPath`, `LogRotateFileCount`. On POSIX, default `LogPath` is `/var/log`; on Windows, it is the executable folder.

### 2. Install as a Windows Service from your own installer

If you do not want users to type `myserver.exe /install`, drive `TServiceController.Install` directly. It is a one-liner that talks to the Service Control Manager.

```pascal
uses
  mormot.core.os;

var
  state: TServiceState;
begin
  state := TServiceController.Install(
    'MyService',                  // internal name (CreateService lpServiceName)
    'My Application Service',     // display name
    'REST API for MyApp',         // description
    {AutoStart=}true,
    {ExeName=}'',                 // '' = current executable, ParamStr(0)
    {Dependencies=}'Tcpip;');     // ; or # separated, optional
  if state = ssErrorRetrievingState then
    raise Exception.Create('install failed; check Windows event log');
end;
```

`TServiceController.CurrentState('MyService')` returns `ssRunning`, `ssStopped`, `ssNotInstalled`, etc. For a process that registers itself as the running service (rather than installing), use `TServiceSingle` with `ServiceSingleRun`. `TSynDaemon.CommandLine` already does both; reach for `TServiceController` directly only when you bypass `TSynDaemon`.

### 3. Static-link C dependencies for a single-binary deploy

mORMot ships precompiled `.o` / `.obj` archives under `mORMot2/static/`. Download `mormot2static.7z` (Windows) or `.tgz` (POSIX) once per checkout. The framework's defaults under `mormot.defines.inc` already turn on the right conditional per platform; the deployment-time job is to verify the conditional you want is set and that the static archive matches the checkout.

```pascal
{$I mormot.defines.inc}
// Active static-linkage conditionals on mainstream targets:
//   STATICSQLITE       (default; undef NOSQLITE3STATIC)
//   OPENSSLSTATIC      (Windows + Linux x86_64 by default in 2.x)
//   LIBDEFLATESTATIC   (Intel Linux/Windows)
//   LIBQUICKJSSTATIC   (Win32, Linux x86_64)
//   ZSTDSTATIC         (via mormot.lib.zstd; TSynZstdStatic populates Zstd)
//   LIBCURLSTATIC      (mainly Android; not for desktop)

uses
  mormot.lib.static, // GCC/libc shims, FPU exception masking
  mormot.db.raw.sqlite3.static, // pulls SQLite .o into the binary
  mormot.lib.openssl11; // OPENSSLSTATIC switches this to static linkage
```

A binary with `STATICSQLITE` + `OPENSSLSTATIC` + `LIBDEFLATESTATIC` ships as a single file with no DLL/.so dependency for SQL, TLS, or HTTP compression. Verify with `ldd myserver` (POSIX) or `dumpbin /dependents` (Windows): nothing under `/usr/lib/libssl*`, no `libcrypto-*.dll`. If you see them, the conditional did not apply (often because the static archive is missing for that platform; see `references/static-libs.md`).

### 4. Reverse-proxy with nginx, including WebSocket upgrade

`useHttpAsync` and `useBidirAsync` work fine behind nginx. The two non-obvious points: WebSocket upgrade requires `Upgrade` / `Connection` headers to be re-set (nginx strips hop-by-hop headers by default), and you must forward the original client IP, scheme, and host so server-side logging and OAuth callbacks see the right thing.

```nginx
upstream mormot { server 127.0.0.1:8080; keepalive 32; }

server {
  listen 443 ssl http2;
  server_name api.example.com;

  ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

  location / {
    proxy_pass         http://mormot;
    proxy_http_version 1.1;

    # Pass-through identity. mORMot reads X-Forwarded-* via TRestServer.OnIPCheck etc.
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket upgrade for useBidirAsync.
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        "upgrade";

    proxy_read_timeout 3600s;  # keep idle WS connections alive
  }
}
```

Pick TLS at exactly one layer. If nginx terminates TLS, run mORMot as plain HTTP on `127.0.0.1` and disable any in-process ACME wiring. If you want certs inside the binary (`TAcmeLetsEncryptServer`), put nginx in TCP-passthrough mode (`stream { listen 443; proxy_pass 127.0.0.1:8443; }`) or remove nginx entirely.

### 5. Supervise with `TSynAngelize` or systemd

`TSynAngelize` (unit `mormot.app.agl`) is mORMot's NSSM equivalent: a JSON-configured supervisor that starts, stops, watches, and restarts child processes with backoff, optionally over HTTP health checks. Use it when you ship a multi-process bundle (web + worker + scheduler) on hosts where you do not want to author per-distro init.

```json
{
  "Services": [
    {
      "Name": "api",
      "Run": "/opt/myapp/bin/myserver",
      "Start": [ "start:%run% --run" ],
      "Stop":  [ "stop:%run%" ],
      "Watch": [ "http://127.0.0.1:8080/health=200" ],
      "WatchDelaySec": 30,
      "RetryStableSec": 60,
      "AbortExitCodes": [ 2, 3 ],
      "RedirectLogFile": "%log%api-console.log",
      "RedirectLogRotateFiles": 5,
      "RedirectLogRotateBytes": 10485760
    }
  ]
}
```

If the host is single-process and Linux, prefer `systemd`: it integrates with `journalctl`, cgroup limits, and socket activation, and one less mORMot process is one less thing to monitor. See `references/services-and-daemons.md` for both unit and plist templates.

## Common pitfalls

- **Forgetting `myserver.exe /install` (or driving `TServiceController.Install` from your installer).** `TSynDaemon` produces the right binary but does not register itself with the Service Control Manager automatically. Without an install step, `net start MyService` fails with `error 1060` ("the specified service does not exist"). Either run the binary once with `/install` from a privileged shell, or call `TServiceController.Install` from your installer's post-install script.
- **`User=` on systemd that cannot read its own working files.** A `User=mormot` service that runs from `/etc/myapp.settings` will silently fail to load settings if that file is owned by `root:root` mode 0600. The daemon proceeds with defaults. Symptom: it serves on the wrong port, logs to `/tmp` instead of `/var/log/myapp`. Fix by setting `chown mormot:mormot /etc/myapp.settings && chmod 0640` and confirming `LogPath` writes through.
- **Reverse proxy that drops `Upgrade` and `Connection`.** WebSocket clients connect, get HTTP 200 instead of 101, and silently fall back. The mORMot server logs nothing (no upgrade ever reaches it). Always set `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";` for nginx, the equivalent `option http-server-close` + `http-request set-header` for HAProxy, and the `webSocket` flag on IIS ARR rules.
- **Static archive arch mismatch.** The download is one archive per `<os>-<cpu>` triplet. Building Win64 with the Win32 archive on the search path produces `Undefined symbol` linker errors deep in `_sqlite3_*` or `_BIO_*`. The error message names a C symbol, not a Pascal unit, which makes it look like a framework bug. Verify the archive matches your target before debugging anything else.
- **SELinux / AppArmor denying outbound connect or port bind.** A daemon installed via `dnf install` runs under a confined SELinux context that may forbid `name_connect` to PostgreSQL on a non-default port, or `name_bind` to ports below 1024 (other than 80/443 by default). Symptom: daemon starts cleanly, then every DB query times out or `bind()` returns EACCES. Check `journalctl -t setroubleshoot` and either label the binary with the right context (`semanage fcontext`) or run from `/opt/myapp` (which is `unconfined_t` by default).
- **Two TLS terminators.** Running `TAcmeLetsEncryptServer` *and* terminating TLS at nginx means cert renewal silently fights for port 80, the binary serves a self-signed or stale cert internally, and nginx's cert is the one users actually see. Pick one. If you keep nginx, drop the in-process ACME (`mormot2-net` belongs to a different topology). If you keep in-process ACME, replace nginx with TCP passthrough.
- **Treating `Stop` as a one-shot.** Windows SCM may call the stop handler twice during a forced shutdown; systemd may call it once on graceful stop and again on the watchdog timeout. `TSynDaemon.Stop` overrides MUST be idempotent: free with `FreeAndNil`, guard external resource teardown with `if Assigned(...)`. A second-call AV crashes the service stop, leaves the SCM in `ssStopPending`, and forces the next deploy to do `taskkill /F`.
- **Forwarding the wrong client IP.** `X-Forwarded-For` is the standard, but only mORMot routes that consult it (e.g. `TRestServer.OnIPCheck`, custom rate-limit code) will use it. A plain `Sender.Call.LowLevelRemoteIP` reads the TCP peer, which is the proxy. Audit code that throttles or geo-locates by IP and route it through the X-Forwarded-* parser, not the socket peer.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-20.md` - Hosting (daemon, service, Angelize)
- `references/static-libs.md`
- `references/services-and-daemons.md`
- `references/reverse-proxy.md`
- `mormot2-net` for in-process TLS / ACME and HTTP engine selection
- `mormot2-rest-soa` for the REST/SOA layer that runs inside `Start`
- `delphi-build`, `fpc-build` for compiler flags and search paths
