# JSON / RTTI Idioms

mORMot 2 JSON is the fastest path Pascal has to JSON. Two rules dominate: register types up front, and never round-trip through `string`.

## Custom record RTTI - text DSL

The simplest registration. One line per record, run once at startup. Ordering matters: register before any code path serializes the type.

```pascal
uses
  mormot.core.rtti;

type
  TPriceRow = packed record
    Symbol: RawUtf8;
    Price:  currency;
    Ts:     TDateTime;
  end;
  TPriceRows = array of TPriceRow;

initialization
  Rtti.RegisterFromText(TypeInfo(TPriceRow),
    'Symbol:RawUtf8 Price:currency Ts:TDateTime');
  Rtti.RegisterType(TypeInfo(TPriceRows));
end.
```

## Custom class RTTI - direct registration

For published-property classes, registration is automatic via RTTI. You only need explicit registration when you want custom JSON names, hooks, or to expose private fields.

```pascal
uses
  mormot.core.rtti;

type
  TUser = class
  private
    fId:   Int64;
    fName: RawUtf8;
  published
    property Id:   Int64   read fId   write fId;
    property Name: RawUtf8 read fName write fName;
  end;

initialization
  Rtti.RegisterClass(TUser);
end.
```

## TDocVariant interop

`TDocVariant` is the ergonomic option when the schema is unknown or sparse. It composes naturally with `TJsonWriter` and `Rtti.RegisterFromText`-typed records.

```pascal
uses
  mormot.core.variants,
  mormot.core.json;

var
  doc: variant;
  raw: RawUtf8;
begin
  doc := _Json('{"user":{"id":42,"name":"Ada"}}');
  doc.user.email := 'ada@example.com';

  raw := VariantSaveJson(doc); // RawUtf8 out, no string round trip
end;
```

## High-throughput JSON: reuse TJsonWriter

`TJsonWriter` is single-thread but reusable. Allocate once per worker, `CancelAll` between rows, never recreate in hot loops.

```pascal
uses
  mormot.core.json;

var
  W: TJsonWriter;
  tmp: TTextWriterStackBuffer;
  out: RawUtf8;
begin
  W := TJsonWriter.CreateOwnedStream(tmp);
  try
    W.Add('[');
    for row in Rows do
    begin
      W.AddRecordJson(row, TypeInfo(TPriceRow));
      W.AddComma;
    end;
    W.CancelLastComma;
    W.Add(']');
    W.SetText(out);
  finally
    W.Free;
  end;
end;
```

## Decoupling rule: never serialize via `string`

JSON in mORMot is `RawUtf8`. The moment you assign a serialized payload to a `string`, you pay a UTF-8 -> UTF-16 -> UTF-8 round trip and bloat memory. Keep the wire format `RawUtf8` end-to-end; convert only at the UI/RTL edge.

```pascal
// WRONG: implicit Utf8ToString during '+' concatenation.
var
  s: string;
begin
  s := 'payload=' + RecordSaveJson(row, TypeInfo(TPriceRow));
end;

// RIGHT: build with FormatUtf8 / RawUtf8 concatenation.
uses
  mormot.core.text;

var
  payload: RawUtf8;
begin
  payload := FormatUtf8('payload=%', [RecordSaveJson(row, TypeInfo(TPriceRow))]);
end;
```

If a function signature you do not own demands `string`, isolate the conversion in one place and document it as a boundary.
