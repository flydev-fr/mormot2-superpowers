# RawUtf8 Cheatsheet

mORMot 2 is natively UTF-8. Pick the type by *purpose*, not by the platform.

## When to use which string type

| Type             | Use for                                                  | Defined in           |
|------------------|----------------------------------------------------------|----------------------|
| `RawUtf8`        | All internal storage, transport, JSON, SQL, log lines    | `mormot.core.base`   |
| `RawByteString`  | Binary payloads (cipher text, file blobs, compressed)    | `mormot.core.base`   |
| `WinAnsiString`  | Legacy WinAnsi (CP1252) bridges; rare in new code        | `mormot.core.base`   |
| `SynUnicode`     | Fastest native Unicode; alias `WideString`/`UnicodeString` | `mormot.core.base` |
| `UnicodeString`  | VCL/FMX UI controls and Delphi RTL APIs that demand it   | RTL                  |
| `string`         | Generic VCL/FMX boundary; treat as alias for `UnicodeString` on D2009+ | RTL  |

Rule: **`RawUtf8` for everything that lives more than one stack frame**. Other types appear only where the platform forces them.

## Conversion functions (mormot.core.unicode)

| From -> To                       | Function                          |
|----------------------------------|-----------------------------------|
| `string` -> `RawUtf8`            | `StringToUtf8`                    |
| `RawUtf8` -> `string`            | `Utf8ToString`                    |
| `WinAnsiString` -> `RawUtf8`     | `WinAnsiToUtf8`                   |
| `RawUtf8` -> `WinAnsiString`     | `Utf8ToWinAnsi`                   |
| `UnicodeString`/PWideChar -> `RawUtf8` | `RawUnicodeToUtf8` / `WideStringToUtf8` |
| `RawUtf8` -> `SynUnicode`        | `Utf8ToSynUnicode`                |
| `RawByteString` <-> `RawUtf8`    | direct cast (no conversion, just codepage hint) |

## The boundary rule

Convert at the edge ONCE, not repeatedly. A single `Utf8ToString` per round trip is fine. A `Utf8ToString` inside a loop is a smell.

### HTTP input boundary (network -> internal)

```pascal
// HTTP body is already UTF-8 bytes. Cast once, do not StringToUtf8.
var
  body: RawUtf8;
begin
  body := Ctxt.InContent; // already RawUtf8 in mormot.rest.http.server
  ProcessUtf8(body);
end;
```

### DB output boundary (DB -> internal -> UI)

```pascal
// mORMot SQL helpers return RawUtf8 directly; only convert when
// you actually paint pixels.
var
  name: RawUtf8;
begin
  name := Conn.ExecuteUtf8('select name from users where id=?', [id]);
  Label1.Caption := Utf8ToString(name); // UI edge, once
end;
```

### VCL form boundary (UI -> internal)

```pascal
// Convert TEdit text once; pass RawUtf8 down the stack.
var
  email: RawUtf8;
begin
  email := StringToUtf8(EditEmail.Text);
  Users.Save(email);
end;
```

## Quick smell list

- A field declared `string` in a record that is later JSON-serialized: change it to `RawUtf8`.
- A `Utf8ToString` call in a loop body: hoist to the boundary.
- A `RawUtf8` variable being concatenated with `'literal'`: ensure the literal is ASCII or wrap with `_U('text')` / use `RawUtf8('text')`.
- A `RawByteString` being passed where `RawUtf8` is expected without explicit cast: the codepage hint is wrong; cast deliberately.
