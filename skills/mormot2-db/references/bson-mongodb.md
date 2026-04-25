# BSON and MongoDB

mORMot 2 ships a pure-Pascal MongoDB client (`mormot.db.nosql.mongodb.pas`) and a BSON encoder/decoder (`mormot.db.nosql.bson.pas`). The two layers map cleanly: BSON is the wire format and on-disk shape; `TDocVariant` is the in-memory shape every other mORMot subsystem already understands. Round-tripping is one function call in either direction.

## Object hierarchy

| Class                   | Owns                                                  | Created via                                               |
|-------------------------|-------------------------------------------------------|-----------------------------------------------------------|
| `TMongoClient`          | `TMongoConnection`s + cached `TMongoDatabase`s        | `TMongoClient.Create(Host, Port[, Options, SecondaryHosts...])` |
| `TMongoDatabase`        | Cached `TMongoCollection`s                            | `Client.Open(DbName)` or `Client.OpenAuth(...)`            |
| `TMongoCollection`      | Nothing it owns; just routes commands                 | `Database.Collection[Name]` or `Database[Name]`            |
| `TMongoConnection`      | The actual socket                                     | Implicitly by the client; one per server in the seed list  |

You construct one `TMongoClient` per logical Mongo deployment; everything else hangs off it. Free the client and the entire tree goes with it. Holding a `TMongoCollection` past the client's destruction is a use-after-free bug.

## Connecting

```pascal
uses
  mormot.db.nosql.mongodb;

var
  Client: TMongoClient;
  DB: TMongoDatabase;
begin
  // Single primary, no auth.
  Client := TMongoClient.Create('mongo.internal', MONGODB_DEFAULTPORT);

  // Replica set: pass primary host + comma-separated secondary hosts.
  // Client := TMongoClient.Create(
  //   'rs0-1.internal', MONGODB_DEFAULTPORT,
  //   MONGODB_DEFAULTOPTIONS,
  //   'rs0-2.internal,rs0-3.internal');

  DB := Client.OpenAuth('mydb', 'app_user', 'app_secret'); // SCRAM-SHA-256 by default
  // DB := Client.OpenAuth('mydb', 'user', 'pass', saSha1, false); // legacy MongoDB 3.x
end;
```

Free the client at shutdown only:

```pascal
Client.Free; // destroys all databases / collections / connections
```

For TLS, pass `mcoTls` in the options and configure `Client.ConnectionTlsContext` before `Open` / `OpenAuth`.

## Building a document

Three idioms, in order of preference for hot paths.

### Idiom 1: BsonVariant from name/value pairs

```pascal
uses
  mormot.db.nosql.bson;

var
  Doc: variant;
begin
  Doc := BsonVariant([
    'email', 'alice@example.com',
    'role', 'admin',
    'createdAt', NowUtc,
    'profile', BsonVariant([      // nested document
      'displayName', 'Alice',
      'avatar', BsonVariantFromIntegers([10, 20, 30])
    ]),
    'tags', _Arr(['admin', 'staff'])
  ]);
end;
```

`BsonVariant(...)` produces a `variant` that internally holds BSON bytes. Sending it does no JSON round-trip.

### Idiom 2: BsonVariant from a JSON template

```pascal
Doc := BsonVariant(
  '{name:?,year:?,tags:?}',
  ['Alice', 2024, _Arr(['admin','staff'])]);
```

The first parameter is a JSON literal with `?` placeholders; the second is the values. Convenient when the document shape is mostly literal.

### Idiom 3: From a TDocVariant you already have

```pascal
var
  V: variant;
  Bytes: TBsonDocument;
begin
  V := _Json('{"email":"bob@example.com","role":"user"}');
  Bytes := Bson(_Safe(V)^);    // raw BSON bytes
  // ... or build a BsonVariant directly:
  Doc := BsonVariant(_Safe(V)^);
end;
```

Use this when the data arrived as JSON / `TDocVariant` from elsewhere (REST input, config file, ORM result).

## CRUD

