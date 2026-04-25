---
name: pascal-debugging-logging
description: Use for TSynLog setup, FastMM4 leak reports, .map/DWARF stack traces, ISynLog tracing, EAccessViolation hunting. Do NOT use for TDD (test-driven-development) or root-cause (systematic-debugging).
---

# pascal-debugging-logging

Runtime diagnostics for mORMot 2 Pascal projects: wiring `TSynLog` (the logger declared in `mormot.core.log.pas`), choosing levels from `TSynLogLevel` (`sllError`, `sllWarning`, `sllStackTrace`, `sllEnter`, `sllLeave`, `sllInfo`, `sllDebug`, `sllTrace`, `sllException`), capturing per-method timings via `ISynLog`, reading FastMM4 / `mormot.core.fpcx64mm` leak reports, and resolving raw return addresses from a stack trace back to source lines via Delphi `.map` or FPC `-gw3` DWARF. This skill teaches what the logger does and how to read what it produces; it stops where test design (`test-driven-development`) and four-phase root-cause analysis (`systematic-debugging`) begin. It assumes the build flags of `delphi-build` / `fpc-build` are already in place: a project that does not emit a `.map` or a `.dbg` file at link time has no symbols to recover, and no amount of logging will turn raw `0x00000000007a3c1d` into `mormot.core.json:1234`.

## When to use

