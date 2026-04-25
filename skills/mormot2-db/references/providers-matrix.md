# Providers Matrix

mORMot 2 ships a connection-properties class per supported engine. The class wires the right driver, picks the right `TSqlDBDefinition` (which drives dialect adaptation), and decides whether the per-thread pool is used. Pick deliberately; the wrong provider for the workload costs you either throughput or correctness.

## Direct providers (recommended where available)

| Engine        | Connection-properties class                     | Unit                                | Runtime dependency                                  | LIMIT syntax          | Pool model                       |
|---------------|-------------------------------------------------|-------------------------------------|-----------------------------------------------------|-----------------------|----------------------------------|
| SQLite3       | `TSqlDBSQLite3ConnectionProperties`             | `mormot.db.sql.sqlite3`             | None (static via `mormot.db.raw.sqlite3.static`) or `sqlite3.dll` / `libsqlite3.so` | `... LIMIT N`         | Single-connection (no pool)      |
| PostgreSQL    | `TSqlDBPostgresConnectionProperties`            | `mormot.db.sql.postgres`            | `libpq` (must be thread-safe; runtime check fails fast otherwise)                   | `... LIMIT N`         | Per-thread (`ThreadSafe`)        |
| Oracle        | `TSqlDBOracleConnectionProperties`              | `mormot.db.sql.oracle`              | OCI client (`oci.dll` / `libclntsh.so`); set `OCI_CHARSET=AL32UTF8`                 | `WHERE rownum<=N`     | Per-thread (`ThreadSafe`)        |
| ODBC (any)    | `TSqlDBOdbcConnectionProperties`                | `mormot.db.sql.odbc`                | OS ODBC manager (`odbc32.dll` / `libodbc.so`)                                       | Engine-defined        | Per-thread (`ThreadSafe`)        |
| Firebird (IBX)| `TSqlDBIbxConnectionProperties`                 | `mormot.db.sql.ibx`                 | `fbclient.dll` / `libfbclient.so`                                                   | `SELECT FIRST N ...`  | Per-thread (`ThreadSafe`)        |
| MS SQL Server | `TSqlDBOleDBMSSQLConnectionProperties` (and 2005/2012/2018 variants) | `mormot.db.sql.oledb`  | OleDB / MSOLEDBSQL provider (Windows only)                                          | `SELECT TOP(N) ...`   | Per-thread (`ThreadSafe`)        |
| MS SQL via ODBC| `TSqlDBOdbcConnectionProperties` (DSN to MSSQL) | `mormot.db.sql.odbc`                | ODBC driver for SQL Server                                                          | `SELECT TOP(N) ...`   | Per-thread (`ThreadSafe`)        |
| Oracle via OleDB | `TSqlDBOleDBMSOracleConnectionProperties`    | `mormot.db.sql.oledb`               | OraOLEDB provider (Windows only)                                                    | `WHERE rownum<=N`     | Per-thread (`ThreadSafe`)        |
| MySQL via OleDB | `TSqlDBOleDBMySQLConnectionProperties`        | `mormot.db.sql.oledb`               | MySQL OleDB provider (Windows only)                                                 | `... LIMIT N`         | Per-thread (`ThreadSafe`)        |
| MS Access (Jet/ACE) | `TSqlDBOleDBJetConnectionProperties` / `TSqlDBOleDBACEConnectionProperties` | `mormot.db.sql.oledb` | Jet 4.0 / ACE OLE DB (Windows only)                                                 | `SELECT TOP N ...`    | Per-thread (`ThreadSafe`)        |

## Cross-engine bridge

| Bridge        | Connection-properties class            | Unit                       | Runtime dependency                          | Notes                                                                                        |
|---------------|----------------------------------------|----------------------------|---------------------------------------------|----------------------------------------------------------------------------------------------|
| Zeos / ZDBC   | `TSqlDBZeosConnectionProperties`       | `mormot.db.sql.zeos`       | ZDBC libraries + native client per engine   | Single class, many engines. Lower performance ceiling than direct providers; use when you must support multiple engines from one binary and direct providers are missing. |

