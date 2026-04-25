# Reading stack traces

Every stack trace in a `TSynLog` log file or a FastMM4 leak report starts as a list of return addresses. Turning those addresses into `unitname.pas (123)` requires (a) symbols that match the binary, and (b) a resolver that knows how to read them. This reference covers both halves.

## What a stack trace looks like

A `sllStackTrace` line in a mORMot 2 log looks like:

```
20240101 12:34:56 stack $00007FF6C123ABCD $00007FF6C123AC10 $00007FF6C123EE10 ...
```

When mORMot's resolver finds symbols, the same line expands at write time into one address per row, with module + unit + line:

```
20240101 12:34:56 stack $00007FF6C123ABCD myserver mymain.MyMethod (mymain.pas:123)
                       $00007FF6C123AC10 myserver mormot.rest.server.TRestServer.Uri (mormot.rest.server.pas:1234)
                       $00007FF6C123EE10 myserver myserver.dpr 28
```

If the resolver fails (no symbols, mismatched build), only the first form ever lands in the file. There is no rerun: the addresses captured at log time are matched against symbols *at log time*, not at read time.

## Build settings (the prerequisite)

### Delphi: emit a `.map`

The `.map` file is a text file the linker writes alongside `.exe`; mORMot's `TDebugFile` parses it on first stack trace. There are three levels:

| `.dproj` `<DCC_MapFile>` | `dcc64` flag | What it contains                                  |
|--------------------------|--------------|---------------------------------------------------|
| `0`                      | none         | No `.map` produced                                |
| `1`                      | `-GS`        | Segments only                                     |
| `2`                      | `-GP`        | Publics                                           |
| `3`                      | `-GD`        | **Detailed** (segments + publics + line numbers)  |

Always use `3` / `-GD` for a build whose stack traces you might one day want to read; the file is ~5 MB for a 50 KLOC project, gzip-friendly. Set in `.dproj`:

```xml
<DCC_MapFile>3</DCC_MapFile>
```

Or on the command line:

```powershell
dcc64.exe -GD -B myserver.dpr
```

`scripts/delphi-build.ps1` passes `-GD` by default for `Debug` and `Release-MapEnabled`; pass `-Config Release-Stripped` to suppress it for size-sensitive deployments.

### FPC: emit DWARF

DWARF debug info is embedded in the binary (no separate file by default). Three flags:

