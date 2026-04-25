# WebSockets

mORMot 2 has two parallel WebSocket stacks: the classic threaded one in `mormot.net.ws.server` (`TWebSocketServerRest` on top of `THttpServer`) and the modern async one in `mormot.net.ws.async` (`TWebSocketAsyncServerRest` on top of `THttpAsyncServer`). Both expose the same protocol-registration surface in `mormot.net.ws.core`. Pick async for any new project; the threaded stack is kept for compatibility and small deployments.

## Picking a server class

| You want                              | Use                          | Engine alias        |
|---------------------------------------|------------------------------|---------------------|
| WebSocket on top of REST, modern      | `TWebSocketAsyncServerRest`  | `useBidirAsync`     |
| WebSocket on top of REST, threaded    | `TWebSocketServerRest`       | `useBidirSocket`    |
| Raw WebSocket without REST routing    | `TWebSocketAsyncServer`      | (construct directly)|

`TRestHttpServer.WebSocketsEnable` returns the server instance. Call it once after `Create` and add protocols to `Server.WebSocketProtocols`.

## Protocols

A protocol describes the framing on the wire. Two ship in core:

- **`TWebSocketProtocolJson`** - text frames, JSON payload, no encryption. Easy to inspect with browser dev tools and `wscat`. Default choice during development.
- **`TWebSocketProtocolBinary`** - binary frames with optional AES-256-CFB encryption (when you supply a non-empty key). Significantly smaller on the wire and the only sane choice for high-throughput or cross-WAN traffic.

Protocols are matched against the `Sec-WebSocket-Protocol` header during the upgrade handshake; the client lists protocol names in priority order, the server picks the first match. There are also `TWebSocketProtocolChat` (lightweight text channel) and `TWebSocketEngineIOProtocol` / `TWebSocketSocketIOProtocol` (Engine.IO and Socket.IO compatibility) for specialized cases.

## Frame protocol primer

A WebSocket frame has an opcode (continuation, text, binary, close, ping, pong), a length, an optional masking key (always present from clients), and the payload. mORMot abstracts the frame layer; you operate on `TWebSocketFrame` records and `TWebSocketProcess` events.

Two facts that bite people:

1. **Fragmentation**: a single logical message can arrive as a sequence of frames (one with opcode 1 or 2, the rest with opcode 0). mORMot reassembles before raising the message event, but if you are sniffing a connection you will see partial payloads.
2. **Control frames** (close/ping/pong) can be interleaved between fragments. The framework handles ping/pong automatically; you only see closes via the disconnect event.

## Binary vs text choice

| Trait                            | `TWebSocketProtocolJson` | `TWebSocketProtocolBinary` |
|----------------------------------|--------------------------|----------------------------|
| Wire format                      | UTF-8 JSON               | mORMot binary record DSL   |
| Inspectable in browser dev tools | Yes                      | No (hex blob)              |
| Encryption available             | No                       | AES-256-CFB if key set     |
| Typical payload size vs JSON     | 1.0x                     | 0.2x to 0.5x               |
| Schema evolution                 | Forgiving (extra fields) | Strict (RTTI versioned)    |

For internal service-to-service streams pick binary with a shared key. For browser SPA clients pick JSON; you can always tunnel binary inside a JSON envelope for the few payloads that need it.

## Server skeleton

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
  Ws := HttpServer.WebSocketsEnable(RestServer, 'shared-encryption-key', false);
  // 'shared-encryption-key' (non-empty) makes binary protocol use AES.
  // false = do not require ajax fallback over plain HTTP.
end;
```

For a custom (non-REST) protocol on a specific URI, register it explicitly:

```pascal
Ws.WebSocketProtocols.Add(
  TWebSocketProtocolJson.Create('chat', '/chatroom'));
```

The first arg is the protocol name negotiated in the handshake header; the second is the URI prefix that activates it.

## Client skeleton

```pascal
uses
  mormot.net.ws.client;

var
  Client: THttpClientWebSockets;
begin
  Client := THttpClientWebSockets.WebSocketsConnect(
    'localhost:8080',                      // host:port
    'shared-encryption-key',               // must match the server
    TWebSocketProtocolJson.Create('chat', '/chatroom'));
  // ... use Client.WebSockets.Sender.SendFrame ...
end;
```

The client owns the registered protocol instance and reuses it for every frame.

## Testing

For human testing, JSON protocol is straightforward to drive with `wscat -c ws://host:port/path -s chat`. For binary protocol, write a Pascal test client that imports the same protocol class and the same key as the server; that is the only sane way to validate the encrypted framing.

mORMot's own test suite (`test.net.async`) runs both stacks against each other; treat it as the executable spec for tricky framing edge cases.

## Backpressure for broadcasts

A common shape: one server broadcasts to N clients. Each WebSocket connection has its own outgoing queue. If one slow client cannot drain frames as fast as you produce them, that client's queue grows without bound and eventually exhausts memory. Mitigations:

- Cap per-connection queue length and disconnect on overflow.
- Drop or coalesce stale frames (e.g., keep only the latest snapshot per topic).
- Move broadcast fan-out off the request thread into a dedicated dispatcher with a bounded ring buffer.

`TWebSocketProcess.NotifyCallback` returns the queue depth; sample it under load and decide on a policy.
