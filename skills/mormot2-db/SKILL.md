---
name: mormot2-db
description: Use when working with raw SQL providers (TSqlDBConnection, TSqlDBStatement), choosing/configuring database engines (SQLite, PostgreSQL, MSSQL, Oracle, MongoDB, ZEOS, ODBC), thread-safe connection pooling, or BSON/Mongo data shapes. Do NOT use for ORM (use mormot2-orm) or REST (use mormot2-rest-soa).
---

# mormot2-db

mORMot 2 data access layer: raw SQL connections through `TSqlDBConnectionProperties`, prepared statements via `TSqlDBStatement`, per-thread connection pools, engine-specific dialect adaptation, and MongoDB / BSON for document workloads. This skill is authoritative for the `mormot.db.sql.*`, `mormot.db.raw.*`, and `mormot.db.nosql.*` namespaces. It deliberately bypasses Delphi's `TDataSet` / `DB.pas` stack: simpler API, JSON-native results, explicit thread safety. Sibling skills cover adjacent concerns: `mormot2-orm` is the declarative `TOrm` layer that may sit on top of these connections, `mormot2-rest-soa` exposes them over HTTP, `mormot2-deploy` covers static-library bundling for single-binary deployment.

## When to use

- Opening a connection through a provider-specific `TSqlDBConnectionProperties` subclass (`TSqlDBSQLite3ConnectionProperties`, `TSqlDBPostgresConnectionProperties`, `TSqlDBOracleConnectionProperties`, `TSqlDBOleDBMSSQLConnectionProperties`, `TSqlDBOdbcConnectionProperties`, `TSqlDBZeosConnectionProperties`).
- Running raw SQL via `Conn.Execute`, `Conn.ExecuteNoResult`, `Conn.ExecuteInlined`, or `NewStatementPrepared` + `Bind` + `ExecutePrepared` + `Step`.
- Sizing or tuning the per-thread connection pool on a `TSqlDBConnectionPropertiesThreadSafe` descendant.
- Adapting LIMIT / TOP / ROWNUM dialect for a SELECT that must run portably across engines, via `SqlLimitClause` and `DB_SQLLIMITCLAUSE[TSqlDBDefinition]`.
- Talking to MongoDB through `TMongoClient`, `TMongoDatabase`, `TMongoCollection`, including aggregation pipelines and BSON construction.
- Converting between BSON and JSON / `TDocVariant` (`BsonVariant`, `BsonToJson`).
- Exposing a remote SQL connection over HTTP via `mormot.db.proxy.pas` (`TSqlDBSocketConnectionProperties`, `TSqlDBHttpRequestConnectionProperties`).

## When NOT to use

- Defining `TOrm` classes, `TOrmModel`, or virtual tables. Use **mormot2-orm**.
- Exposing the data layer as REST endpoints, interface-based services, or session-aware SOA. Use **mormot2-rest-soa**.
- Bundling SQLite / OpenSSL / Zstd static libraries into a single binary, or wiring a service / daemon. Use **mormot2-deploy**.
- TLS termination, ACME, or HTTP transport for a remote-DB proxy front. Use **mormot2-net**.
- Password hashing, ECC keys, JWT for connection authentication. Use **mormot2-auth-security** for the crypto primitives, this skill for the DB layer that consumes them.
- `RawUtf8`, `TDocVariant`, custom RTTI registration. Use **mormot2-core**.

## Core idioms

### 1. Pick a provider class

`TSqlDBConnectionProperties` is the abstract factory. You always instantiate a concrete subclass; pick by engine.

```pascal
uses
  mormot.db.sql,
  mormot.db.sql.sqlite3,
  mormot.db.sql.postgres,
  mormot.db.sql.oracle,
  mormot.db.sql.oledb,
  mormot.db.sql.odbc,
  mormot.db.sql.zeos;

var
  Props: TSqlDBConnectionProperties;
begin
  // SQLite3 (file path goes in aServerName; the rest is ignored).
  Props := TSqlDBSQLite3ConnectionProperties.Create('data.db3', '', '', '');

  // PostgreSQL (libpq; aServerName is host[:port], aDatabaseName accepts a URI).
  Props := TSqlDBPostgresConnectionProperties.Create(
    'localhost:5432', 'mydb', 'app_user', 'secret');

  // Microsoft SQL Server via OleDB.
  Props := TSqlDBOleDBMSSQLConnectionProperties.Create(
    'sqlsrv\INSTANCE', 'mydb', 'sa', 'secret');

  // Oracle (native OCI; aServerName is the TNS alias or EZCONNECT).
  Props := TSqlDBOracleConnectionProperties.Create(
    '//db.example.com/ORCLPDB1', '', 'app_user', 'secret');

  // ODBC (any DSN).
  Props := TSqlDBOdbcConnectionProperties.Create('DSN=mydsn', '', 'user', 'pass');

  // Zeos (cross-database, drives many engines via ZDBC).
  Props := TSqlDBZeosConnectionProperties.Create(
    'postgresql://localhost:5432/mydb', '', 'user', 'pass');
end;
```

