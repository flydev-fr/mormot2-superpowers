# TOrmModel Patterns

`TOrmModel` is the schema description handed to every `TRest`. It owns the list of `TOrm` classes, their root URL, and any virtual-table registrations. Get the lifecycle right and most ORM bugs disappear.

## Single-database model

The default. One `TOrmModel`, one `TRestServerDB`, one SQLite file.

```pascal
uses
  mormot.orm.core,
  mormot.orm.sqlite3;

var
  Model:  TOrmModel;
  Server: TRestServerDB;
begin
  Model  := TOrmModel.Create([TOrmUser, TOrmRole]);
  Server := TRestServerDB.Create(Model, 'data.db3');
  try
    Server.Server.CreateMissingTables;
    // ... use Server.Orm ...
  finally
    Server.Free;
    Model.Free; // after Server, not before
  end;
end;
```

## Multi-group model with distinct root names

When two logical databases must coexist in one process, give each model its own `RootName`. The root becomes the URL prefix for any later REST exposure.

```pascal
var
  CrmModel, AnalyticsModel: TOrmModel;
begin
  CrmModel       := TOrmModel.Create([TOrmCustomer, TOrmInvoice], 'crm');
  AnalyticsModel := TOrmModel.Create([TOrmEvent, TOrmFunnel],     'analytics');
  // /crm/Customer  vs  /analytics/Event
end;
```

Each `TRest` instance binds to exactly one model. Two models means two `TRest` instances.

## Sharing the model between server and client

Server and client must agree on the schema. Simplest: build the model once and pass the same instance to both.

```pascal
var
  Model:  TOrmModel;
  Server: TRestServerDB;
  Client: TRestClientDB;
begin
  Model  := TOrmModel.Create([TOrmUser, TOrmRole]);
  Server := TRestServerDB.Create(Model, ':memory:');
  Client := TRestClientDB.Create(Model, nil, ':memory:', TRestServerDB);
  // Client.Orm and Server.Orm now share the same schema description.
end;
```

For network deployments, build the model from the same Pascal unit on both sides. The class list and order must match exactly.

## Lifecycle and unregistering

- Free the `TRest` first. The server holds non-owning references into the model.
- Free the `TOrmModel` second. It owns the per-class metadata and frees it on destroy.
- A `TOrmModel` cannot be mutated after a `TRest` has been built from it. Add classes during construction; rebuild the model if the schema changes.
- There is no public "unregister class" call. To shrink the schema, build a new model with the reduced class list and switch the `TRest` over.

## Common shape of a server bootstrap

```pascal
function BuildModel: TOrmModel;
begin
  Result := TOrmModel.Create([TOrmUser, TOrmRole, TOrmAuditLog]);
  Result.VirtualTableRegister(TOrmAuditLog, TOrmVirtualTableJson);
end;

var
  Model:  TOrmModel;
  Server: TRestServerDB;
begin
  Model  := BuildModel;
  Server := TRestServerDB.Create(Model, 'app.db3');
  try
    Server.Server.CreateMissingTables;
    RunUntilSignal;
  finally
    Server.Free;
    Model.Free;
  end;
end;
```

Keep the model factory in one place. Two call sites that both build "the same" model are a refactor away from drifting apart.
