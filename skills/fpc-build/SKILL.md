---
name: fpc-build
description: Use for FPC/Lazarus builds: -Mobjfpc/-Sci modes, -Fu/-Fi search paths, .lpi files, lazbuild, cross-compilation, FPC_X64MM. Do NOT use for Delphi (delphi-build) or runtime config (mormot2-deploy).
---

# fpc-build

Build-time configuration for Free Pascal Compiler and Lazarus projects that consume mORMot 2: command-line `fpc` invocations, mode selection (`-Mobjfpc`, `-Mdelphi`), unit and include search paths into `$MORMOT2_PATH/src/{core,orm,rest,soa,db,crypt,net,app,lib}`, `.lpi` project files driven by `lazbuild`, and cross-target builds (`-T<os>`, `-P<cpu>`) for ARM, AArch64, and Linux from a Windows host. This skill teaches WHY/WHICH flags to set; the wrapper script `scripts/fpc-build.sh` covers WHEN/HOW to drive them from CI. It assumes the runtime/topology decisions of `mormot2-deploy` (services, reverse proxy, static libs) and stops where Delphi begins: `dcc32`, `dcc64`, `.dproj`, and MSBuild all belong in `delphi-build`.

## When to use

- Adding `-Fu` (unit) and `-Fi` (include) search paths to an `fpc` command line so a project picks up `mormot.core.base.pas`, `mormot.orm.core.pas`, and the rest of the namespace tree under `$MORMOT2_PATH/src`.
- Choosing between `-Mobjfpc` (mORMot's required default) and `-Mdelphi` (compatibility mode) for a given source tree, and pairing it with `-Sci` so C-style operators like `+=` and `^=` parse.
- Configuring a Lazarus `.lpi` project file: search paths, custom build modes (`Debug`, `Release`), package dependencies, and triggering builds from CI via `lazbuild file.lpi --build-mode=Release`.
- Cross-compiling from a Windows host to ARM Linux (`-Tlinux -Parm`), AArch64 Linux (`-Tlinux -Paarch64`), or 32-bit Linux (`-Tlinux -Pi386`) using a pre-built FPC cross toolchain.
- Wiring `scripts/fpc-build.sh` into CI: pinning `MORMOT2_PATH`, parsing the `BUILD_RESULT exit=... errors=... warnings=...` trailer, and switching between `fpc` (for `.dpr`/`.lpr`) and `lazbuild` (for `.lpi`) automatically based on file extension.
- Toggling FPC-specific defines: `FPC_X64MM` (use mORMot's x86_64 memory manager), `FPCMM_BOOST` (boost mode), `FPC_HAS_FEATURE_STACKCHECK` family.
- Diagnosing `Fatal: Can't find unit mormot.core.base used by ...`, which on FPC always traces back to a missing `-Fu`, the wrong mode (`-Mtp`), or a stale `lib/` output dir from a prior architecture.

## When NOT to use

- Delphi command-line builds: `dcc32`, `dcc64`, `.dproj`, MSBuild, `<DCC_*>` properties, `rsvars.bat`. Use **delphi-build**. (Conditional defines such as `STATICSQLITE` apply to both compilers; `delphi-build` covers them on the Delphi side, this skill on the FPC side.)
- Runtime deployment: bundling static C archives with the binary, registering a Windows Service, writing a systemd unit, choosing a reverse proxy. Use **mormot2-deploy**.
- In-process TLS, ACME, HTTP engine selection. Use **mormot2-net**.
- REST routes, SOA contracts, `TRestServer` lifecycle. Use **mormot2-rest-soa**.
- `RawUtf8`, `TSynLog`, `TDocVariant`, RTTI conventions used in the examples. Use **mormot2-core**.

## Core idioms

### 1. Compile a `.dpr` or `.lpr` directly with `fpc`

When you do not have an `.lpi` (a small tool, a CLI, a test harness), `fpc` takes search paths on the command line. `-Fu` adds a unit search path, `-Fi` an include search path, `-FE` sets the executable output dir, `-FU` sets the unit (`.ppu`) output dir, and `-B` forces a rebuild of every unit.

```bash
SRC="$MORMOT2_PATH/src"
fpc \
  -Mobjfpc -Sci \
  -Fu"$SRC" -Fu"$SRC/core" -Fu"$SRC/orm" -Fu"$SRC/rest" \
  -Fi"$SRC" -Fi"$SRC/core" \
  -FE./bin -FU./lib \
  -dDEBUG -B \
  myserver.lpr
```

`-Mobjfpc` enables the Object Pascal mode mORMot 2 is written against; `-Sci` adds C-style operators (`+=`, `-=`, `*=`, `/=`) that mORMot uses heavily. Drop `-Sci` and the compiler will reject perfectly valid mORMot source with cryptic syntax errors. `scripts/fpc-build.sh` wraps exactly this pattern: it expands the path list under `$MORMOT2_PATH/src`, drops any subfolder that does not exist, and quotes each `-Fu`/`-Fi` argument so spaces in the install path do not split the token. See `references/fpc-modes-and-flags.md` for the full flag table.

### 2. Build an `.lpi` through `lazbuild`

Lazarus stores project state in an `.lpi` file: search paths, build modes (`Default`, `Debug`, `Release`, plus any custom modes), package dependencies, target OS/CPU. `lazbuild` is the headless builder that consumes the same `.lpi` the IDE writes, with no GUI.

```bash
# Build the default mode.
lazbuild myserver.lpi

# Build a specific mode.
lazbuild myserver.lpi --build-mode=Release

# Build all modes in a row (CI matrix).
lazbuild myserver.lpi --build-all

# Override the OS/CPU at the command line (cross-compile target).
lazbuild myserver.lpi --build-mode=Release --os=linux --cpu=aarch64

# Skip dependency checks (useful when a sibling package has its own build).
lazbuild myserver.lpi --skip-dependencies
```

Custom search paths configured in the IDE under `Project Options | Compiler Options | Paths` are written into the `.lpi` and travel with source control. Avoid paths added under `Tools | Options | Files`: those live in IDE config and CI runners do not have them. See `references/lazbuild-and-lpi.md` for the `.lpi` schema and per-mode override rules.

### 3. Cross-compile from Windows to Linux/ARM

FPC ships separate compiler binaries per host/target pair, plus a cross-binutils toolchain. The host invokes `fpc` (the Windows binary), passes `-T<os> -P<cpu>` to switch the target, and `fpc` calls into the cross-assembler (`<target>-as`) and cross-linker (`<target>-ld`) found on `PATH` or in `$FPCDIR/bin`.

```bash
# Windows host -> AArch64 Linux target.
fpc -Mobjfpc -Sci \
  -Tlinux -Paarch64 \
  -Fu"$MORMOT2_PATH/src" -Fu"$MORMOT2_PATH/src/core" \
  -FE./bin/aarch64-linux \
  -FU./lib/aarch64-linux \
  myserver.lpr
```

The output unit dir (`-FU`) MUST be partitioned per target: a `.ppu` built for `linux/aarch64` is binary-incompatible with `win64/x86_64` and the linker will silently pick the wrong one if both share `lib/`. `lazbuild` partitions automatically when `Project Options | Paths | Unit output directory` contains `$(TargetOS)-$(TargetCPU)`. Hand-rolled `fpc` calls must do the same. See `references/cross-compilation.md` for host triplets, runtime DLL/SO requirements, and the `-XR<sysroot>` flag for offline cross-builds.

### 4. Toggle FPC-specific defines consistently

mORMot 2 has FPC-only conditional symbols that toggle the bundled memory manager and other runtime features. Set them in exactly one place per build:

- **`FPC_X64MM`** — replace FPC's default heap with mORMot's `mormot.core.fpcx64mm` (faster on multi-threaded server workloads). Set via `-dFPC_X64MM` on the command line or under `Custom Options` in the `.lpi`.
- **`FPCMM_BOOST`** — enables aggressive small-block allocation in `fpcx64mm` (further speedup, slightly more memory).
- **`FPCMM_DEBUG`** — adds leak/double-free detection at the cost of throughput. Pair with a development build, never production.
- **`FPCMM_NOASSEMBLER`** — falls back to pure-Pascal allocator (slower but portable to any CPU).

Do not mix: a project that sets `FPC_X64MM` in the `.lpi` Release mode AND inherits `-dFPC_X64MM` from `lazbuild --build-mode=Release` ends up with the define set twice, which is harmless until a dependency `.inc` does `{$IFDEF FPC_X64MM}{$DEFINE FPCMM_BOOST}{$ENDIF}` and now you get boost mode without asking. Search the tree (`rg -F '{$DEFINE FPC_X64MM}'`, `rg -F '{$UNDEF FPC_X64MM}'`) before adding a new global.

### 5. Run via `scripts/fpc-build.sh`

The wrapper resolves `MORMOT2_PATH`, picks `fpc` versus `lazbuild` from the project file extension, injects search paths under `$MORMOT2_PATH/src`, captures stdout, parses errors and warnings, and emits a single trailer line CI can grep:

```bash
export MORMOT2_PATH=/src/mormot2
scripts/fpc-build.sh --project myserver.lpr
# ...build output...
# BUILD_RESULT exit=0 errors=0 warnings=2 first=

scripts/fpc-build.sh --lpi myserver.lpi
# ...build output...
# BUILD_RESULT exit=0 errors=0 warnings=0 first=
```

Exit codes map cleanly: `0` success, `2` `MORMOT2_PATH` unset/invalid, `5` project missing, `6` `fpc`/`lazbuild` not on `PATH`, `7` build failed (errors > 0). CI scripts should grep for the `BUILD_RESULT` trailer rather than rely on `$?` alone, because some FPC error patterns can leave `$?` at 0 even when the build produced unresolved-unit fatals.

## Common pitfalls

- **Missing `-Sci`.** mORMot 2 source uses `+=`, `-=`, `*=`, and `/=` everywhere. Without `-Sci`, the compiler emits `Error: Illegal expression` or `Error: ":=" expected` at the first such line, with no hint that a single missing flag is the cause. Always pass `-Sci` (or set `Compiler Options | Parsing | C-style operators` in the `.lpi`). `scripts/fpc-build.sh` passes it unconditionally on the `fpc` path; `.lpi` projects must enable it explicitly per build mode.
- **Wrong mode for mORMot 2 (`-Mtp` or `-Mdelphi`).** mORMot 2 requires `-Mobjfpc`. `-Mdelphi` compiles a subset but breaks on operator overloading and inline classes; `-Mtp` (Turbo Pascal) does not get out of unit 1. Symptom: `Error: Operator is not overloaded` or `Error: Identifier not found 'inline'`. Set `-Mobjfpc` on the command line or under `Compiler Options | Parsing | Syntax mode` in the `.lpi`.
- **Lazarus IDE-only paths in `.lpi` not propagating to lazbuild.** Paths added via `Tools | Options | Files | Other unit files` live in the IDE config (`environmentoptions.xml`), not in the `.lpi`. The IDE finds them; `lazbuild` does not. Symptom: builds work in the IDE, fail in CI with `Fatal: Can't find unit ...`. Move every dependency path into the `.lpi` under `Project Options | Compiler Options | Paths | Other unit files`, or pass `--add-package` / `--ws=...` flags to `lazbuild`.
- **Shared lib/ directory across targets.** `fpc -FU./lib` writes `.ppu` files into one directory regardless of target OS/CPU. Switch from `win64` to `linux/aarch64` without `rm -rf lib/` (or without partitioning into `lib/$(TargetOS)-$(TargetCPU)`) and the linker pulls a Win64 `.ppu` into a Linux build, with no error until link time when symbol mangling differs. Always partition: `-FU./lib/$fpctarget`. `scripts/fpc-build.sh` does not auto-partition; CI scripts must clean `lib/` between targets.
- **`MORMOT2_PATH` set per shell, missing from CI.** Local devs put `export MORMOT2_PATH=/src/mormot2` in `.bashrc`; CI runners have nothing. `scripts/fpc-build.sh` exits `2` ("MORMOT2_PATH unset") with a clear message, but a hand-rolled `fpc` call just produces `Fatal: Can't find unit mormot.core.base` with no hint. Set `MORMOT2_PATH` in the CI job's environment block, and assert it is non-empty as the first step of the build.
- **`fpc.cfg` shadowing command-line flags.** FPC reads `fpc.cfg` from `$FPCDIR/etc/`, `~/.fpc.cfg`, and the working directory in that order. A user-level `~/.fpc.cfg` with `-Fu/usr/local/lib/fpc/3.2.2/units/$FPCTARGET` is fine for non-mORMot work but can pull in mismatched `.ppu` versions of shared units (`fpwidestring`, `cwstring`). Pass `-n` to ignore the default config and rely entirely on the explicit flags `scripts/fpc-build.sh` passes, when the build host is shared or untrusted.
- **Mixed FPC versions across CI runners.** mORMot 2 requires FPC 3.2.0 or newer; some skip-list features need 3.2.2. A runner with FPC 3.0.4 produces `Fatal: Can't find unit Generics.Collections` because that unit only landed in 3.2.0. Pin the FPC version per runner (`fpc -iV` should print `3.2.2` or newer), and document the minimum in the project README. Lazarus pinning is separate: a Lazarus 2.0 IDE can drive an FPC 3.2.2 backend, but the `.lpi` schema migrated at Lazarus 2.2 and old IDEs strip new properties on save.
- **Spaces in `MORMOT2_PATH` not quoted.** `fpc -Fu/c/Program Files/mormot2/src` parses as `-Fu/c/Program` plus a positional argument `Files/mormot2/src`, which fails with `Fatal: Compilation aborted`. Always quote: `-Fu"$MORMOT2_PATH/src"`. `scripts/fpc-build.sh` quotes correctly; ad-hoc `eval` calls usually do not. (Even better: install mORMot under a path with no spaces; Windows + MSYS2 path mangling makes spaces fragile no matter how careful the quoting.)

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-26.md` - Installation and Compilation
- `references/fpc-modes-and-flags.md`
- `references/lazbuild-and-lpi.md`
- `references/cross-compilation.md`
- `scripts/fpc-build.sh` - the build wrapper this skill teaches
- `delphi-build` for Delphi `dcc32`/`dcc64`/`.dproj`/MSBuild builds
- `mormot2-deploy` for runtime topology, services, static-library bundling
- `mormot2-core` for `RawUtf8`, `TSynLog`, and the unit conventions every snippet above leans on