`Props` is the *factory*, not a connection. It manages per-thread connections internally.

### 2. Get a thread-safe connection

`TSqlDBConnection` instances are *not* thread-safe; mORMot binds one connection per thread via `ThreadSafeConnection`. Anything except the simplest single-threaded tools should go through this property.

```pascal
var
  Conn: TSqlDBConnection;
begin
  Conn := Props.ThreadSafeConnection; // safe to call from any worker thread
  // Conn is owned by Props; do NOT free it.
end;
```

Most mORMot providers descend from `TSqlDBConnectionPropertiesThreadSafe`, which keeps a `fConnectionPool` indexed by `TSynLog.ThreadIndex`. SQLite3 is the exception: its provider derives directly from `TSqlDBConnectionProperties` and uses a single shared connection (the engine itself serializes writes).

### 3. Execute SQL with parameters

Two shapes. Pick by need.

```pascal
uses
  mormot.db.sql;

// Shape A: high-level Execute, returns ISqlDBRows (auto-Free).
var
  Rows: ISqlDBRows;
begin
  Rows := Conn.Execute(
    'SELECT id, email FROM users WHERE role=? AND active=?',
    ['admin', true]);
  while Rows.Step do
    Writeln(Rows.ColumnInt(0), ' ', Rows.ColumnUtf8(1));
end;

// Shape B: NewStatementPrepared for cached prepared statements (binary-friendly).
var
  Stmt: ISqlDBStatement;
begin
  Stmt := Conn.NewStatementPrepared(
    'SELECT id, email FROM users WHERE role=? AND active=?',
    {ExpectResults=}true,
    {RaiseExceptionOnError=}true);
  Stmt.BindTextU(1, 'admin');
  Stmt.Bind(2, true);
  Stmt.ExecutePrepared;
  while Stmt.Step do
    Writeln(Stmt.ColumnInt(0), ' ', Stmt.ColumnUtf8(1));
end;
```

`NewStatementPrepared` caches by SQL text per connection; reusing the same statement many times pays the prepare cost once. Always use `?` placeholders. mORMot rewrites them to `:AA`, `$1`, etc., per engine.

### 4. Adapt LIMIT across engines

Each engine spells row-limit differently. The framework exposes the dialect through `DB_SQLLIMITCLAUSE[TSqlDBDefinition]` and `TSqlDBConnectionProperties.SqlLimitClause`; the ORM external layer consumes it via `TRestStorageExternal.AdaptSqlForEngineList`.

```pascal
uses
  mormot.db.core,
  mormot.db.sql;

// DB_SQLLIMITCLAUSE encodes how each engine writes "first N rows":
//   dOracle    -> WHERE rownum<=N
//   dMSSQL     -> SELECT TOP(N) ...
//   dMySQL / dSQLite / dPostgreSQL -> ... LIMIT N
//   dFirebird  -> SELECT FIRST N ...
//
// Inside the ORM, the rewrite is automatic when you go through TRestStorageExternal.
// Outside the ORM, query the clause and assemble it yourself via SqlLimitClause.
```

If you write hand-tuned SQL that must run on Oracle and SQLite (for example), do not hardcode `LIMIT`. Either route through the ORM external storage (`mormot2-orm`) or branch on `Props.Dbms`.

### 5. MongoDB: client, database, collection

`TMongoClient` owns the wire connection; databases and collections are lazily resolved.

```pascal
uses
  mormot.db.nosql.bson,
  mormot.db.nosql.mongodb;

var
  Client: TMongoClient;
  DB: TMongoDatabase;
  Coll: TMongoCollection;
begin
  Client := TMongoClient.Create('localhost', MONGODB_DEFAULTPORT);
  try
    DB := Client.Open('mydb');                 // unauthenticated
    // DB := Client.OpenAuth('mydb', 'user', 'pass'); // SCRAM-SHA-256 by default
    Coll := DB.Collection['users'];

    // Insert a document built from BSON name/value pairs.
    Coll.Insert([BsonVariant([
      'email', 'alice@example.com',
      'role',  'admin',
      'createdAt', NowUtc])]);

    // Aggregation pipeline returning a TDocVariant array.
    Writeln(VariantSaveJson(Coll.AggregateDoc(
      '[{$match:{role:?}},{$group:{_id:null,count:{$sum:1}}}]', ['admin'])));
  finally
    Client.Free; // releases all TMongoDatabase / TMongoCollection / TMongoConnection
  end;
end;
```

