# TSynLog setup

Reference for `TSynLogFamily` properties (declared in `mormot.core.log.pas`) and recommended configurations per environment. The family is the configuration object; the `TSynLog` class is the type whose family you configure. `TSynLog.Family` returns the `TSynLogFamily` instance, lazily created on first access.

## Project boilerplate

The minimum-viable wiring is three statements: pick the levels, pick the destination, and (optionally) enable exception interception. Everything else has working defaults.

```pascal
program myserver;
{$I mormot.defines.inc}
uses
  mormot.core.base,
  mormot.core.log,
  mormot.core.os; // for executable folder, stack-trace symbol resolution

procedure SetupLogging;
begin
  with TSynLog.Family do
  begin
    DestinationPath := './logs/';
    Level := LOG_NFO;
    HandleExceptions := true;
    AutoFlushTimeOut := 5;
  end;
end;

begin
  SetupLogging;
  TSynLog.Add.Log(sllInfo, 'starting; pid=%', [GetCurrentProcessId]);
  // ... main loop ...
end.
```

`Level` should be set last in the `with` block: assigning a non-empty set triggers `SetLevel`, which calls `CreateSynLog` if no log instance exists yet, which opens the destination file. Setting other properties after `Level` works but they are read at log-line time, not at file-open time, so the file header can end up partially configured.

## Folder layout

| Production environment    | Recommended `DestinationPath`                          |
|---------------------------|--------------------------------------------------------|
| Windows service           | `'%PROGRAMDATA%\MyApp\logs\'` (writable; survives upgrade) |
| Linux systemd unit        | `'/var/log/myapp/'` (with `LogsDirectory=myapp` in `.service`) |
| Local dev (Delphi/Lazarus)| `'./logs/'` (relative to executable) |
| Container (Docker)        | `'/var/log/myapp/'` mounted to a volume; or `''` + `EchoToConsole := LOG_VERBOSE` for stdout-only |

When `DestinationPath` is empty (`''`), logs go to the executable folder. When the folder does not exist, mORMot creates it on first write (recursive). Ensure the runtime user has write permissions; on Windows services the default `LocalSystem` does, on Linux systemd `User=` may not.

## Levels per environment

mORMot 2 ships these convenience constants in `mormot.core.log` (verified against `mormot.core.log.pas:236-247`):

| Constant       | Includes                                                                              | Use for                |
|----------------|---------------------------------------------------------------------------------------|------------------------|
| `LOG_VERBOSE`  | every level                                                                           | development, repro     |
| `LOG_NFO`      | `LOG_WNG` + `sllInfo`, `sllDDDInfo`, `sllMonitoring`, `sllClient`, `sllServer`, `sllServiceCall` | production default     |
| `LOG_WNG`      | `LOG_ERR` + `sllWarning`, `sllFail`, `sllStackTrace`                                  | production-quiet       |
| `LOG_ERR`      | `LOG_CRI` + `sllLastError`, `sllError`, `sllDDDError`                                 | error-only deployments |
| `LOG_CRI`      | `sllException`, `sllExceptionOS`                                                      | crash-only telemetry   |
| `LOG_STACKTRACE` | levels that include a stack trace (`sllError`, `sllException`, `sllExceptionOS`, `sllLastError`, `sllStackTrace`) | reference for `LevelStackTrace` |
| `LOG_FILTER[lfErrors]` | `[sllError, sllLastError, sllException, sllExceptionOS]`                          | tight error filter     |
| `LOG_FILTER[lfDebug]`  | `[sllDebug, sllTrace, sllEnter]`                                                   | per-method tracing     |

Assemble custom sets by union: `Level := LOG_NFO + [sllSQL, sllDB]` for an info-level production log that *also* captures every SQL statement, useful when chasing an ORM regression.

## Property reference

The full list of properties on `TSynLogFamily` (from `mormot.core.log.pas:676-1100`); the most-used are:

