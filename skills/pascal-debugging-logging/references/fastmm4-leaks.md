# Reading FastMM4 / `fpcx64mm` leak reports

Delphi ships FastMM4 as the default memory manager (since XE2). Free Pascal ships its own (FPC's `cmem` or the built-in heap manager); for mORMot 2 server workloads, swap to `mormot.core.fpcx64mm` (a FastMM4-derived 64-bit allocator with full server-grade tuning, see `mormot.core.fpcx64mm.pas:12-26`). Both produce the same shape of leak report at shutdown, with different debug-mode flag names.

## Enabling leak reporting

### Delphi + FastMM4

Two switches: turn on the report, and turn on the per-allocation stack trace.

```pascal
program myserver;
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
```

`ReportMemoryLeaksOnShutdown` is the System unit's flag; FastMM4 honours it. Without it, leaks accumulate silently and only the OS reclaims them. `True` triggers the dialog (or stderr, in console apps) at unit finalization.

For per-allocation stack traces, build with `FullDebugMode`:

```
{$DEFINE FullDebugMode}
{$DEFINE LogMemoryLeakDetailToFile}
```

These are FastMM4 conditionals defined in `FastMM4.pas` itself (or in the `FastMM4Options.inc` file when the FastMM4 source is in the project's path). `FullDebugMode` adds an 8-byte block header to every allocation that records the call stack, which the leak report then prints. The cost is roughly 2x memory and 5-10% throughput, so use it only in `Debug` configuration.

### FPC + `mormot.core.fpcx64mm`

Replace FPC's default heap with mORMot's allocator early in the project file (it must be the first unit in `uses`, before any string/object allocation):

```pascal
program myserver;

uses
  {$ifdef FPC_X64MM}
  mormot.core.fpcx64mm,
  {$endif}
  mormot.core.base,
  mormot.core.log;
```

Build with `-dFPC_X64MM`. For per-allocation tracking, add `-dFPCMM_DEBUG -dFPCMM_FULLDEBUG`:

```bash
fpc -dFPC_X64MM -dFPCMM_DEBUG -dFPCMM_FULLDEBUG ... myserver.lpr
```

`FPCMM_DEBUG` adds leak detection; `FPCMM_FULLDEBUG` adds per-allocation stack traces. `FPCMM_BOOST` is a release-only switch (small-block fast path; not compatible with the debug switches). Verified against `mormot.core.fpcx64mm.pas` block comments.

## Reading the report

The report has three parts. A small-block summary, a medium/large-block summary, and a per-allocation detail block (only when `FullDebugMode` / `FPCMM_FULLDEBUG` is on):

```
This application has leaked memory. The small block leaks are
(excluding any internal expected leaks of the memory manager):

5 - 12 bytes: TStringBuilder x 2, UnicodeString x 1
121 - 132 bytes: TMyService x 1
521 - 532 bytes: TList<Integer> x 3
4097 - 8192 bytes: TBytes x 1

The sizes of unexpected leaked medium and large blocks are: 65540

Note: detail of memory leaks is shown below.

----- Detail of memory leaks -----

121 - 132 bytes: TMyService x 1
   Stack trace at allocation:
     0x00007FF6C123ABCD mymain.pas TMyService.Create (line 87)
     0x00007FF6C123CDEF mymain.pas WireUp (line 142)
     0x00007FF6C123EE10 myserver.dpr ... (line 28)
```

### Decoding each line

- **`5 - 12 bytes`** = the FastMM4 *small block* size class. Allocations 5..12 bytes inclusive land in this block; the manager rounds up to the next class. So a 6-byte `string` and a 12-byte `TStringBuilder` both end up here.
- **`TMyService x 1`** = one instance of an object whose RTTI name is `TMyService`. The class name comes from the object's VMT, which FastMM4 reads at allocation time and stores in the block header.
- **`UnicodeString x 1`** = a string allocation that has no class (raw memory). FastMM4 inspects the first 4 bytes of the block: a string-reference-counted header, a class pointer in `[Pointer + 0]`, or unknown.
- **`Stack trace at allocation`** = the call stack captured by FastMM4 at the `GetMem` call, resolved against the `.map` / DWARF that was deployed alongside the binary. Without symbols (no `.map` next to the `.exe`), addresses appear as raw hex.

### Block-size math (Delphi 64-bit)

| Block class      | Range         | Header overhead | Notes                                  |
|------------------|---------------|-----------------|----------------------------------------|
| Small            | 1-1024 B      | 16 B            | 16-byte buckets up to 64, 32 to 256, 64 to 1024 |
| Medium           | 1025-260 KB   | 16 B            | 4-byte alignment within the block      |
| Large            | > 260 KB      | OS page         | One `VirtualAlloc` (Win) / `mmap` (Linux) per allocation |

So `TMyService` reported as `121-132 bytes` means: object instance size between 121 and 132 bytes, in the `[121..132]` small-block class with 16 B header. `SizeOf(TMyService) + 16 (class header) + 16 (FastMM4 header)` should land in that range.

## Triaging false positives

Most leak reports contain mostly false positives on a healthy mORMot 2 application. Common patterns:

### Finalization-order leaks of mORMot globals

`mormot.core.json` registers global `TRttiCustom` instances at unit `Initialization`; these are intended to live for the process and are freed in `Finalization`. If your unit is finalised *before* `mormot.core.json`, you see the framework's globals listed as leaks because FastMM4's snapshot ran before mORMot finished tearing down. Symptom: leaks reported with class names like `TRttiCustom`, `TSynList`, `TSynDictionary`. Fix: ensure your `Finalization` does not call `Halt`; let the unit chain run.

### Dynamic packages (BPLs / SOs)

A `.bpl` that registers types and unloads before the leak check looks like a pile of class instances with no stack trace. The FastMM4 header points at code that is no longer mapped. Symptom: the class names look unfamiliar, the stack trace shows `[unknown]` or hex-only addresses, and the count matches the package's registered types.

Fix one of two ways:

1. **Keep the package loaded** for the lifetime of the host (`LoadPackage` without a matching `UnloadPackage`).
2. **Mark expected leaks** in the package's `Initialization`:
   ```pascal
   {$IFDEF DEBUG}
   RegisterExpectedMemoryLeak(SizeOf(TMyClass));    // by size
   RegisterExpectedMemoryLeak(@MyGlobalSingleton);  // by pointer
   {$ENDIF}
   ```

### String interning

`mormot.core.text.UniqueRawUtf8` and friends keep a global hash table of interned `RawUtf8` values. The table grows for the life of the process and is freed at `Finalization`. If your leak report shows a single `UnicodeString` or `RawUtf8` with no stack trace, and the size matches a small string you handed to an interner once, it is the cache, not a real leak. `mormot.core.text` registers these as expected leaks via `RegisterExpectedMemoryLeak`; if you see them, your `FastMM4Options.inc` is overriding the registration.

### RTL caches (Delphi)

`SysUtils.GMonitorSupport`, `System.Generics.Collections.TArray<*>` template instantiations, and `Variants.NullVariant` are RTL globals that FastMM4 tracks as leaks unless the RTL adds them to its expected list. Most modern Delphi versions do; older ones (XE2-XE7) do not, and you see ~5-10 RTL "leaks" on every shutdown of every program.

### Genuine leak fingerprints

A *real* leak typically shows:

- Multiple instances of the same class (`TMyClass x 17`), increasing run over run.
- A stack trace pointing at user code (`mymain.pas`, `myservice.pas`).
- Allocations in the medium/large block range (deliberate large buffers, dynamic arrays, untracked `TStream` content).

When in doubt, run the program twice with the same workload and compare reports: framework / RTL leaks are stable; genuine leaks scale with iterations.

## Tools that read the report

- **mORMot's `TSynLog` does not write the leak report itself**; FastMM4 / `fpcx64mm` writes to stderr (or to a `.txt` next to the executable when `LogMemoryLeakDetailToFile` is set).
- **MadExcept** and **EurekaLog** (Delphi commercial) can replace FastMM4's report with a richer one that resolves symbols against the `.map` even when FastMM4 itself only has hex addresses. They install a memory-manager hook that runs *before* FastMM4's, so the two cannot run together.
- **Heaptrc** (FPC built-in, `-gh`) is FPC's equivalent for projects that have *not* swapped in `fpcx64mm`. It produces a similar report with DWARF-resolved stack traces. Cannot be used alongside `mormot.core.fpcx64mm` (each unit replaces `MemoryManager`); pick one.

## See also

- `tsynlog-setup.md` - the logger that runs alongside the leak detector at runtime
- `reading-stack-traces.md` - resolving the addresses in `Stack trace at allocation`
- `mormot.core.fpcx64mm.pas` - the FPC allocator (FastMM4 algorithms; lines 1-100 list options)
- FastMM4 `FastMM4Options.inc` - the canonical option list for the Delphi allocator
- `delphi-build` for `-V` / `-GD` flags that make `.map` resolution work
- `fpc-build` for `-gw3 -gl` flags that make DWARF resolution work