`Client.Free` is the only finalizer you need; the client owns the database, collection, and connection trees.

### 6. BSON and TDocVariant interop

BSON is the wire format; `TDocVariant` is the in-memory shape mORMot uses everywhere else. The two convert in O(1) terms of code.

```pascal
uses
  mormot.core.variants,
  mormot.db.nosql.bson;

var
  V: variant;
  Json, Bson: RawUtf8;
begin
  // Build a TDocVariant document from JSON.
  V := _Json('{"email":"alice@example.com","role":"admin"}');

  // Send it as BSON over the wire.
  Bson := Bson(_Safe(V)^);

  // Receive BSON, decode to JSON for inspection / logs.
  Json := BsonToJson(pointer(Bson), betDoc, length(Bson), modMongoStrict);
end;
```

Treat `BsonVariant(...)` as the canonical "build a Mongo document literal" call; it stays in BSON form internally, which avoids JSON ↔ BSON ping-pong on hot paths.

## Common pitfalls

- **Sharing one `TSqlDBConnection` across threads.** `TSqlDBConnection` is *not* thread-safe; only the `Props.ThreadSafeConnection` accessor is. A worker thread that captures a `Conn` reference outside `ThreadSafeConnection` and uses it on a different thread will corrupt the prepared-statement cache and (on Oracle / OleDB) crash the driver. Always re-fetch `ThreadSafeConnection` inside the thread that uses it. For SQLite3 / Firebird embedded, set `Props.ThreadingMode := tmMainConnection` so all threads serialize on a single connection instead of opening a pool the engine can't support.
- **Oracle field width above 1333 chars.** Oracle's `VARCHAR2` caps at 4000 bytes; mORMot stores text as UTF-8, so the practical character ceiling is 1333 (4000 / 3 for worst-case multi-byte encoding). Properties / columns wider than that must be `CLOB`. Symptom on insert: `ORA-01401` or silent truncation depending on driver mode. Match with `index 1333` on the Pascal side, or switch to a TEXT/CLOB type.
- **Pool exhaustion under bursty load.** `TSqlDBConnectionPropertiesThreadSafe` allocates one connection per `TSynLog.ThreadIndex`. A short-lived flood of worker threads (e.g. an HTTP server with `useHttpAsync` and a giant pool) opens that many DB connections, and the database side hits its own connection cap (PostgreSQL `max_connections`, Oracle session limits) before mORMot does. Cap the HTTP worker pool to what the DB can sustain, or switch to `tmMainConnection` for read-mostly workloads. `Props.ConnectionTimeOutMinutes` releases idle pool slots; tune it down on long-tail workloads.
- **BSON / JSON identity assumptions.** `BsonToJson` and `_Json` round-trip the *shape*, not the binary identity: BSON dates become ISO 8601 strings, ObjectIds become hex strings, decimals become numeric. A document hashed before and after the round-trip will not match. If you need stable hashing for replication or signatures, hash the BSON bytes directly via `Bson(...)`, never the JSON projection.
- **Forgetting hints on MongoDB queries that should use an index.** Mongo's planner is good but not telepathic. If a query plan unexpectedly does a `COLLSCAN`, attach a `$hint` in the aggregation pipeline or use the `Find` overload that takes an index name. The framework does not auto-hint based on declared indexes; that is your job at query time.
- **Keeping a reference to a `TMongoCollection` after `Client.Free`.** `TMongoClient` owns the entire object tree (database, collection, connection). Holding a stale `TMongoCollection` past the client's destruction crashes the next call into freed memory. Scope collections to the client's lifetime, or wrap acquisition in a helper that re-resolves through `Client.Database['x'].Collection['y']` on each use.
- **Mixing prepared and ad-hoc execution against a cached statement.** `NewStatementPrepared` caches by exact SQL text. `Conn.Execute(SqlText, ...)` and `Conn.NewStatementPrepared(SqlText, true)` against the *same* SQL share the cache slot only when the text is byte-for-byte identical. Trailing whitespace, different quote styles, or generated IN-list lengths produce a cache miss every call. Normalize SQL text upstream of the cache.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-07.md` - SQL Database Access
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-08.md` - SQLite3 Database
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-09.md` - External NoSQL (MongoDB)
- `references/providers-matrix.md`
- `references/thread-safety.md`
- `references/bson-mongodb.md`
- `mormot2-core` for `RawUtf8`, `TDocVariant`, `TSynLocker`
- `mormot2-orm` for `TOrm` / `TOrmModel` on top of these connections
- `mormot2-rest-soa` for exposing the data layer over REST/SOA
- `mormot2-deploy` for SQLite / OpenSSL static-library bundling