| Property                       | Default                              | What it does                                                                 |
|--------------------------------|--------------------------------------|------------------------------------------------------------------------------|
| `Level`                        | `[]`                                 | Which `TSynLogLevel` values reach the file                                   |
| `LevelStackTrace`              | `LOG_STACKTRACE` set                 | Levels that capture a stack trace in addition to the message                 |
| `LevelSysInfo`                 | `[sllException, sllExceptionOS, sllLastError]` | Levels that include system-info dump (memory, CPU)               |
| `DestinationPath`              | executable folder                    | Folder where `.log` files are written                                        |
| `DefaultExtension`             | `'.log'`                             | File extension                                                               |
| `IncludeComputerNameInFileName`| `false`                              | Append `(MyComputer)` to the filename                                        |
| `IncludeUserNameInFileName`    | `false`                              | Append `(UserName)` to the filename                                          |
| `CustomFileName`               | derived from executable              | Override the auto-generated filename                                         |
| `BufferSize`                   | `8192`                               | In-memory bytes before disk flush                                            |
| `AutoFlushTimeOut`             | `0` (no auto-flush)                  | Seconds between background-thread flushes; set `1`-`10` in production        |
| `PerThreadLog`                 | `ptIdentifiedInOneFile`              | `ptOneFilePerThread` for hot multi-threaded servers                          |
| `HighResolutionTimestamp`      | `false`                              | Hex microseconds vs ISO-8601 timestamp                                       |
| `LocalTimestamp`               | `false`                              | UTC (default) vs local time                                                  |
| `ZonedTimestamp`               | `false`                              | Append `Z` to UTC timestamps                                                 |
| `WithUnitName`                 | `true`                               | Log unit name with object instances (RTTI-derived)                           |
| `WithInstancePointer`          | `true`                               | Log object pointer alongside class name                                      |
| `HandleExceptions`             | `false`                              | Hook RaiseException / RaiseProc and log every Exception                      |
| `ExceptionIgnore`              | empty `TSynList`                     | List of Exception classes to skip (e.g. `EConvertError`)                     |
| `ExceptionIgnoreLibrary`       | `false`                              | Skip exceptions raised from loaded BPLs / SOs                                |
| `RotateFileCount`              | `0` (no rotation)                    | Number of rotated files to keep                                              |
| `RotateFileSizeKB`             | `0`                                  | Trigger rotation when current file exceeds this size                         |
| `RotateFileDailyAtHour`        | `-1` (never)                         | `0`-`23`: rotate daily at this hour                                          |
| `EchoToConsole`                | `[]`                                 | Levels echoed to stdout (use `LOG_VERBOSE` for container-friendly stdout)    |
| `EchoToConsoleBackground`      | `false`                              | When echoing, do it on the background thread (avoids blocking the caller)   |
| `EchoToConsoleUseJournal`      | `false`                              | On Linux, echo to systemd journal instead of stdout                          |
| `ArchiveAfterDays`             | `7`                                  | Move old files to `ArchivePath` after this many days                         |
| `ArchivePath`                  | `DestinationPath`                    | Where old files go (subfolder `log\YYYYMM\`)                                 |
| `OnArchive`                    | `nil`                                | Callback to compress/upload/delete old files                                 |
| `NoFile`                       | `false`                              | Disable file output entirely (useful with `EchoToConsole := LOG_VERBOSE`)    |

## Recommended per-environment recipes

**Development on a developer workstation:**
```pascal
with TSynLog.Family do
begin
  DestinationPath := './logs/';
  Level := LOG_VERBOSE;
  HandleExceptions := true;
  AutoFlushTimeOut := 1;          // see lines immediately
  EchoToConsole := LOG_VERBOSE;   // tail in the IDE
  PerThreadLog := ptIdentifiedInOneFile;
end;
```

**Production HTTP / REST server:**
```pascal
with TSynLog.Family do
begin
  DestinationPath := '/var/log/myapp/';
  Level := LOG_NFO;
  LevelStackTrace := LOG_STACKTRACE; // default; explicit for clarity
  HandleExceptions := true;
  ExceptionIgnoreLibrary := true;
  AutoFlushTimeOut := 5;
  RotateFileCount := 14;          // ~2 weeks
  RotateFileSizeKB := 16 * 1024;  // 16 MB
  RotateFileDailyAtHour := 3;     // 03:00 local
  PerThreadLog := ptIdentifiedInOneFile;
  WithUnitName := true;
end;
```

**Container / Kubernetes (stdout-friendly):**
```pascal
with TSynLog.Family do
begin
  NoFile := true;                 // no file at all
  Level := LOG_NFO;
  HandleExceptions := true;
  EchoToConsole := LOG_VERBOSE;   // every captured line goes to stdout
  EchoToConsoleBackground := true;
end;
```

**Error-only telemetry uplink:**
```pascal
with TSynLog.Family do
begin
  Level := LOG_ERR;               // errors only
  LevelStackTrace := LOG_ERR;     // attach stack to every error
  HandleExceptions := true;
  OnArchive := @UploadToTelemetry; // SAD §25.6 callback signature
  ArchiveAfterDays := 1;
end;
```

## Multiple `TSynLog` classes

When one log file would mix concerns (e.g. SQL traces drowning REST traces), declare separate subclasses; each gets its own family and its own `.log` file:

```pascal
type
  TSqlLog = class(TSynLog);
  TRestLog = class(TSynLog);

procedure SetupLogging;
begin
  TSqlLog.Family.Level := [sllSQL, sllDB, sllError, sllException];
  TSqlLog.Family.DestinationPath := '/var/log/myapp/sql/';
  TRestLog.Family.Level := LOG_NFO;
  TRestLog.Family.DestinationPath := '/var/log/myapp/rest/';
end;

procedure DoQuery;
begin
  TSqlLog.Add.Log(sllSQL, 'select * from %', [tableName]);
end;
```

The framework supports up to seven `TSynLogFamily` instances simultaneously (`MAX_SYNLOGFAMILY = 7`, see `mormot.core.log.pas:222`); attempting to register an eighth raises an exception at unit initialization.

## See also

- `fastmm4-leaks.md` - reading the leak report that `TSynLog.Family.Level` does not affect
- `reading-stack-traces.md` - turning addresses in the log into source lines
- `mormot.core.log.pas` lines 196-1100 - the authoritative declarations
- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-25.md` - SAD chapter on logging
