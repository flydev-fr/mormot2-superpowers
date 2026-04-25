# Thread Safety

mORMot 2's data-access layer is explicit about threading. Connections are *not* thread-safe; properties are. Statements are owned by the connection. If you remember those three sentences, the rest is mechanical.

## The three classes that matter

| Class                                          | Thread safety                                            | Lifetime                                            |
|------------------------------------------------|----------------------------------------------------------|-----------------------------------------------------|
| `TSqlDBConnectionProperties`                   | Thread-safe factory                                      | Process lifetime; one per logical database.         |
| `TSqlDBConnectionPropertiesThreadSafe`         | Thread-safe factory + per-thread connection pool         | Same as above. Most networked providers descend from this. |
| `TSqlDBConnection`                             | NOT thread-safe                                          | Bound to the thread that obtained it.               |
| `TSqlDBConnectionThreadSafe`                   | NOT thread-safe by itself, but lives in a per-thread pool slot indexed by `TSynLog.ThreadIndex` | Reaped when the thread ends or after `ConnectionTimeOutMinutes`. |
| `TSqlDBStatement` / `ISqlDBStatement`          | NOT thread-safe; bound to its connection                 | Caller-owned (or interface-managed).                |

## The golden rule

Always go through `Props.ThreadSafeConnection` from the thread that will *use* the connection.

```pascal
procedure WorkerJob;
var
  Conn: TSqlDBConnection;
  Rows: ISqlDBRows;
begin
  Conn := AppProps.ThreadSafeConnection; // resolves THIS thread's slot
  Rows := Conn.Execute('SELECT count(*) FROM events WHERE day=?', [Today]);
  if Rows.Step then
    Writeln('rows=', Rows.ColumnInt(0));
end;
```

`Props.ThreadSafeConnection` looks up the per-thread slot via `TSynLog.ThreadIndex`. The connection is created lazily on first use and reused on subsequent calls from the same thread.

What you must NOT do:

```pascal
// WRONG: capture once, share across threads.
ConnGlobal := AppProps.ThreadSafeConnection;          // initialized on main thread
TThread.CreateAnonymousThread(procedure begin
  ConnGlobal.Execute('...', []);                      // CORRUPTION: wrong thread
end).Start;
```

## Threading modes

`TSqlDBConnectionPropertiesThreadSafe.ThreadingMode` toggles the pool behavior:

| Mode                       | Behavior                                            | When to use                                                       |
|----------------------------|-----------------------------------------------------|-------------------------------------------------------------------|
| `tmThreadPool` (default)   | One connection per thread, allocated on first use   | Networked engines with sane connection caps (PostgreSQL, Oracle, MSSQL, ODBC). |
| `tmMainConnection`         | Single shared connection; all threads serialize     | Embedded engines that cannot multiplex (SQLite3 in some configs, Firebird embedded). |

```pascal
// SQLite3 with mORMot defaults already uses one connection. For Firebird embedded:
Props := TSqlDBIbxConnectionProperties.Create(...);
(Props as TSqlDBConnectionPropertiesThreadSafe).ThreadingMode := tmMainConnection;
```

## Connection lifecycle integration

The pool is keyed off `TSynLog.ThreadIndex`. mORMot's REST and threads units (`mormot.rest.*`, `mormot.threads.*`) call `TSynLog.NotifyThreadEnded` on worker shutdown, which reclaims the pool slot. If you spin up your own worker threads with `TThread.Create` and bypass mORMot's threading helpers, do this on shutdown:

```pascal
procedure TMyWorker.TerminatedSet;
begin
  TSynLog.NotifyThreadEnded; // releases this thread's TSqlDB connection slot
  inherited;
end;
```

Without this, short-lived threads accumulate orphaned pool slots until `ConnectionTimeOutMinutes` elapses (default: never).

## Reusing prepared statements

`Conn.NewStatementPrepared(sql, ExpectResults)` looks up an existing prepared statement keyed by SQL text on *that connection*. The cache is per-connection, which is per-thread. Implications:

- Across threads, the same SQL prepares once *per thread*. That is fine; the prepare cost amortizes over the thread's lifetime.
- A single thread reusing the same SQL hits the cache from the second call onward. Build SQL with `?` placeholders and bind values; do NOT inline parameter values into the SQL text or you blow the cache every call.
- `Stmt.Reset` lets you re-bind and re-execute without re-preparing. Use it inside a loop.

```pascal
var
  Stmt: ISqlDBStatement;
  Conn: TSqlDBConnection;
  i: integer;
begin
  Conn := Props.ThreadSafeConnection;
  Stmt := Conn.NewStatementPrepared(
    'INSERT INTO events(day, kind, payload) VALUES(?,?,?)', false);
  for i := 0 to High(Batch) do
  begin
    Stmt.Bind(1, Batch[i].Day);
    Stmt.BindTextU(2, Batch[i].Kind);
    Stmt.BindBlob(3, Batch[i].Payload);
    Stmt.ExecutePrepared;
    Stmt.Reset; // ready for the next iteration without re-prepare
  end;
end;
```

## Locking patterns when you must share state

Sometimes the data layer wraps a small in-process cache (last-seen sequence, tenant routing). Wrap it in `TSynLocker` or a `TRWLightLock` from `mormot.core.os` rather than rolling your own critical section.

```pascal
uses
  mormot.core.os;

var
  GLastSeqLock: TRWLightLock;
  GLastSeq: Int64;

procedure UpdateLastSeq(NewSeq: Int64);
begin
  GLastSeqLock.WriteLock;
  try
    if NewSeq > GLastSeq then
      GLastSeq := NewSeq;
  finally
    GLastSeqLock.WriteUnLock;
  end;
end;
```

`TRWLightLock` is non-reentrant and very cheap; perfect for "many readers, rare writer" snapshots that surround a DB call.

## Transaction scope

A transaction is *connection-local*. `Conn.StartTransaction / Commit / Rollback` only affect the calling thread's connection. To run a "global" transaction across threads, you cannot; serialize the work onto one thread instead, or use `Conn.SharedTransaction(SessionID, action)` which uses reference counting to allow nested transactions on a *single* shared connection.

```pascal
Conn := Props.ThreadSafeConnection;
Conn.StartTransaction;
try
  Conn.Execute('UPDATE accounts SET balance=balance-? WHERE id=?', [100, FromId]);
  Conn.Execute('UPDATE accounts SET balance=balance+? WHERE id=?', [100, ToId]);
  Conn.Commit;
except
  Conn.Rollback;
  raise;
end;
```

If `WorkerA` spawns `WorkerB` mid-transaction expecting B to "see" A's writes, that is a logic error: `B` will get its own connection and see only committed state.
