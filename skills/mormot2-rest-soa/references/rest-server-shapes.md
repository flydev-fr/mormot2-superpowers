# REST Server Shapes

`TRestServer` is the abstract base for every mORMot 2 REST server. Two concrete descendants ship in the framework, plus an HTTP wrapper that bolts a transport in front. Pick the shape that matches your storage and deployment profile, then layer the HTTP server from `mormot2-net` on top.

## Concrete server classes

| Class                      | Storage                              | Unit                            | Use when                                                                 |
|----------------------------|--------------------------------------|---------------------------------|--------------------------------------------------------------------------|
| `TRestServerDB`            | SQLite3 file (or `:memory:`)         | `mormot.rest.sqlite3`           | Default. Local DB, embedded, single-process. Fast, transactional.        |
| `TRestServerFullMemory`    | In-process arrays + optional JSON file | `mormot.rest.memserver`       | Lightweight, no SQLite link. Cache layer, tests, ephemeral state.        |
| `TRestServerRemoteDB`      | Proxies ORM verbs to another `TRest` | `mormot.rest.core` and friends  | Federate two REST nodes; the local server speaks ORM but stores nothing. |

External SQL providers (PostgreSQL, MSSQL, Oracle, FireDAC, ZEOS) plug in via `TOrmVirtualTableExternal` on `TRestServerDB`. There is no separate `TRestServerExternalDB` class; you bind a virtual table to your ORM model. See `mormot2-db` for connection-side configuration and `mormot2-orm/references/virtual-tables.md` for the registration pattern.

## TRestServerDB - the default

```pascal
uses mormot.rest.sqlite3;

Server := TRestServerDB.Create(Model, 'app.db3');
Server.Server.CreateMissingTables;
```

SQLite features available: WAL, FTS, RTree, JSON1, custom collations. The DB file lives next to the executable by default; pass an absolute path for production.

## TRestServerFullMemory - SQLite-free

```pascal
uses mormot.rest.memserver;

Server := TRestServerFullMemory.Create(Model, 'backup.json');
// Reads backup.json on startup if present, writes on UpdateToFile / Free.
```

Shape:
- All rows held in arrays; queries iterate in memory.
- Persistence is one big JSON snapshot. Crash-safe at file-write boundaries only.
- Best for caches, configuration servers, fixtures, or units where pulling SQLite is too heavy.

## TRestHttpServer - the transport wrapper

`TRestHttpServer` (unit `mormot.rest.http.server`, owned by `mormot2-net`) wraps one or more `TRestServer` instances and serves them over HTTP/HTTPS/WebSocket. The REST/SOA layer does not care which engine is chosen; that is `mormot2-net`'s job.

```pascal
uses mormot.rest.http.server; // see mormot2-net for engine choice

HttpServer := TRestHttpServer.Create('8080', [Server], '+', useHttpAsync);
```

You can register multiple `TRestServer` instances (different roots) on a single port. The HTTP layer multiplexes by `Root`.

## In-process client without HTTP

For tests and tightly-coupled processes, `TRestClientDB` (unit `mormot.rest.sqlite3`) talks to a `TRestServerDB` over a direct in-memory channel - same JSON pipeline, no socket. Useful for unit tests of services without standing up a real HTTP listener.

```pascal
Client := TRestClientDB.Create(Model, nil, ':memory:', TRestServerDB);
```

## Picking the shape

| Need                                                  | Pick                              |
|-------------------------------------------------------|-----------------------------------|
| Local app DB, persisted, transactional                | `TRestServerDB`                   |
| Fast in-memory cache, no SQLite link                  | `TRestServerFullMemory`           |
| Mirror an external SQL provider                       | `TRestServerDB` + `TOrmVirtualTableExternal` |
| Aggregate two REST nodes                              | `TRestServerRemoteDB`             |
| Test a service without sockets                        | `TRestClientDB` + `TRestServerDB` |
| Expose any of the above over HTTP/WS                  | wrap with `TRestHttpServer` (mormot2-net) |
