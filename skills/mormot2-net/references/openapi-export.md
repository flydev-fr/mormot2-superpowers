# OpenAPI Export

`mormot.net.openapi` does one job: it reads a Swagger 2 or OpenAPI 3.x JSON document and emits two Pascal units, a DTO unit (records and enums) and a client unit (one method per operation). The generated client speaks JSON over HTTP through `IJsonClient`. There is no inverse path in core; mORMot does not currently introspect a `TRestServer` and emit a Swagger document by itself.

## Pipeline

```text
   third-party openapi.json (or url)
              |
              v
   TOpenApiParser.ParseFile / ParseJson / ParseUrl
              |
              v
   in-memory schemas, paths, operations
              |
              v
   ExportToDirectory('out/')
              |
              +-- Petstore.dto.pas    (records, enums, helpers)
              +-- Petstore.client.pas (TPetstoreClient = class)
```

## Minimal export

```pascal
uses
  mormot.net.openapi;

var
  Parser: TOpenApiParser;
begin
  Parser := TOpenApiParser.Create('Petstore', []);
  try
    Parser.ParseFile('petstore.openapi.json');
    Parser.ExportToDirectory('generated/');
  finally
    Parser.Free;
  end;
end;
```

The first argument names the units (`Petstore.dto.pas`, `Petstore.client.pas`). The second is a `TOpenApiParserOptions` set; the most useful flags:

- `opoNoEnum` - emit `RawUtf8` instead of generated enum types. Use when the spec churns enum values often and you do not want the unit to drift.
- `opoNoDateTime` - keep `string` for date fields rather than mapping to `TDateTime`. Useful when the upstream encodes timezone-naive ISO strings inconsistently.
- `opoClientOnlySummary` - generate one summary comment per operation rather than the full description block; smaller diffs.
- `opoGenerateOldDelphiCompatible` - target pre-Unicode Delphi if you must build on D7-ish toolchains.
- `opoGenerateStringType` - use `string` instead of `RawUtf8` for textual fields. Choose this only if you cannot follow the `RawUtf8` boundary discipline from `mormot2-core`.

## Using the generated client

The generated unit defines a class like:

```pascal
type
  TPetstoreClient = class(TJsonClientAbstract)
  public
    constructor Create(const aClient: IJsonClient); reintroduce;
    function GetPetById(aPetId: Int64): TPet;
    procedure AddPet(const aBody: TPet);
    // ... one method per operation ...
  end;
```

Construction is a two-line idiom: build a transport, hand it to the client.

```pascal
uses
  mormot.net.client,
  Petstore.client;

var
  Json: IJsonClient;
  Pets: TPetstoreClient;
  P: TPet;
begin
  Json := TJsonClient.Create('https://petstore.example.com');
  Pets := TPetstoreClient.Create(Json);
  try
    P := Pets.GetPetById(42);
    // ... use P ...
  finally
    Pets.Free;
  end;
end;
```

`IJsonClient` is reference-counted and goes out of scope when `Json` does.

## Authentication

Headers go through `IJsonClient.OnBefore`:

```pascal
Json := TJsonClient.Create('https://api.example.com');
Json.OnBefore := procedure(var Ctxt: TJsonClientRequest)
  begin
    Ctxt.Headers := Ctxt.Headers + 'Authorization: Bearer ' + JwtToken + #13#10;
  end;
```

For OAuth2 client-credentials flows where the token rotates, fetch and cache the token in the same `OnBefore` callback and refresh on 401.

## Going the other way

mORMot does not ship a "REST -> Swagger" generator in `mormot.net.openapi`. If you need to publish a spec for your own services, three patterns work:

1. **Hand-author** the spec next to your interface unit and treat it as part of the contract. The cost is duplication; the benefit is a stable spec that does not flicker on internal refactors.
2. **Reflect at startup** through `TInterfaceFactory` (in `mormot.core.interfaces`) and write a custom emitter. mORMot has the RTTI for every `IInvokable` method and parameter; the emitter is a few hundred lines of `TJsonWriter`.
3. **Use a third-party tool** to walk the Pascal interface units and emit OpenAPI. This belongs outside core; see your team's policy.

The choice depends on whether the spec or the interface is your source of truth.

## Serving the spec

If you do produce an OpenAPI document, serving it is a method-based service one-liner:

```pascal
type
  TAppServer = class(TRestServerDB)
  published
    procedure OpenApiJson(Ctxt: TRestServerUriContext);
  end;

procedure TAppServer.OpenApiJson(Ctxt: TRestServerUriContext);
begin
  Ctxt.ReturnFile('docs/openapi.json', false, JSON_CONTENT_TYPE);
end;
```

Pair with a static-served Swagger UI bundle (one HTML file plus the assets) to give consumers an in-browser explorer. The static serving belongs in `mormot2-deploy`'s reverse proxy or in a `TRestServerStatic`-style mount; it is not a transport-layer concern beyond the URI route.