| Flag    | What it does                                               |
|---------|------------------------------------------------------------|
| `-g`    | Generate generic debug info (defaults to stabs on legacy)  |
| `-gw3`  | DWARF v3 (mORMot's resolver expects v3 or v4)              |
| `-gw2`  | DWARF v2 (also accepted; older toolchains)                 |
| `-gl`   | Add line numbers (always pair with `-gw*`)                 |
| `-gh`   | Enable HeapTrc leak detector (mutually exclusive with `fpcx64mm`) |

The right combination for mORMot 2 is `-gw3 -gl`. Stabs (`-g` alone, on older Lazarus IDE templates) does not parse; symptom: stack traces show addresses, no source lines. `scripts/fpc-build.sh` passes `-gw3 -gl` by default.

To split DWARF off into a side file (smaller binary, separate symbol shipment):

```bash
objcopy --only-keep-debug myserver myserver.dbg
strip --strip-debug myserver
objcopy --add-gnu-debuglink=myserver.dbg myserver
```

The final binary now contains a `.gnu_debuglink` section pointing at `myserver.dbg`. mORMot's resolver reads the link and falls back to the side file when it does not find DWARF in the binary itself. Cross-compiled targets MUST use the matching cross-binutils (`aarch64-linux-objcopy`, not the host `objcopy`).

## Resolving an address by hand

Sometimes the captured log lines lack symbols, but you still have the binary, and you want to map the addresses now. Three resolvers, in order of preference.

### 1. mORMot built-in (Delphi `.map` / FPC DWARF)

mORMot 2's `mormot.core.log.pas` exposes `TDebugFile` for ad-hoc resolution from another tool:

```pascal
program resolve;
{$I mormot.defines.inc}
uses
  mormot.core.base,
  mormot.core.log;

var
  dbg: TDebugFile;
  addr: PtrUInt;
begin
  dbg := TDebugFile.Create('myserver.exe'); // looks for .map or DWARF
  try
    addr := $00007FF6C123ABCD;
    Writeln(dbg.FindLocation(addr));         // -> 'mymain.pas (123)'
  finally
    dbg.Free;
  end;
end.
```

`TDebugFile.FindLocation(absolute address)` returns `'unitname.pas (line)'` or `''` if the address is outside the module. `TDebugFile.FindLocationShort` returns the unit + line in shorter form.

### 2. `addr2line` (FPC / GNU binutils)

For FPC binaries with DWARF (or split `.dbg` files), `addr2line` from binutils resolves addresses:

```bash
# Single address, with function name and inlining:
addr2line -e myserver -f -i 0x401abc
# Output:
#   TMyService.PostOrder
#   /src/myproject/myservice.pas:142

# Bulk: pipe a list:
echo "0x401abc 0x401d00 0x402100" | xargs -n1 addr2line -e myserver -f
```

`-e` selects the binary, `-f` adds function names, `-i` walks inlined frames. For cross-targets, use the cross binutils (`aarch64-linux-gnu-addr2line`).

### 3. `Map2DWARF` (Delphi `.map` to FPC tooling)

When a Delphi-built binary has only a `.map`, but you want to feed the symbols into a tool that expects DWARF (`gdb`, `addr2line`, IDE plugins), `Map2DWARF` (third-party, ships in some Lazarus distributions) converts:

```bash
Map2DWARF myserver.map myserver.dwarf
# Now myserver.dwarf is consumable by addr2line / objdump.
```

Useful when the runbook expects FPC-style tooling but the producer is Delphi.

## Address spaces and ASLR

A 64-bit Windows executable runs at a base address that ASLR randomizes per-launch (typically `0x00007FF6...`). The `.map` records *RVA* (relative virtual addresses, `0x00401abc`) plus the preferred image base (`0x00400000`). To resolve a captured absolute address `A`:

```
relative = A - actual_image_base + map_image_base
```

mORMot's `TDebugFile.FindLocation` does this automatically by reading the runtime image base on call. For external tools (`addr2line`), the address you pass must already be the relative one. `addr2line -e myserver -j .text 0x1abc` is the form when working in section-relative offsets.

For Linux PIE binaries (the default since GCC 10 / FPC 3.2.2 with `-Cg`), the image base is the load address of the first PT_LOAD segment, available at runtime in `/proc/self/maps`. `mormot.core.log` reads this on first stack trace.

For shared libraries / `.so` / `.bpl`, each module has its own base; mORMot's resolver records which module each frame belongs to and picks the correct map. `addr2line` with `-e` only resolves one module at a time; bulk-resolving a stack trace that crosses modules requires per-module passes.

## Common failure modes

- **`.map` next to source, not next to deployed binary.** The compiler writes `.map` to the same folder as `.exe` at build time; release archives often skip it. Always include the `.map` in the artefact zip.
- **Mismatched binary and `.map`.** A rebuild without re-shipping the `.map` causes the resolver to find symbols at the wrong addresses; the resolved unit/line is then *wrong* (often within ~10 lines of correct, sometimes wildly off). Always pair `.exe` and `.map` from the same build.
- **Stripped FPC binary, missing `.dbg`.** `strip --all` removes DWARF; mORMot then reports raw hex. Use `strip --strip-debug` (keeps symbols, removes only debug info) plus the side `.dbg` file approach above.
- **`-g` only, no `-gw3`.** Stabs format; mORMot does not parse it. Symptom: `objdump --debugging myserver` reports `stabs`. Fix: rebuild with `-gw3 -gl`.
- **Cross-compiled binary, host binutils.** Stripping a `linux/aarch64` binary with `x86_64-w64-mingw32-strip` produces a corrupted ELF. Always use the cross-target's binutils.
- **`HighResolutionTimestamp := true` plus stack trace.** The high-res timer captures a TSC value; the symbol resolution still uses the address. They do not interact, but new readers occasionally assume "raw hex addresses" and "raw hex timestamps" are the same column. They are not: `+ 01.512.320` is microseconds; `$00007FF6...` is an address.

## Quick reference

| You have                                          | You need                          | Tool                                                        |
|---------------------------------------------------|-----------------------------------|-------------------------------------------------------------|
| Delphi `.exe` + `.map`                             | Resolve a captured address        | mORMot `TDebugFile.FindLocation`                            |
| FPC binary with `-gw3 -gl`                         | Resolve a captured address        | mORMot `TDebugFile.FindLocation`, `addr2line -e bin -f -i`  |
| FPC binary stripped, `.dbg` side file              | Resolve a captured address        | `addr2line -e bin -f -i` (reads the debuglink automatically)|
| Delphi `.map`, want DWARF for `gdb` / IDE plugin   | DWARF copy of the symbols         | `Map2DWARF map dwarf`                                       |
| Cross-compiled aarch64 ELF                         | Strip / resolve                   | `aarch64-linux-gnu-strip`, `aarch64-linux-gnu-addr2line`    |
| Stack trace inside `.bpl` / `.so`                  | Per-module resolution             | mORMot's resolver auto-detects; `addr2line` needs `-e <bpl>`|

## See also

- `tsynlog-setup.md` - configuring `LevelStackTrace` so the trace gets captured in the first place
- `fastmm4-leaks.md` - the same address-resolution applies to leak-report stack traces
- `mormot.core.log.pas:130-180` - the `TDebugFile` declaration and its `FindLocation` method
- `delphi-build` - `-GD` and `<DCC_MapFile>3</DCC_MapFile>`
- `fpc-build` - `-gw3 -gl` and the cross-binutils setup