```pascal
uses
  mormot.core.variants,
  mormot.db.nosql.bson,
  mormot.db.nosql.mongodb;

var
  Coll: TMongoCollection;
  Doc, Found: variant;
begin
  Coll := DB.Collection['users'];

  // Insert one
  Coll.Insert([BsonVariant(['email','c@x','role','admin'])]);

  // Insert many (one round trip)
  Coll.Insert([
    BsonVariant(['email','d@x','role','user']),
    BsonVariant(['email','e@x','role','user'])]);

  // Find one
  Found := Coll.FindOne(BsonVariant(['email','c@x']));
  if not VarIsEmpty(Found) then
    Writeln(VariantSaveJson(Found));

  // Update (set role = 'editor' for one user)
  Coll.Update(
    BsonVariant(['email','c@x']),                  // filter
    BsonVariant(['$set', BsonVariant(['role','editor'])]));

  // Delete
  Coll.Remove(BsonVariant(['email','c@x']));
end;
```

`FindOne` returns `Unassigned` when nothing matches. `Find` returns an iterable cursor (`TMongoRequestCursor`) for paged reads.

## Aggregation pipelines

The aggregation API takes either a JSON string with `?` placeholders or an already-built `TDocVariantData` array. Three convenience entry points:

```pascal
// Raw JSON pipeline; placeholders bound by the params array.
Result := Coll.AggregateDoc(
  '[{$match:{role:?}},{$group:{_id:null,count:{$sum:1}}}]',
  ['admin']);

// Same, returning a list of documents you can iterate.
List := Coll.AggregateDocList(
  '[{$match:{role:?}},{$sort:{createdAt:-1}}]',
  ['admin']);

// Same, but pipeline is already a TDocVariant array (e.g. from caller-side composition).
Result := Coll.AggregateCallFromVariant(BuiltPipeline);
```

Pipelines that should use an index require an explicit `$hint` stage; the planner does not auto-pick declared indexes for ambiguous filters.

## BSON ↔ JSON conversions

`BsonToJson` is the inverse of `Bson(...)`. Two modes matter:

| Mode               | Output                                                              | Use for                                           |
|--------------------|---------------------------------------------------------------------|---------------------------------------------------|
| `modMongoStrict`   | Strict extended JSON: `ObjectId('...')` becomes `{"$oid":"..."}` etc | Round-tripping into another Mongo tool.           |
| `modMongoShell`    | mongo-shell-style: `ObjectId("...")`, `ISODate("...")`              | Logging / debugging.                              |
| `modNoMongo`       | Plain JSON without Mongo extensions                                  | Sending to non-Mongo consumers.                   |

Round-tripping erases binary identity: ObjectIds become hex strings, dates become ISO 8601, decimals become numerics. Hash the BSON bytes (`Bson(...)`) for stable signatures, never the JSON projection.

## Replica set configuration

`TMongoClient` constructor takes secondary hosts as a CSV. The client tracks primary/secondary state and routes reads according to `ReadPreference`:

```pascal
Client := TMongoClient.Create(
  'rs0-primary',
  MONGODB_DEFAULTPORT,
  MONGODB_DEFAULTOPTIONS,
  'rs0-secondary-1,rs0-secondary-2');
Client.ReadPreference := rpSecondaryPreferred; // route reads to secondaries when available
```

Reads with `rpPrimary` (default) always hit the primary; reads with `rpSecondaryPreferred` load-balance over secondaries and fall back to primary if all secondaries are down. Writes always go to the primary regardless of preference.

## Lifecycle checklist

- One `TMongoClient` per logical deployment, created at startup, freed at shutdown.
- Do NOT free `TMongoDatabase` or `TMongoCollection`; the client owns them.
- Wrap `Insert` / `Update` calls in your own retry logic if you target a replica set; failover to a new primary takes a few seconds during which writes fail with a recognizable Mongo error.
- Set `Client.ConnectionTimeOutMS` and `Client.SocketTimeoutMS` before `Open`/`OpenAuth`. Defaults are generous; production deployments often want them tighter.
- Define `MONGO_OLDPROTOCOL` only if you must talk to MongoDB < 3.6. Modern clusters always speak OP_MSG.