## TDataSet RAD bridges (legacy interop)

| Bridge        | Class                                       | Unit                          | When to use                                                                                  |
|---------------|---------------------------------------------|-------------------------------|----------------------------------------------------------------------------------------------|
| FireDAC       | `TSqlDBFireDacConnectionProperties`         | `mormot.db.rad.firedac`       | Existing Delphi codebase already invested in FireDAC; want JSON output and mORMot tooling.   |
| UniDAC        | `TSqlDBUniDACConnectionProperties`          | `mormot.db.rad.unidac`        | Same logic, UniDAC stack.                                                                    |
| BDE           | `TSqlDBBdeConnectionProperties`             | `mormot.db.rad.bde`           | Legacy BDE only; do not pick this for new code.                                              |
| NexusDB       | `TSqlDBNexusDBConnectionProperties`         | `mormot.db.rad.nexusdb`       | NexusDB embedded / client-server.                                                            |

## Remote proxy (HTTP-fronted)

| Class                                         | Unit                  | Wire protocol               | Use for                                                                              |
|-----------------------------------------------|-----------------------|-----------------------------|--------------------------------------------------------------------------------------|
| `TSqlDBSocketConnectionProperties`            | `mormot.db.proxy`     | mORMot binary over TCP      | Lowest-overhead in-DC tunnel.                                                        |
| `TSqlDBHttpRequestConnectionProperties`       | `mormot.db.proxy`     | HTTP/HTTPS (THttpRequest)   | Generic HTTP relay; pick a concrete subclass for the actual client.                  |
| `TSqlDBCurlConnectionProperties`              | `mormot.db.proxy`     | HTTP/HTTPS via libcurl      | Cross-platform HTTP relay where libcurl is already deployed.                         |
| `TSqlDBWinHttpConnectionProperties`           | `mormot.db.proxy`     | WinHTTP                     | Windows-only deployments; uses the WinHTTP stack (services, no UI).                  |
| `TSqlDBWinINetConnectionProperties`           | `mormot.db.proxy`     | WinINet                     | Windows-only deployments that already share IE / browser proxy config.               |

## NoSQL

| Engine    | Class            | Unit                          | Runtime dependency               | Notes                                                                          |
|-----------|------------------|-------------------------------|----------------------------------|--------------------------------------------------------------------------------|
| MongoDB   | `TMongoClient`   | `mormot.db.nosql.mongodb`     | None (pure-Pascal wire client)   | Speaks OP_MSG by default (MongoDB 5.1+); define `MONGO_OLDPROTOCOL` for < 3.6. |

## Pool sizing rules

`TSqlDBConnectionPropertiesThreadSafe` (the parent of every networked direct provider) allocates one connection per `TSynLog.ThreadIndex` slot. There is no explicit "pool size" knob; the pool grows up to the number of distinct worker threads that touch the connection. To control max connections, control max threads at the layer above.

Recommended ceilings:

| Workload                        | Worker threads ≈ pool size            | Reason                                                                              |
|---------------------------------|---------------------------------------|-------------------------------------------------------------------------------------|
| OLTP API on PostgreSQL          | 8 to 32                               | PG default `max_connections=100`; keep room for replicas / admins.                  |
| Reporting on Oracle             | 4 to 16                               | Oracle session licensing matters; each session is heavy.                            |
| SQLite3 (embedded)              | Set `ThreadingMode := tmMainConnection` | The engine serializes writes; multiple connections add no throughput.               |
| Firebird embedded               | Set `ThreadingMode := tmMainConnection` | Same reasoning.                                                                     |
| MongoDB                         | Bound by `TMongoClient` socket count  | Mongo client already pools internally; one `TMongoClient` per service is enough.    |

`Props.ConnectionTimeOutMinutes` (default 0 = no timeout) reaps idle pool slots. Set it to 5 to 15 minutes on bursty workloads so cold threads don't hold sessions forever. `Props.ClearConnectionPool` is the explicit "drop everything" operation; call it on configuration reload.
