# Unit Hierarchy

mORMot 2 is layered. A unit at level N may `uses` units at level <= N, never above. Get the order right in your `uses` clause and circular-dependency errors disappear.

## ASCII tree (Layer 0: mormot.core.*)

```
mormot.core.base                (foundation: RawUtf8, PtrInt, ASM stubs, no deps)
  +-> mormot.core.os            (OS abstraction: TSynLocker, GetTickCount64, FS)
  |     +-> mormot.core.os.security  (security primitives)
  |     +-> mormot.core.os.mac       (macOS-specific)
  +-> mormot.core.unicode       (charset conversion: StringToUtf8, ...)
        +-> mormot.core.text    (FormatUtf8, CSV, currency text)
              +-> mormot.core.datetime  (TTimeLog, ISO 8601)
                    +-> mormot.core.rtti      (TRttiCustom, Rtti.RegisterFromText)
                          +-> mormot.core.buffers  (SynLZ, Base64, TBufferWriter)
                                +-> mormot.core.data     (TDynArray, hashed)
                                      +-> mormot.core.json     (TJsonWriter, GetJsonField)
                                            +-> mormot.core.variants (TDocVariant, IDocList)
                                                  +-> mormot.core.log      (TSynLog)
                                                        +-> mormot.core.threads
                                                              +-> mormot.core.search
                                                                    +-> mormot.core.collections
                                                                          +-> mormot.core.interfaces
                                                                                +-> mormot.core.test
```

(All of the above sit below `lib`, `crypt`, `net`, `db`, `orm`, `rest`, `soa`, `app`.)

## Per-tier purpose

### Tier 0 - foundation

| Unit                    | One-liner                                                    |
|-------------------------|--------------------------------------------------------------|
| `mormot.core.base`      | RawUtf8, RawByteString, PtrInt, ASM stubs, basic types.      |
| `mormot.core.os`        | OS abstraction; `TSynLocker`, ticks, file/process APIs.      |
| `mormot.core.unicode`   | UTF-8 / UTF-16 / WinAnsi conversion functions.               |
| `mormot.core.text`      | Text formatting, CSV parsing, currency-to-text.              |
| `mormot.core.datetime`  | `TTimeLog`, `TDateTimeMS`, ISO 8601 helpers.                 |

### Tier 1 - data services

| Unit                    | One-liner                                                    |
|-------------------------|--------------------------------------------------------------|
| `mormot.core.rtti`      | `Rtti.RegisterFromText`, custom RTTI registry.               |
| `mormot.core.buffers`   | SynLZ compression, Base64, low-level buffer writers.         |
| `mormot.core.data`      | `TDynArray`, `TDynArrayHashed`, serialization plumbing.      |
| `mormot.core.json`      | `TJsonWriter`, `GetJsonField`, `TSynDictionary`.             |
| `mormot.core.variants`  | `TDocVariant`, `IDocList`, `IDocDict`.                       |

### Tier 2 - cross-cutting

| Unit                    | One-liner                                                    |
|-------------------------|--------------------------------------------------------------|
| `mormot.core.log`       | `TSynLog`, structured logging, family configuration.         |
| `mormot.core.threads`   | Background thread pool, `TSynBackgroundThreadProcess`.       |
| `mormot.core.search`    | `TSynTimeZone`, full-text search helpers.                    |
| `mormot.core.interfaces`| Interface RTTI, fakes, DI/IoC building blocks.               |
| `mormot.core.test`      | `TSynTestCase` test framework.                               |

## "Don't import upward" rule

Lower tiers must not see higher ones. Concrete example:

```pascal
// WRONG: mormot.core.base cannot uses mormot.core.json (json is higher).
unit mormot.core.base;
uses
  mormot.core.json; // <-- circular layering, will not compile
```

```pascal
// RIGHT: a service unit consumes both, in the right order.
unit my.app.pricing;
uses
  mormot.core.base,    // first
  mormot.core.rtti,    // before json so any RegisterFromText is visible
  mormot.core.json;    // last among core deps
```

When a `uses` clause grows past ~6 mormot units, add them in *layer order*. The RTTI registry is the most common ordering trap: registration must happen before any code path that serializes the registered type.
