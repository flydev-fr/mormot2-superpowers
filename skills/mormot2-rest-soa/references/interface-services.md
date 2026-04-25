# Interface-Based Services

Interface-based services are mORMot 2's structured SOA contract: a Pascal interface declared once, implemented on the server, faked on the client. The wire format is JSON, the binding is RTTI-driven.

## The contract

```pascal
type
  IInventoryService = interface(IInvokable)
    ['{4C2E1A8B-9D7F-4E3A-9B6C-7E5D1A2B3C4D}']
    procedure ListItems(out Items: TItemArray);
    function GetCount: integer;
    function FindBySku(const Sku: RawUtf8; out Item: TItem): boolean;
  end;
```

Two non-negotiables:
- Inherit from `IInvokable` (or a descendant). This is what gives mORMot the per-method RTTI it needs.
- Embed a GUID. The GUID identifies the contract on the wire. Press `Ctrl+Shift+G` in the IDE.

## Allowed parameter types

| Type                                                | Notes                                                  |
|-----------------------------------------------------|--------------------------------------------------------|
| `integer`, `Int64`, `boolean`, `double`, `currency` | Primitive, marshalled directly                         |
| `RawUtf8`                                           | Default text type. Always prefer over `string`         |
| `TDateTime`, `TDateTimeMS`, `TTimeLog`              | Time types, ISO 8601 on the wire                       |
| Records with registered RTTI                        | Register via `Rtti.RegisterFromText` in `mormot2-core` |
| Dynamic arrays of any of the above                  | Including arrays of records and arrays of `RawUtf8`    |
| `variant` / `TDocVariantData`                       | For schema-less or nullable values                     |

Disallowed (registration will fail or runtime will reject):
- Classes (use records or DTOs).
- Untyped pointers.
- `string` is allowed but pays a UTF-16 round trip on every call. Use `RawUtf8`.
- Nested interfaces are allowed only if the inner one is also `IInvokable` and registered.

## Parameter direction

| Pascal modifier | Direction         | Wire shape                    |
|-----------------|-------------------|-------------------------------|
| (none)          | input             | inside the request payload    |
| `var`           | input + output    | request payload + response    |
| `out`           | output only       | response payload              |
| function result | output            | response payload              |

`out` parameters are returned as named JSON fields. The function result, if any, lands in the `result` member.

## Lifetime modes (`TServiceInstanceImplementation`)

| Mode               | One instance per...           | Auth required | Use when                                              |
|--------------------|-------------------------------|---------------|-------------------------------------------------------|
| `sicSingle`        | call (default, safest)        | no            | Resource-heavy, stateless logic, slow path tolerated  |
| `sicShared`        | server process                | no            | Hot path, stateless or guarded by `TSynLocker`        |
| `sicClientDriven`  | client-managed lifetime       | no            | Stateful workflow (wizard, transaction, cursor)       |
| `sicPerSession`    | authenticated session         | yes           | Per-user cache, in-flight state                       |
| `sicPerUser`       | user across sessions          | yes           | User preferences shared across devices                |
| `sicPerGroup`      | user group                    | yes           | Group config, RBAC-scoped data                        |
| `sicPerThread`     | server worker thread          | no            | Thread-local connection / handle / arena              |

## Registering on the server

```pascal
Server.ServiceDefine(TInventoryService, [IInventoryService], sicShared);
// Older equivalent:
Server.ServiceRegister(TInventoryService, [TypeInfo(IInventoryService)], sicShared);
```

`ServiceDefine` is the preferred verb in mORMot 2: takes the interface itself (not its `TypeInfo`).

## Consuming on the client

```pascal
Client.ServiceDefine([IInventoryService], sicShared);

var Service: IInventoryService;
if Client.Services.Resolve(IInventoryService, Service) then
  Service.ListItems(MyItems);
```

For `sicClientDriven`, registration is implicit: `Client.Services.Info(IService).Get(ref)` auto-registers on first use.

## Contract versioning

`ContractExpected` lets server and client refuse to talk if the wire shape drifts. Pass a string version as the last parameter to `ServiceRegister` / `ServiceDefine`.

```pascal
Server.ServiceRegister(TMyService, [TypeInfo(IMyService)], sicShared, 'v2.5');
Client.ServiceRegister([TypeInfo(IMyService)], sicShared, 'v2.5');
```

Bumping the version on a breaking change is cheaper than debugging a silently-corrupted JSON round trip.

## Async result patterns

mORMot 2 supports asynchronous service calls via callbacks (`IInvokable`-based callbacks defined as `interface(ICallbackInterface)` parameters) over WebSockets - see `mormot2-net` for the bidirectional transport. For synchronous services, return values flow through the function result and `out` parameters; long-running work should be split with a separate "poll status" call rather than blocked on the wire.
