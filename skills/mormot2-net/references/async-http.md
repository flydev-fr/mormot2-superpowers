# Async HTTP

mORMot 2 ships four HTTP server engines. Picking the right one is the single most consequential choice you will make in the transport layer; it affects throughput, tail latency, memory profile, and even what fits behind your reverse proxy. Use this matrix to choose deliberately.

## Engine matrix

| Engine                        | Class wired in                         | Concurrency model              | Best for                                                       | Avoid for                                            |
|-------------------------------|----------------------------------------|--------------------------------|----------------------------------------------------------------|------------------------------------------------------|
| `useHttpSocket`               | `THttpServer` (`mormot.net.server`)    | One thread per connection      | Internal services with low connection count, simple debugging  | Public endpoints with hundreds of concurrent clients |
| `useHttpAsync`                | `THttpAsyncServer` (`mormot.net.async`)| Event-driven, fixed worker pool| Default modern choice; HTTP/1.1 keep-alive at scale            | Workloads dominated by long-running blocking handlers|
| `useBidirAsync`               | `TWebSocketAsyncServerRest`            | Same as `useHttpAsync` plus WS | Anything that needs WebSocket upgrade                          | Pure HTTP if you do not also need WS                 |
| `useHttpApi` (Windows only)   | `THttpApiServer` (kernel HTTP.SYS)     | Kernel-mode queue, user workers| Sharing port 80/443 with IIS, SChannel TLS, URL ACL integration| Linux/macOS, lightweight single-binary deployments   |

`useHttpApiRegisteringURI` is `useHttpApi` plus a one-shot `netsh http add urlacl` registration. Use it during install, not in the running binary path.

## Thread pool sizing

The `aThreadPoolCount` argument on `TRestHttpServer.Create` sizes the worker pool. mORMot enforces a floor of `CpuThreads * 5` if you pass a smaller value, so passing `0` is safe and gets you the default sizing.

Rules of thumb:

- **CPU-bound handlers** (JSON serialization heavy, no I/O): set pool to `CpuThreads` to `2 * CpuThreads`. More workers just thrash caches.
- **I/O-bound handlers** (waiting on DB, downstream HTTP, disk): set pool to `2 * CpuThreads` to `4 * CpuThreads`. Extra workers absorb wait time.
- **Mixed workload**: start at `CpuThreads * 5` (the framework default) and tune from telemetry. mORMot enforces this floor for a reason.
- **`useHttpSocket` only**: the pool size is the maximum number of concurrent connections you can accept. Plan accordingly; `useHttpAsync` does not have this constraint.

## Backpressure

`useHttpAsync` is event-driven, but handlers still run on the worker pool. If every worker is blocked waiting on a slow downstream, new connections accept fine but their requests queue. Symptoms:

- Request latency p99 grows even though CPU is idle.
- Queue depth on the load balancer climbs.
- Connection counts on the listener look healthy.

Mitigations, in order of preference:

1. Make handlers non-blocking: push slow work to a `TLoggedWorkThread` and respond with `202 Accepted` plus a poll URL or webhook.
2. Increase the worker pool size if downstream wait time is the bottleneck and CPU is not.
3. Cap inbound rate at the reverse proxy (nginx `limit_req`, HAProxy `rate-limit sessions`); leaking traffic upstream is far better than collapsing in-process.

## Keep-alive and HTTP/1.1 vs HTTP/2

`THttpAsyncServer` speaks HTTP/1.1 with persistent connections by default. mORMot does not implement HTTP/2 in the built-in servers; if you need HTTP/2 (or HTTP/3 / QUIC) terminate it at a reverse proxy and run mORMot behind it on HTTP/1.1. nginx, HAProxy, Caddy, and Traefik all do this transparently.

Implications:

- WebSockets work fine through the reverse proxy if you forward `Upgrade` and `Connection` headers (see `mormot2-deploy/references/reverse-proxy.md`).
- HTTP/2 multiplexing happens proxy-side; mORMot still serves one request per keep-alive connection at a time.
- Server-Sent Events (SSE) are HTTP/1.1 streaming and work identically across the proxy.

## Binding addresses

The first argument to `TRestHttpServer.Create` is a port string with optional bind address and protocol override:

- `'8080'` - bind to all interfaces on port 8080 (IPv4 by default).
- `'127.0.0.1:8080'` - bind to localhost only; use this when a reverse proxy fronts the app on the same host.
- `'[::]:8080'` - bind to IPv6 (and IPv4 if `bindv6only=0`).
- `'unix:/run/myapp.sock'` - Unix domain socket (Linux/macOS); skips TCP entirely, ideal for nginx upstream.

The second argument list (`aServers`) accepts multiple `TRestServer` instances; the wrapper multiplexes them by `TOrmModel.Root`.

## Telemetry

Enable via `TRestHttpServerOptions`:

- `rsoTelemetryCsv` - rolling CSV access log.
- `rsoTelemetryJson` - rolling JSON access log; easier to ship to a log aggregator.
- `rsoEnableLogging` - per-request log lines through `TSynLog`.
- `rsoLogVerbose` - includes request/response bodies; verbose, do not leave on in production.

Log volume can dwarf the actual workload; gate `rsoLogVerbose` behind a feature flag or a debug build define.
