# TOrm Cheatsheet

`TOrm` is the base class for every ORM-mapped table. Each `published` property becomes a column. Pick the right Pascal type and the SQL type follows automatically.

## Pascal type to SQL type

| Pascal type      | SQL type (SQLite / generic)         | Notes                                              |
|------------------|-------------------------------------|----------------------------------------------------|
| `RawUtf8`        | `TEXT`                              | Default text type. Use `index N` to cap to VARCHAR(N). |
| `string`         | `TEXT`                              | Avoid. Pays UTF-16 round trips. Use `RawUtf8`.     |
| `integer`        | `INTEGER` (32-bit)                  | Use for small counts / enums.                      |
| `Int64`          | `INTEGER` (64-bit)                  | Default for IDs and large counters.                |
| `boolean`        | `INTEGER` (0/1)                     | Stored as 0 or 1; queried via `=0` / `=1`.         |
| `currency`       | `INTEGER` (cents x 10000)           | 4 implicit decimals; never use `double` for money. |
| `double`         | `FLOAT`                             | Floating-point only when imprecision is acceptable.|
| `TDateTime`      | `TEXT` (ISO 8601)                   | Stored as `YYYY-MM-DDTHH:NN:SS.ZZZ`, sortable.     |
| `TDateTimeMS`    | `TEXT` (ISO 8601 with ms)           | When millisecond precision matters.                |
| `TTimeLog`       | `INTEGER`                           | Compact timestamp; faster sort/filter than TEXT.   |
| `TOrm`           | `INTEGER` (foreign-key RowID)       | Stores the linked row's ID; declare as `TOrmUser`. |
| `RawBlob`        | `BLOB`                              | Binary; not loaded by default `Retrieve`.          |
| `variant`        | `TEXT` (JSON)                       | TDocVariant payload, schema-less.                  |

## Property attribute legend

| Attribute        | Effect                                                           | Example                                    |
|------------------|------------------------------------------------------------------|--------------------------------------------|
| `index N`        | Caps `RawUtf8` to N chars (SQL `VARCHAR(N)`); ignored for others | `property Email: RawUtf8 index 120 ...`    |
| `stored AS_UNIQUE` | Adds `UNIQUE NOT NULL` to the column                           | `... stored AS_UNIQUE;`                    |
| `stored false`   | Excludes the property from persistence and JSON                  | Useful for derived/computed properties     |
| `default V`      | Default value at INSERT time (Delphi syntax: `default 0`)        | `property Active: boolean default 1 ...`   |
| `width M`        | Suggested display width (consumers like UI grids honor this)     | `property Note: RawUtf8 width 200 ...`     |

## TOrm and RowID mental model

- `TOrm` already declares `property ID: TID`. Do NOT redeclare it in your subclass.
- `RowID` is the SQL column name; `ID` is the Pascal alias. Both refer to the same value.
- Set `ID := 0` before `Add`; the ORM assigns the new row's ID back into the instance.
- After `Retrieve(SomeID, MyOrm)`, `MyOrm.ID = SomeID`. Mutating it locally and calling `Update` is undefined behavior.

## Common verbs

```pascal
// Add
NewID := Rest.Orm.Add(User, true); // SendData=true ships the field values

// Update
Rest.Orm.Update(User);

// Retrieve by ID
if Rest.Orm.Retrieve(42, User) then
  ...;

// Retrieve list
Json := Rest.Orm.RetrieveListJson(TOrmUser, 'Role=?', ['admin']);

// Delete
Rest.Orm.Delete(TOrmUser, 42);
```

## Anti-patterns

- Overriding `Create` without calling `inherited Create`. The base constructor builds the property table.
- Storing currency as `double`. Use `currency` for money.
- Declaring a `Password: RawUtf8` field and calling it secure. The ORM stores it as TEXT in plain. Hash before assigning, or move auth to `mormot2-auth-security`.
- Using `Retrieve` in a loop to fetch N rows. Use `RetrieveListJson` or a `TOrmTableJson` instead.
