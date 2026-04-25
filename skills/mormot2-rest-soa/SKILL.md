---
name: mormot2-rest-soa
description: Use when building REST servers/clients, method-based services, or interface-based SOA in mORMot 2. Do NOT use for HTTP transport (use mormot2-net) or auth (use mormot2-auth-security).
---

# mormot2-rest-soa

mORMot 2 REST and Service-Oriented Architecture layer: in-process and remote `TRestServer` descendants, method-based services on `TRestServerUriContext`, interface-based services declared as `IInvokable` descendants, and the matching `TRestClientUri` consumers. This skill is authoritative for the `mormot.rest.*` namespace and for service registration verbs (`ServiceRegister`, `ServiceDefine`). It assumes the conventions defined in `mormot2-core` (RawUtf8, RTTI) and `mormot2-orm` (`TOrm`, `TOrmModel`). Sibling skills handle adjacent concerns: `mormot2-net` covers the HTTP/WebSocket transport that wraps the REST server, `mormot2-auth-security` covers JWT, ECC, and AES primitives, and `mormot2-db` covers raw SQL.

## When to use

- Standing up an in-process `TRestServerDB` (SQLite3 backend) or `TRestServerFullMemory` (no SQLite) to expose a `TOrmModel`.
- Adding a method-based service: a `published procedure DoSomething(Ctxt: TRestServerUriContext);` on a `TRestServer` descendant.
- Declaring an interface-based service: `IMyService = interface(IInvokable) ['{GUID}'] ... end;` plus a `TInterfacedObject` implementation.
- Registering services on the server with `ServiceRegister` / `ServiceDefine`, picking a lifetime mode (`sicShared`, `sicSingle`, `sicPerSession`, `sicPerThread`, `sicClientDriven`, `sicPerUser`, `sicPerGroup`).
- Wiring a `TRestClientUri` (or `TRestClientDB` for in-process tests) and calling `Client.ServiceDefine([IMyService], sicShared)` so the same Pascal interface drives the round trip.
- Using `Ctxt.Session`, `Ctxt.SessionID`, and `Ctxt.SessionUser` inside a method-based service, or hooking session creation/teardown.

## When NOT to use

- Async HTTP, WebSockets, OpenAPI generation, TLS, or HTTP-engine tuning (`useHttpAsync`, `useBidirAsync`, `useHttpApi`). Use **mormot2-net**.
- JWT signing, ECC key pairs, AES, OpenSSL bindings, password hashing primitives. Use **mormot2-auth-security**.
- Defining the underlying `TOrm` classes, mapping field attributes, building the `TOrmModel`, registering virtual tables. Use **mormot2-orm**.
- Raw SQL, `TSqlDBConnectionProperties`, PostgreSQL/MSSQL/MongoDB providers. Use **mormot2-db**.
- Foundational types (`RawUtf8`, `TDocVariant`), conditional defines, custom record RTTI. Use **mormot2-core**.

## Core idioms

### 1. Minimal in-process REST server with SQLite3 backend

`TRestServerDB` is the canonical SQLite-backed REST server. `TRestServerFullMemory` is the SQLite-free in-memory variant. Both bind to a `TOrmModel` built per `mormot2-orm`.

```pascal
uses
  mormot.core.base,
  mormot.orm.core,
  mormot.rest.sqlite3;

var
  Model:  TOrmModel;
  Server: TRestServerDB;
begin
  Model  := TOrmModel.Create([TOrmUser, TOrmRole]);
  Server := TRestServerDB.Create(Model, 'data.db3');
  try
    Server.Server.CreateMissingTables;
    // Server.Orm now exposes the model; HTTP transport comes from mormot2-net.
  finally
    Server.Free;
    Model.Free; // after the TRest, never before
  end;
end;
```

### 2. Method-based service

A `published` procedure on a `TRestServer` descendant becomes a URI under `ModelRoot/MethodName`. Signature MUST match `TOnRestServerCallBack`.

```pascal
type
  TAppServer = class(TRestServerDB)
  published
    procedure Sum(Ctxt: TRestServerUriContext);
  end;

procedure TAppServer.Sum(Ctxt: TRestServerUriContext);
begin
  Ctxt.Results([Ctxt.InputDouble['a'] + Ctxt.InputDouble['b']]);
end;

// GET /root/Sum?a=3&b=4  ->  {"Result":7}
```