- Adding a logger to a project: declaring a `TSynLogClass` (or using the default `TSynLog`), configuring `TSynLogFamily` (`Level`, `LevelStackTrace`, `DestinationPath`, `PerThreadLog`, `RotateFileCount`, `AutoFlushTimeOut`), and emitting log entries via `TSynLog.Add.Log(sllInfo, ...)` or `TSynLog.Family.SynLog.Log(...)`.
- Choosing log levels per environment: production typically uses `LOG_NFO` (info + warnings + errors + monitoring), development `LOG_VERBOSE`, error-only deployments `LOG_ERR`. Stack traces always travel with `sllError`, `sllException`, `sllExceptionOS`, `sllLastError`, `sllStackTrace` via the default `LevelStackTrace` set.
- Per-method timing with `ISynLog`: `TSynLog.Enter(self, 'MyMethod')` or the more efficient `TSynLog.EnterLocal(local, self, 'MyMethod')`, which records `sllEnter` on entry and `sllLeave` with elapsed microseconds when the interface goes out of scope.
- Reading a FastMM4 (Delphi) or `mormot.core.fpcx64mm` (FPC) leak report at shutdown: matching the call-site fingerprint to a unit + line, distinguishing real leaks from finalization-order false positives, telling shared-string interning artifacts from genuine retention.
- Resolving an address-only stack trace (`error  $0000000000401abc`) to a source line: building Delphi with `-GD` so a detailed `.map` exists, building FPC with `-gw3 -gl` so DWARF + line-info travel with the binary, and pointing the resolver (mORMot's built-in, `addr2line`, `Map2DWARF`) at the artefact.
- Hunting `EAccessViolation`, `EAssertionFailed`, `EOutOfMemory`, `EDivByZero` and other `Exception` descendants by enabling `Family.HandleExceptions := true` so every raised exception gets logged with its stack trace before it propagates.
- Capturing live performance traces in long-running services: `mormot.core.perf.TSynMonitor` family for per-operation counters (count, total/min/max time, throughput) when `ISynLog` per-method timing is too coarse-grained or already enabled at every entry.

## When NOT to use

- Writing failing tests first, the RED-GREEN-REFACTOR loop, choosing `TSynTestCase` / `TSynTestsLogged` shapes. Use **test-driven-development**.
- Following the four-phase root-cause workflow (Capture, Reproduce, Bisect, Fix) on a specific failure. This skill teaches the *instruments*; the workflow that drives them is in **systematic-debugging**.
- Build-time configuration: `-V` / `-GD` on Delphi, `-gw3` / `-gl` on FPC, search paths, conditional defines that toggle logging at compile time. Use **delphi-build** or **fpc-build**.
- Runtime topology decisions (where the log file lives in production, log shipping to a SIEM, rotation policy across multiple instances). Those are deployment choices and belong in **mormot2-deploy**.
- `RawUtf8`, `TDocVariant`, RTTI, conditional defines used in the snippets. Use **mormot2-core**.

## Core idioms

### 1. Wire `TSynLog` into a project in three lines

mORMot 2's `TSynLog` is a singleton-per-class: every `TSynLogClass` (i.e. `class of TSynLog`) gets its own `TSynLogFamily`. The default `TSynLog` works for most apps; large systems declare `TSqlLog`, `TServerLog`, etc. so the `.log` files separate by concern. Configuration goes through the family, before the first log line:

```pascal
program myserver;
{$I mormot.defines.inc}
uses
  mormot.core.log,
  mormot.core.os; // for TSynLog stack-trace symbol resolution

begin
  with TSynLog.Family do
  begin
    Level := LOG_VERBOSE;          // every level; use LOG_NFO in production
    DestinationPath := './logs/';  // created on first write
    PerThreadLog := ptIdentifiedInOneFile; // tag thread, single file
    RotateFileCount := 5;          // keep 5 rotated files
    RotateFileSizeKB := 8 * 1024;  // 8 MB before rotation
    AutoFlushTimeOut := 5;         // flush every 5s even if buffer not full
    HandleExceptions := true;      // log every Exception with stack trace
  end;
  TSynLog.Add.Log(sllInfo, 'server starting, pid=%', [GetCurrentProcessId]);
  // ... main loop ...
end.
```

`Level := LOG_VERBOSE` should be set last (it triggers the family's first `CreateSynLog`), and `LevelStackTrace` already includes `sllError`, `sllException`, `sllExceptionOS`, `sllLastError`, `sllFail`, `sllDDDError`, `sllStackTrace` by default. There is no separate `Initialize` to call: the family is constructed lazily on first access. See `references/tsynlog-setup.md` for the full property table and per-environment level recommendations.

### 2. Per-method timing via `ISynLog` / `EnterLocal`

`TSynLog.Enter` returns an `ISynLog` interface whose `_AddRef` writes `sllEnter` and whose `_Release` writes `sllLeave` with the elapsed time. The interface goes out of scope at the method end, so the leave entry happens automatically on `return`, `raise`, or any other exit path:

```pascal
procedure TOrderService.PostOrder(const order: TOrder);
var
  log: ISynLog;
begin
  log := TSynLog.Enter(self, 'PostOrder');
  // do work
  if Assigned(log) then // nil if sllEnter is not in Family.Level
    log.Log(sllInfo, 'submitted order id=%', [order.ID]);
end; // _Release writes:  20240101 12:34:56  -    01.512.320
```

For the hot path, prefer `EnterLocal`, which avoids one `IUnknown` indirection and is explicitly faster on FPC:

```pascal
var
  log: ISynLog;
begin
  TSynLog.EnterLocal(log, self, 'HotMethod');
  // ...
  if Assigned(log) then
    log.Log(sllDebug, 'cache hit ratio=%', [hits / total]);
end;
```

When `Family.HighResolutionTimestamp := true`, the `+`/`-` lines carry hexadecimal microseconds suitable for after-the-fact profiling without re-running. Pair with `mormot.core.perf.TSynMonitor` when you need aggregated counters (call count, min/max/total time per operation) instead of per-call lines.

### 3. Make every `Exception` log its stack trace

The single highest-value setting in `TSynLogFamily` is `HandleExceptions := true`. mORMot 2 hooks `RaiseException` on Windows and the `RaiseProc` slot on FPC; every raised `Exception` lands in the log with its message, address, and stack trace, before the regular `try/except` can swallow it:

```pascal
TSynLog.Family.HandleExceptions := true;
TSynLog.Family.ExceptionIgnore.Add(EConvertError); // skip noisy ones
TSynLog.Family.ExceptionIgnoreLibrary := true;     // skip exceptions from .bpl
```

`ExceptionIgnore` is a class list; `ExceptionIgnoreCurrentThread := true` toggles per-thread (e.g. inside an Indy worker that raises a lot of `EIdConnClosedGracefully`). `OnBeforeException` is a callback if you need conditional filtering. The result in the log file:

```
20240101 12:34:56 EXC   EAccessViolation ('Access violation at address...') at $00007FF6C123ABCD
20240101 12:34:56 stack $00007FF6C123ABCD mymain.MyMethod (mymain.pas:123)
                         $00007FF6C123AC10 mormot.rest.server.TRestServer.Uri ...
```

The level marker is `EXC` for `sllException` and `OSE` for `sllExceptionOS`. `sllStackTrace` lines follow only when the address resolves; addresses that the resolver cannot map appear as raw hex.

### 4. Build for stack traces: `.map` (Delphi) and DWARF (FPC)

mORMot 2's address-to-line resolver reads either a Delphi-style `.map` file (parsed by `mormot.core.log` at startup) or an FPC binary with embedded DWARF debug info (read via `mormot.core.log` + `mormot.lib.libcrypto` or the OS-native debug API). Without one of these, every stack trace is raw hex, and every leak report is "[allocated at $00007FF6C123ABCD]" with no further information.

- **Delphi**: build with `-GD` (or `<DCC_MapFile>3</DCC_MapFile>` in `.dproj`) to emit a *detailed* map. Ship the `.map` next to the `.exe`. mORMot reads it on first stack trace.
- **FPC**: build with `-gw3 -gl` (DWARF v3 + line numbers). The debug info is embedded in the binary; nothing extra to ship. For smaller binaries, run `objcopy --only-keep-debug` to split off a `.dbg` companion file, then `objcopy --add-gnu-debuglink` to wire the binary back to it.
- **Cross-compiled FPC binaries**: the host's binutils strip differs from the target's; always use the `<target>-objcopy` and `<target>-strip` from the cross toolchain, never the host versions.

`scripts/delphi-build.ps1` passes `-GD` when `-Compiler dcc64` is selected and `Config != Release-Stripped`; `scripts/fpc-build.sh` passes `-gw3 -gl` by default. See `references/reading-stack-traces.md` for the symbol-resolution toolchain (mORMot built-in, `addr2line`, `Map2DWARF` on Delphi for Lazarus interop).

### 5. Read FastMM4 / `fpcx64mm` leak reports

A leak at shutdown reaches you as a multi-line text dump. The FastMM4 (Delphi) and `mormot.core.fpcx64mm` (FPC) versions share the same shape: a count, a per-allocation size class, and (when `FullDebugMode` / `FPCMM_DEBUG` is on) a stack trace per allocation:

```
This application has leaked memory. The small block leaks are
(excluding any internal expected leaks of the memory manager):

5 - 12 bytes: TStringBuilder x 2, UnicodeString x 1
121 - 132 bytes: TMyService x 1
   Stack trace of leak:
     0x00007FF6C123ABCD mymain.pas TMyService.Create (line 87)
     0x00007FF6C123CDEF mymain.pas WireUp (line 142)
```

Reading the report:

1. **Count and size** — `TMyService x 1` at `121-132 bytes` means one instance of an object whose size lands in the `[121,132]` block size. Match against `SizeOf(TMyService) + class header (16 B on 64-bit)`.
2. **Stack trace** — only present in `FullDebugMode` (Delphi FastMM4) or with `-dFPCMM_DEBUG -dFPCMM_FULLDEBUG` (FPC `fpcx64mm`). Without these, you see only the count and the class name (RTTI-derived).
3. **False positives** — finalization-order leaks of mORMot global singletons (`TRestOrmCache.Done` running before `TRttiCustom.Done`) are tracked as expected leaks; the manager subtracts them. Real false positives come from dynamic packages (BPLs/SO that unload before the manager checks) and from string interning (`mormot.core.text.UniqueRawUtf8` keeps a global hash table).

`scripts/delphi-build.ps1 -Config Debug` enables `FullDebugMode`; `scripts/fpc-build.sh --debug` enables `FPCMM_DEBUG`. See `references/fastmm4-leaks.md` for false-positive triage and the full "what the bytes mean" decoder.

### 6. Map a raw address to a source line

When the log says `$00007FF6C123ABCD` and nothing else, mORMot's parser failed to find symbols. Three resolvers, in order of preference:

```pascal
// Delphi .map already loaded at startup:
TDebugFile.FindLocation(addr) -> 'mymain.pas (123)'

// FPC DWARF (requires -gw3 -gl):
GetCallerAddr(addr) -> 'mymain.pas (123)'

// Last resort, external tool:
//   addr2line -e myserver.exe -f -i 0x401abc       (FPC, GNU binutils)
//   Map2DWARF myserver.map myserver.dwarf          (Delphi -> FPC tooling)
```

The most common cause of "no symbols" is a `.map` next to the *source tree* but not next to the *deployed binary*. Always copy `.map` together with `.exe` in your release archive; on FPC, prefer the embedded DWARF path so there is nothing extra to copy. See `references/reading-stack-traces.md` for offsets, ASLR adjustments, and how to handle stripped binaries with split `.dbg` files.

## Common pitfalls

- **`.map` not deployed alongside `.exe`.** Delphi releases routinely ship the binary without the map; the resulting log shows raw hex addresses and nobody can resolve them after the fact. Either include `myserver.map` in the release archive (it's small, gzip-friendly), or build with FPC + DWARF where the symbols travel inside the binary. Verify on a clean machine before shipping: copy `.exe` only, run, raise an exception, confirm the log resolves the stack frame.
- **`Family.Level := LOG_VERBOSE` left in production.** Verbose logs include `sllEnter` / `sllLeave` for every instrumented method; on a busy server that is gigabytes per hour and a measurable throughput hit. Use `LOG_NFO` (info + warning + error + monitoring) as the production default; promote to `LOG_VERBOSE` only inside an `if SomeDebugMode then ... else` gate, or by SIGUSR1-style reload.
- **FastMM4 false positive on dynamic packages.** A `.bpl` that registers a `TPersistent` descendant and then unloads before `FastMM4` reports leaks looks like a `121-132 bytes: TMyClass x 1` leak with no stack trace. Either keep the package loaded for the lifetime of the host (`LoadPackage` without `UnloadPackage`), or call `RegisterExpectedMemoryLeak` from the package's `Initialization` for each registered class.
- **Logger thread contention on a hot path.** A single global log file with `PerThreadLog := ptIdentifiedInOneFile` serializes writes through one mutex; under heavy contention you can see `sllInfo` calls take 50+ microseconds because they're queued. Either switch to `ptOneFilePerThread` (one file per thread, no contention but harder to read), reduce `Level` so fewer lines compete, or raise `BufferSize` (default 8 KB) so flushes are less frequent.
- **`HandleExceptions := true` and a noisy library.** Enabling exception interception on a project that uses Indy or any TCP library that raises on disconnect (`EIdConnClosedGracefully`, `EIdSocketError`) floods the log. Add the noisy classes to `Family.ExceptionIgnore`, set `ExceptionIgnoreLibrary := true` to skip exceptions raised from inside loaded `.bpl` / `.so` files, or set `ExceptionIgnoreCurrentThread := true` around the noisy worker for the duration of its run.
- **Log file not closed on shutdown.** A program that aborts (`Halt`, signal) without running unit finalization can leave the in-memory `BufferSize` worth of log entries unwritten. The very last few seconds before a crash are exactly the lines you need. Set `AutoFlushTimeOut := 1` (seconds) on a debug build so the background thread flushes continuously, and call `TSynLog.Family.SynLog.Flush` explicitly at the end of your `try/finally` shutdown path.
- **DWARF level too low (`-g` only).** FPC `-g` (or `-gl`) without `-gw3` produces stabs-format debug info, which mORMot's resolver does not parse. Symptom: stack traces show addresses, no source lines, and `objdump --debugging` reports `stabs`. Always pair `-gw3` (DWARF v3) with `-gl` (line numbers) for mORMot compatibility; older Lazarus IDE templates default to `-g` only.
- **`HighResolutionTimestamp := true` with rotation.** The high-resolution timestamp is calibrated once at file open and stored in the file header; switching files mid-process (rotation, daily roll) invalidates the calibration for the new file. Either turn on rotation OR high-resolution timestamps, not both. The compiler does not warn; `Family.SetEchoToConsole` will fail silently when both are set.
- **Stripped FPC binary with DWARF still expected.** A release build run through `strip --all` removes both the symbol table and the DWARF section. mORMot's resolver then walks the binary, finds nothing, and falls back to raw hex. Use `objcopy --only-keep-debug myserver myserver.dbg && strip --strip-debug myserver && objcopy --add-gnu-debuglink=myserver.dbg myserver` so the stripped binary points at the side-loaded debug file; ship the `.dbg` to the support team but not necessarily to end users.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-25.md` - Testing and Logging (the authoritative chapter on `TSynLog`)
- `references/tsynlog-setup.md` - per-environment configuration recipes for `TSynLogFamily`
- `references/fastmm4-leaks.md` - reading FastMM4 / `fpcx64mm` leak reports and triaging false positives
- `references/reading-stack-traces.md` - building with `.map` / DWARF and resolving raw addresses
- `test-driven-development` for writing the test that *causes* the log line you are reading
- `systematic-debugging` for the four-phase Capture/Reproduce/Bisect/Fix workflow that drives this skill's instruments
- `delphi-build` and `fpc-build` for the compile-time flags (`-GD`, `-gw3 -gl`) that make stack traces resolvable
- `mormot2-core` for `RawUtf8`, conditional defines, and the unit conventions every snippet above leans on
- `mormot2-deploy` for log file location, rotation policy, and shipping to a SIEM in production
