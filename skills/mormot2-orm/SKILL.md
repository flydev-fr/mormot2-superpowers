---
name: mormot2-orm
description: Use when defining TOrm classes, building TOrmModel, mapping fields with attributes, configuring virtual tables, or ORM CRUD. Do NOT use for raw SQL (use mormot2-db) or REST (use mormot2-rest-soa).
---

# mormot2-orm

mORMot 2 ORM layer: declarative `TOrm` classes, `TOrmModel` schema definition, field attribute mapping, virtual tables, and CRUD/batch operations through `TRest` descendants. This skill is authoritative for the `mormot.orm.*` namespace and assumes the conventions defined in `mormot2-core` (RawUtf8 strings, custom RTTI, layered uses). Sibling skills extend this layer: `mormot2-rest-soa` exposes models over HTTP/REST, `mormot2-db` handles raw SQL when the ORM is the wrong tool.

## When to use

- Defining a `TOrm` descendant with typed published properties.
- Building a `TOrmModel` from a list of `TOrm` classes (single or multi-database).
- Mapping field attributes (`stored AS_UNIQUE`, `index N`, `width M`, `default`).
- Configuring virtual tables (`TOrmVirtualTableJson`, `TOrmVirtualTableCsv`, `TOrmVirtualTableExternal`).
- ORM CRUD via `TRest.Add`, `TRest.Update`, `TRest.Retrieve`, `TRest.Delete`.
- Batch operations via `TRestBatch` (insert/update/delete sequences with one round-trip commit).

## When NOT to use

- Raw SQL queries, joins, or custom DDL. Use **mormot2-db**.
- Exposing the ORM as REST endpoints, interface-based services, or SOA contracts. Use **mormot2-rest-soa**.
- Authentication, sessions, JWT, password hashing. Use **mormot2-auth-security** for the crypto, **mormot2-rest-soa** for the REST session lifecycle.
- Foundational types (`RawUtf8`, `TDocVariant`), unit ordering, custom record RTTI. Use **mormot2-core**.

## Core idioms

### 1. Defining a TOrm class

Every persisted field is a `published` property with a mORMot-friendly type. RowID is implicit; do not declare it.

```pascal
uses
  mormot.core.base,
  mormot.orm.core;

type
  TOrmUser = class(TOrm)
  private
    fEmail: RawUtf8;
    fRole:  RawUtf8;
    fLogon: TDateTime;
  published
    property Email: RawUtf8   read fEmail write fEmail;
    property Role:  RawUtf8   read fRole  write fRole;
    property Logon: TDateTime read fLogon write fLogon;
  end;
```

### 2. Building a TOrmModel

A model is the schema. Pass it to the `TRest` (server or client). Free it during shutdown after the `TRest` is gone.

```pascal
uses
  mormot.orm.core;

var
  Model: TOrmModel;
begin
  Model := TOrmModel.Create([TOrmUser, TOrmRole, TOrmAuditLog]);
  try
    // pass Model to TRestServerDB.Create / TRestClientDB.Create
  finally
    Model.Free; // after the TRest is destroyed
  end;
end;
```

### 3. Unique index and width attributes

`stored AS_UNIQUE` adds a SQL UNIQUE constraint; `index N` sets max length for `RawUtf8` (SQL `VARCHAR(N)`). Both are declarative and read by the ORM at model-creation time.

```pascal
type
  TOrmUser = class(TOrm)
  published
    property Email: RawUtf8 index 120 read fEmail write fEmail
      stored AS_UNIQUE; // SQL: VARCHAR(120) UNIQUE NOT NULL
    property Slug:  RawUtf8 index 64  read fSlug  write fSlug;
  end;
```

### 4. Registering a virtual table

A virtual table maps a `TOrm` class to a non-SQLite backend (JSON file, CSV, external SQL connection). Register it on the model before opening the database.

```pascal
uses
  mormot.orm.core,
  mormot.orm.storage;

var
  Model: TOrmModel;
begin
  Model := TOrmModel.Create([TOrmCsvRow]);
  Model.VirtualTableRegister(TOrmCsvRow, TOrmVirtualTableJson); // or Csv / External
  // ORM verbs (Retrieve, RetrieveListJson, Add) work transparently against the backend.
end;
```

### 5. Batch insert with commit at end

`TRestBatch` queues operations and ships them in a single round trip. Use it for bulk imports, scheduled syncs, or any path that touches many rows.

```pascal
uses
  mormot.orm.core;

var
  Batch: TRestBatch;
  User: TOrmUser;
  i: Integer;
begin
  Batch := TRestBatch.Create(Server.Orm, TOrmUser, 1000);
  try
    User := TOrmUser.Create;
    try
      for i := 0 to High(Inputs) do
      begin
        User.Email := Inputs[i].Email;
        User.Role  := 'member';
        Batch.Add(User, true);
      end;
    finally
      User.Free;
    end;
    Server.Orm.BatchSend(Batch); // single commit
  finally
    Batch.Free;
  end;
end;
```

## Common pitfalls

- **Forgetting the `published` modifier.** Properties under `public` or `private` are invisible to RTTI and the ORM ignores them silently. Symptom: column missing from generated SQL, no error.
- **Naming a field after a SQL reserved word.** A property called `Group`, `Order`, `User`, or `Index` may compile but blow up at first SELECT. Either rename the Pascal property or alias the SQL name.
- **Modifying `TOrm.ID` directly.** The ORM owns `RowID`. Set it only via `Add` (which assigns the new ID back) or `Retrieve` (which reads it). Never declare a `published property ID` either; `TOrm` already exposes it.
- **Using `string` for persisted text fields.** Switch to `RawUtf8`. `string` will compile but every read/write pays a UTF-16 round trip, and JSON serialization may corrupt non-ASCII. See `mormot2-core` for the RawUtf8 boundary rule.
- **Leaking the model on shutdown.** `TOrmModel` is owned by your code, not by the `TRest`. After `Server.Free`, call `Model.Free`. Free in the wrong order and you double-free or leak RTTI structures.
- **Calling `Add` with `SendData=false` then expecting the row to come back.** `SendData` controls whether non-default fields are written. With `false` you get an empty row plus the new ID, not the values you set on the instance.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-05.md` - TOrm and TOrmModel
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-06.md` - ORM Daily Patterns
- `references/torm-cheatsheet.md`
- `references/torm-model-patterns.md`
- `references/virtual-tables.md`
- `mormot2-core` for RawUtf8 conventions and custom record RTTI
- `mormot2-db` for non-ORM SQL access
- `mormot2-rest-soa` for exposing the ORM as REST