### 3. Interface-based service contract

Inherit from `IInvokable` and embed a GUID. The interface is the contract; the same Pascal unit ships to client and server.

```pascal
type
  TItem = packed record
    Sku:   RawUtf8;
    Price: currency;
  end;
  TItemArray = array of TItem;

  IInventoryService = interface(IInvokable)
    ['{4C2E1A8B-9D7F-4E3A-9B6C-7E5D1A2B3C4D}']
    procedure ListItems(out Items: TItemArray);
    function GetCount: integer;
  end;
```

### 4. Server-side service registration

`ServiceDefine` is the modern verb (it accepts the interface itself rather than its `TypeInfo`). Pick the lifetime mode deliberately; `sicShared` is the safest default for stateless services and is the cheapest in throughput.

```pascal
uses
  mormot.rest.server,
  mormot.soa.server;

type
  TInventoryService = class(TInterfacedObject, IInventoryService)
  public
    procedure ListItems(out Items: TItemArray);
    function GetCount: integer;
  end;

// ... after Server is constructed:
Server.ServiceDefine(TInventoryService, [IInventoryService], sicShared);
```

### 5. Client consuming the same interface

The client builds the same `TOrmModel`, opens a `TRestClientUri` (HTTP variant comes from `mormot2-net`), then calls `ServiceDefine` to wire a fake implementation that serializes calls as JSON.

```pascal
uses
  mormot.rest.client;

var
  Service: IInventoryService;
  Items:   TItemArray;
begin
  Client.ServiceDefine([IInventoryService], sicShared);
  if Client.Services.Resolve(IInventoryService, Service) then
    Service.ListItems(Items);
end;
```

## Common pitfalls

- **Forgetting `IInvokable` (or its `IInvokable`-derived ancestor) on the interface.** Without it the interface has no RTTI, `ServiceDefine` cannot inspect parameters, and registration silently does nothing useful at runtime. Always inherit from `IInvokable` and embed a GUID.
- **Forgetting the GUID on the interface declaration.** mORMot uses the GUID to identify the contract across the wire. A missing or duplicated GUID makes `Services.Resolve` return false or, worse, route to the wrong service.
- **Using raw `Boolean` parameters in interface methods when nullability matters.** Nullable booleans round-trip as `0` / `1` / missing, which is ambiguous. Use `variant` for nullable values, or split into two methods (`SetEnabled` / `SetDisabled`).
- **Misjudging the lifetime mode.** `sicShared` is one instance for ALL calls and threads (you must make the implementation thread-safe). `sicSingle` is a fresh instance per call (default, safest, slowest). `sicPerSession` requires authentication. `sicPerThread` is one per server worker thread. Pick on read/write profile and statefulness, not by feel.
- **Defining a method-based handler with the wrong signature.** The procedure MUST be `procedure(Ctxt: TRestServerUriContext)`, declared `published`, and live on a class derived from `TRestServer`. Anything else is invisible to the URI router.
- **Not setting up CORS for browser clients.** `TRestHttpServer` (in `mormot2-net`) has explicit CORS knobs; without them an SPA on a different origin will hit a preflight wall. Configure CORS at the HTTP wrapper layer.
- **Mutating shared state inside a `sicShared` service without locking.** `sicShared` is single-instance, multi-thread. Use a `TSynLocker` (see `mormot2-core`) or restructure to keep the service stateless.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-10.md` - JSON / REST
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-11.md` - Client-Server Architecture
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-14.md` - Method-based Services
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-15.md` - Interfaces and SOLID
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-16.md` - Service-Oriented Architecture
- `references/rest-server-shapes.md`
- `references/interface-services.md`
- `references/session-and-auth.md`
- `mormot2-core` for RawUtf8 conventions and TSynLocker
- `mormot2-orm` for TOrm/TOrmModel definitions
- `mormot2-net` for HTTP/WebSocket/TLS transport
- `mormot2-auth-security` for JWT, ECC, AES primitives
