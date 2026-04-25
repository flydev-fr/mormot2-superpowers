# Virtual Tables

A virtual table maps a `TOrm` class to a backend that is not the local SQLite table. The ORM verbs (`Add`, `Retrieve`, `RetrieveListJson`) keep working; the storage changes underneath.

## When to use a virtual table vs raw SQL

| Need                                                       | Pick                                  |
|------------------------------------------------------------|---------------------------------------|
| Read-only dataset already on disk (CSV, JSON file)         | `TOrmVirtualTableCsv` / `Json`        |
| In-memory cache with ORM verbs                             | `TOrmVirtualTableJson`                |
| Mirror an external SQL provider (PostgreSQL, MSSQL, etc.)  | `TOrmVirtualTableExternal` (+ mormot2-db) |
| One-off complex JOIN across tables                         | Raw SQL via `mormot2-db`              |
| Heavy bulk INSERT under transaction                        | Native SQLite + `TRestBatch`          |

If your access pattern is a single SELECT with custom JOINs and you do not need ORM serialization, drop to raw SQL. Virtual tables shine when the rest of the app already speaks ORM and one or two tables happen to live elsewhere.

## TOrmVirtualTableJson

Backs a table with an in-memory JSON store, optionally persisted to a `.json` file. Fast for small-to-medium datasets, no SQLite engine touch.

```pascal
uses
  mormot.orm.core,
  mormot.orm.storage;

var
  Model: TOrmModel;
begin
  Model := TOrmModel.Create([TOrmAuditLog]);
  Model.VirtualTableRegister(TOrmAuditLog, TOrmVirtualTableJson);
  // After TRestServerDB.Create, point storage at a file:
  // (Server.Server as TRestServerDB).StaticVirtualTable[TOrmAuditLog]
  //   .RootFolder := 'data/';
end;
```

## TOrmVirtualTableCsv

Read-only mapping of a CSV file as a table. Useful for ETL and reference data that ships with the app.

```pascal
Model.VirtualTableRegister(TOrmCsvRow, TOrmVirtualTableCsv);
// At runtime, point the storage at the file. Schema must match the CSV header.
```

CSV columns map by name to the published properties of the `TOrm` class. Mismatched names mean silent NULLs.

## TOrmVirtualTableExternal

Routes ORM operations to an external SQL connection (managed by `mormot.db.sql.*`, see `mormot2-db`). The class still inherits from `TOrm`, the schema still lives in `TOrmModel`, but rows live in PostgreSQL/MSSQL/Oracle/etc.

```pascal
Model.VirtualTableRegister(TOrmCustomer, TOrmVirtualTableExternal);
// Then bind via VirtualTableExternalRegister with a TSqlDBConnectionProperties.
```

Use this when the database is shared with non-mORMot consumers. ORM CRUD, REST exposure, and `TRestBatch` keep working; under the hood every operation hits the external SQL provider.

## Querying via the ORM's normal verbs

Once registered, the storage is transparent. Code that calls `Server.Orm.Retrieve` does not know whether the row came from SQLite, JSON, CSV, or PostgreSQL.

```pascal
Json := Server.Orm.RetrieveListJson(TOrmCustomer, 'Country=?', ['FR']);
```

This is the point of virtual tables: one ORM mental model, multiple storage backends. Where you cross over into raw SQL or provider-specific calls, the ORM stops covering for you and `mormot2-db` takes over.

## Pitfalls

- Registering the virtual table type AFTER the `TRest` is created. Register on the model before constructing the server.
- Mixing virtual-table classes with regular SQLite classes in the same JOIN. The query planner cannot always cross the boundary; split into two queries or use external SQL.
- Forgetting that CSV virtual tables are read-only. `Add` / `Update` will raise.
- Assuming external virtual tables are transactional like SQLite. They follow the external provider's semantics; wrap multi-row writes in an explicit transaction via `mormot2-db`.
