---
name: mormot2-core
description: Use when working with mORMot 2 core types (RawUtf8, RawByteString, TSynLocker, TDocVariant), mormot.defines.inc, unit order, JSON, or RTTI. Do NOT use for ORM/REST/DB/Net/Crypto: use sibling skills.
---

# mormot2-core

Foundational mORMot 2 layer: string and byte types, conditional defines, unit dependency order, JSON, RTTI registration, dynamic documents, and lightweight thread-safety primitives. This skill is authoritative for the `mormot.core.*` namespace and the `mormot.defines.inc` / `mormot.uses.inc` include files. Sibling skills (orm, rest-soa, db, net, auth-security) build on top of this layer and assume its conventions.

## When to use

- Choosing between `string`, `RawUtf8`, `RawByteString`, `WinAnsiString`, `SynUnicode`, or `UnicodeString` for a field, parameter, or return value.
- Setting or unsetting a toggle in `mormot.defines.inc` (PUREMORMOT2, FPC_X64MM, FPCMM_BOOST, FPCMM_SERVER, NEWRTTINOTUSED, NOPATCHVMT, NOPATCHRTL).
- Adding a `mormot.core.*` (or higher) unit to a `uses` clause and unsure of dependency order.
- Registering custom RTTI for a record or class so it serializes/deserializes through mORMot JSON.
- Working with `TDocVariant`, `IDocList`, or `IDocDict` for schema-less JSON-shaped data.
- Using `TSynLocker` or `TSynLocked` to protect shared state on a hot path without paying the cost of `TCriticalSection`.

## When NOT to use

- Defining `TOrm` classes, `TOrmModel`, or wiring an ORM virtual table. Use **mormot2-orm**.
- Building REST endpoints, interface-based services, or SOA contracts. Use **mormot2-rest-soa**.
- Writing raw SQL, configuring DB providers (PostgreSQL, MSSQL, MongoDB, ZEOS, FireDAC). Use **mormot2-db**.
- HTTP server/client work, WebSockets, TLS, or network buffer tuning. Use **mormot2-net**.
- JWT, signing, AES, OpenSSL bindings, or auth flows. Use **mormot2-auth-security**.

## Core idioms

### 1. RawUtf8 boundary conversions

Convert at the edge ONCE. Internally everything is `RawUtf8`. Touch `string` only at UI/RTL boundaries.

```pascal
uses
  mormot.core.base,
  mormot.core.unicode;

var
  utf8: RawUtf8;
  display: string;
begin
  utf8 := StringToUtf8(Edit1.Text); // VCL/UI -> internal (once, at the edge)
  // ... business logic uses utf8 only ...
  Edit1.Text := Utf8ToString(utf8); // internal -> VCL/UI (once, on the way out)
end;
```

### 2. TSynLocker

Stack-allocated, requires explicit `Init` and `Done`. Cheaper and more cache-friendly than `TCriticalSection` for short critical sections.

```pascal
uses
  mormot.core.os;

var
  Lock: TSynLocker;
  Counter: Integer;
begin
  Lock.Init;
  try
    Lock.Lock;
    try
      Inc(Counter);
    finally
      Lock.UnLock;
    end;
  finally
    Lock.Done;
  end;
end;
```

### 3. TDocVariant

Late-binding JSON-shaped variants. `_Json` builds from text, `_Obj` / `_Arr` build from in-memory arrays.

```pascal
uses
  mormot.core.variants;

var
  doc: variant;
begin
  doc := _Json('{"user":{"id":42,"name":"Ada"},"tags":["admin","beta"]}');
  WriteLn(doc.user.name);             // dotted path via late binding
  doc.user.email := 'ada@example.com'; // add new property
  TDocVariantData(doc).U['user.id'] := '42'; // typed path access via _Safe / typed cast
end;
```

### 4. Custom record RTTI

Use the text DSL once at startup so every `RecordSaveJson` / `RecordLoadJson` / `TJsonWriter.AddRecordJson` knows the field shape.

```pascal
uses
  mormot.core.rtti;

type
  TPriceRow = packed record
    Symbol: RawUtf8;
    Price:  currency;
    Ts:     TDateTime;
  end;

initialization
  Rtti.RegisterFromText(TypeInfo(TPriceRow),
    'Symbol:RawUtf8 Price:currency Ts:TDateTime');
end.
```

### 5. Layered uses (dependency order matters)

Lower layers never `uses` higher ones. Always include `mormot.core.base` first; pull `mormot.core.rtti` before `mormot.core.json` if you do custom serialization. For the memory manager, include `mormot.uses.inc` once in your `.dpr`.

```pascal
program myserver;
{$I mormot.defines.inc}
uses
  {$I mormot.uses.inc} // FPC_X64MM / FPCMM_BOOST etc. live here
  mormot.core.base,    // RawUtf8, PtrInt, primitive types
  mormot.core.os,      // TSynLocker, GetTickCount64
  mormot.core.unicode, // StringToUtf8 / Utf8ToString
  mormot.core.text,    // FormatUtf8, CSV
  mormot.core.rtti,    // Rtti.RegisterFromText
  mormot.core.variants,// TDocVariant
  mormot.core.json,    // TJsonWriter, GetJsonField
  // higher layers (orm/rest/net) come after.
  SysUtils;
```

## Common pitfalls

- **Mixing `string` and `RawUtf8` in business logic.** Each implicit cast is a UTF-16 <-> UTF-8 round trip. Pick `RawUtf8` everywhere except UI/RTL.
- **Importing `mormot.core.json` before `mormot.core.rtti`.** Custom RTTI registration must already be visible when JSON serializers initialize. Wrong order = "type not registered" at runtime.
- **Forgetting `{$I ..\mormot.defines.inc}` at the top of a unit.** Without it, conditionals like `FPC_X64MM` and `NEWRTTINOTUSED` are not seen and the unit compiles with the wrong feature set.
- **Using `TSynLocker` like `TCriticalSection`.** It is a stack-allocated record. You MUST call `Lock.Init` before first use and `Lock.Done` before it goes out of scope, or you leak the underlying OS primitive.
- **Reusing a `TJsonWriter` across threads without locking.** `TJsonWriter` is single-threaded by design. Either keep one per thread or guard it with a `TSynLocker`.
- **Storing binary blobs in `RawUtf8`.** Use `RawByteString` for binary; `RawUtf8` carries a UTF-8 codepage hint that some helpers will honor.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-04.md` - Core Units
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-03.md` - Unit Structure
- `references/raw-utf8-cheatsheet.md`
- `references/conditional-defines.md`
- `references/unit-hierarchy.md`
- `references/json-rtti-idioms.md`
- `mormot2-orm` for TOrm-specific RTTI
