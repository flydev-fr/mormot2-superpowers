---
name: delphi-build
description: Use when configuring Delphi builds: dcc32/dcc64 flags, .dproj search paths, MSBuild targets, conditional defines. Do NOT use for FPC/Lazarus (use fpc-build) or runtime config (use mormot2-deploy).
---

# delphi-build

Build-time configuration for Delphi projects that consume mORMot 2: command-line `dcc32` / `dcc64` invocations, `.dproj` XML structure, MSBuild targets (`Build`, `Rebuild`, `Make`, `Clean`, `Compile`), unit/include search paths into `$(MORMOT2_PATH)/src/{core,orm,rest,soa,db,crypt,net,app,lib}`, and conditional defines that toggle features at compile time (`USEZEOS`, `NOSYNDBZEOS`, `MORMOT2TESTS`, `FPC_X64MM`, `DEBUG`). This skill teaches WHY/WHICH flags to set; the wrapper script `scripts/delphi-build.ps1` covers WHEN/HOW to drive them from CI. It assumes the runtime/topology decisions of `mormot2-deploy` (services, reverse proxy, static libs) and stops where Free Pascal begins: `-Fu`, `-Mobjfpc`, `lazbuild`, and cross-targets all belong in `fpc-build`.

## When to use

- Adding a `<DCC_UnitSearchPath>` or `<DCC_Include>` entry to `.dproj` so a project picks up `mormot.core.base.pas`, `mormot.orm.core.pas`, and the rest of the namespace tree under `$(MORMOT2_PATH)/src`.
- Choosing between `dcc32`, `dcc64`, and `msbuild` from the command line: which one resolves which configuration, which one understands `.dproj` properties, and which one needs explicit `-U` / `-I` / `-NS`.
- Defining or removing build-time conditionals (`{$DEFINE DEBUG}`, `{$DEFINE FPC_X64MM}`, `{$DEFINE USEZEOS}`) either in the `.dproj` `<DCC_Define>` block or via `/p:DCC_Define="DEBUG;FPC_X64MM"` on the MSBuild command line.
- Switching a `.dproj` between Debug and Release, or Win32 and Win64, via `/p:Config=Release /p:Platform=Win64` so the same source tree produces both builds without IDE clicks.
- Wiring `scripts/delphi-build.ps1` into CI: pinning `MORMOT2_PATH`, parsing the `BUILD_RESULT exit=... errors=... warnings=...` trailer, and choosing `-Compiler dcc64` versus `-Compiler msbuild` for a given project file.
- Diagnosing `F1026 File not found: 'mormot.core.base.dcu'` and similar errors that almost always trace back to a missing search path or a stale DCU output directory.

## When NOT to use

- Free Pascal Compiler or Lazarus builds: `-Mobjfpc`, `-Sci`, `-Fu`, `-Fi`, `.lpi`, `lazbuild`, cross-compilation targets. Use **fpc-build**.
- Runtime deployment: bundling static C archives, registering Windows Services, writing systemd units, choosing a reverse proxy. Use **mormot2-deploy**. (Static-link conditionals such as `STATICSQLITE` *do* belong here when the question is "how do I set the define"; they belong in **mormot2-deploy** when the question is "do I want to ship a single binary".)
- In-process TLS, ACME, HTTP engine selection. Use **mormot2-net**.
- REST routes, SOA contracts, `TRestServer` lifecycle. Use **mormot2-rest-soa**.
- `RawUtf8`, `TSynLog`, `TDocVariant`, RTTI conventions used in the examples. Use **mormot2-core**.

## Core idioms

### 1. Inject mORMot 2 search paths into `.dproj`

A `.dproj` is MSBuild XML. Each configuration (`Cfg_1`, `Cfg_2`, `Base`) has a `<PropertyGroup>` whose `<DCC_UnitSearchPath>` is a semicolon-separated list. Add `$(MORMOT2_PATH)\src` and the per-namespace subfolders so the compiler finds `mormot.core.*`, `mormot.orm.*`, `mormot.rest.*`, etc.

```xml
<PropertyGroup Condition="'$(Base)'!=''">
  <DCC_UnitSearchPath>$(MORMOT2_PATH)\src;$(MORMOT2_PATH)\src\core;$(MORMOT2_PATH)\src\orm;$(MORMOT2_PATH)\src\rest;$(MORMOT2_PATH)\src\soa;$(MORMOT2_PATH)\src\db;$(MORMOT2_PATH)\src\crypt;$(MORMOT2_PATH)\src\net;$(MORMOT2_PATH)\src\app;$(MORMOT2_PATH)\src\lib;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
  <DCC_Include>$(MORMOT2_PATH)\src;$(DCC_Include)</DCC_Include>
  <DCC_UnitAlias>WinTypes=Windows;WinProcs=Windows;DbiTypes=BDE;$(DCC_UnitAlias)</DCC_UnitAlias>
</PropertyGroup>
```

The trailing `$(DCC_UnitSearchPath)` keeps inherited entries (parent group, IDE library path). Always prepend mORMot rather than appending: when two units share a name, the leftmost path wins, and you want yours, not whatever an IDE add-on registered globally.

### 2. Compile a `.dpr` directly with `dcc64`

When you do not have a `.dproj` (a small tool, a test harness), `dcc64` takes the same paths on the command line. `-U` adds a unit search path, `-I` an include search path, `-NS` an implicit namespace, `-O` an object/DCU output dir, and `-B` forces a rebuild.

```powershell
$mormot = $env:MORMOT2_PATH
& dcc64.exe `
  -U"$mormot\src;$mormot\src\core;$mormot\src\orm;$mormot\src\rest" `
  -I"$mormot\src" `
  -NSSystem -NSWinapi -NSData.DB `
  -O"$PSScriptRoot\dcu" `
  -DDEBUG -B `
  myserver.dpr
```

`scripts/delphi-build.ps1` wraps exactly this: it expands the path list under `$env:MORMOT2_PATH/src`, drops any subfolder that does not exist on disk, and quotes each `-U` / `-I` argument so spaces in the install path do not split the token. See `references/dcc-flags.md` for the full flag table.

### 3. Drive a `.dproj` through MSBuild

For projects that ship a `.dproj`, prefer MSBuild: it honours every `<DCC_*>` property, every per-configuration `<PropertyGroup>`, and produces the same artefacts the IDE produces. Targets are `Build`, `Rebuild`, `Make`, `Clean`, and `Compile`; configuration and platform pivot through `/p:Config=` and `/p:Platform=`.

```powershell
# 1) Activate the RAD Studio environment so $BDS / $BDSCommonDir / $BDSPlatformSDKsDir are set.
& "$env:BDS\bin\rsvars.bat"

# 2) Build a Win64 release.
msbuild myserver.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal

# 3) Re-export defines without touching the .dproj on disk.
msbuild myserver.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define="DEBUG;FPC_X64MM"

# 4) Clean DCUs and EXE for a given config.
msbuild myserver.dproj /t:Clean /p:Config=Release /p:Platform=Win64
```

`Build` runs `Compile` then linking with conditional rebuild; `Rebuild` is `Clean` + `Build`; `Make` only rebuilds units whose source changed. See `references/msbuild-targets.md` for the full target/property matrix.

### 4. Toggle build-time conditionals consistently

mORMot 2 is conditional-heavy: `STATICSQLITE`, `OPENSSLSTATIC`, `LIBDEFLATESTATIC`, `FPC_X64MM`, `NOSYNDBZEOS`, `MORMOT2TESTS`, plus your own (`DEBUG`, `RELEASE`, `STAGING`). Set them in exactly one place per build:

- **In `.dproj`**, under `<DCC_Define>` per-configuration. Survives IDE editing, ships in source control, easy to diff.
- **On the MSBuild command line**, `/p:DCC_Define="DEBUG;FPC_X64MM"`. Right for CI matrix builds where the same `.dproj` produces several binaries.
- **In a shared `.inc` file**, `mormot.defines.inc` style. Right when several `.dpr` files share toggles.

Do not mix: a project that gets `DEBUG` from `.dproj` *and* `/p:DCC_Define=` ends up with `DCC_Define` overriding silently, which yields the wrong binary in CI without any warning. Pick one home and document it next to the build script.

### 5. Run via `scripts/delphi-build.ps1`

The wrapper resolves `MORMOT2_PATH`, picks `dcc32` / `dcc64` / `msbuild`, injects search paths, captures stdout, parses errors and warnings, and emits a single trailer line CI can grep:

```powershell
$env:MORMOT2_PATH = '\src\mormot2'   # absolute path on the build host
pwsh -NoProfile -File scripts/delphi-build.ps1 -Project myserver.dproj -Compiler msbuild
# ...build output...
# BUILD_RESULT exit=0 errors=0 warnings=3 first=
```

Exit codes map cleanly: `0` success, `2` `MORMOT2_PATH` unset/invalid, `5` project missing, `6` no compiler on `PATH`, `7` build failed (errors > 0). CI scripts should grep for the trailer rather than rely on `$LASTEXITCODE` alone, because non-zero exit + zero errors usually means the SDK environment was not loaded (common on bare runners).

## Common pitfalls

- **`BDS` / `BDSCommonDir` unset under CI.** A `dcc64.exe` invocation outside the IDE silently falls back to whatever `dcc64.cfg` is alongside the binary, which on a bare runner means **no** namespace setup and **no** RTL search path. Symptom: `F1026 File not found: 'System.SysUtils.dcu'`. Fix by sourcing `rsvars.bat` (`call "%BDS%\bin\rsvars.bat"` from cmd, `& "$env:BDS\bin\rsvars.bat"` from pwsh) before the compiler runs, every time, in the same shell.
- **`.dproj` `<ProjectVersion>` mismatched against the installed Delphi.** A `.dproj` saved by Delphi 12 (`<ProjectVersion>20.2</ProjectVersion>`) loaded under Delphi 11 silently loses property groups MSBuild does not recognise; a Delphi 11 `.dproj` opened by Delphi 12 IDE auto-upgrades on save and breaks the older box. Pin the IDE to one version per branch, or keep a separate `.dproj.<version>` per supported toolchain. Never rely on "should be backwards compatible".
- **`<DCC_Namespace>` `(default)` versus explicit `-NS`.** The IDE writes `<DCC_Namespace>$(DCC_Namespace)</DCC_Namespace>` and resolves it from registered Delphi versions; MSBuild on a bare runner inherits whatever was set in `rsvars.bat`, which may be empty. `dcc64` invoked directly inherits **nothing** unless you pass `-NSSystem -NSWinapi -NSData.DB ...` explicitly. Symptom: `E2003 Undeclared identifier: 'TStringList'`. Fix by listing the namespaces the project actually needs in the `.dproj` `<DCC_Namespace>` *and* keep `scripts/delphi-build.ps1` passing them on `dcc64` calls.
- **Conditional defines shadowing globals.** `mormot.defines.inc` has its own `{$IFDEF FPC_X64MM}` and `{$IFDEF DEBUG}` logic. A project that also defines `DEBUG` in `<DCC_Define>` and again on `/p:DCC_Define="DEBUG"` is fine *until* a sibling unit's `.inc` does `{$UNDEF DEBUG}`, and now the linker silently drops your debug-only branch. Search the tree (`rg -F '{$DEFINE DEBUG}'`, `rg -F '{$UNDEF DEBUG}'`) before adding a new global.
- **Stale DCU output directory.** `dcc64 -O"dcu"` writes per-configuration DCUs into one directory by default. Switch from `Debug` to `Release` without `-B` (or `Rebuild`) and the linker pulls a Debug DCU into a Release binary, with no error. Either give each configuration its own output directory (`-O"dcu\$Config\$Platform"` or per-config `<DCC_DcuOutput>`), or always `-B` in CI. The `.dproj` IDE template gets this right; hand-rolled `.dpr` builds get it wrong constantly.
- **Spaces in `MORMOT2_PATH` not quoted on the command line.** `dcc64 -U\src\mormot 2\src\core` parses as `-U\src\mormot` plus a positional argument `2\src\core`, which fails with a confusing "no input files" error. Always quote: `-U"$mormot\src\core"`. `scripts/delphi-build.ps1` quotes correctly; ad-hoc `Invoke-Expression` calls usually do not.
- **Mixing 32-bit DCUs into a 64-bit build.** Sharing one DCU folder across `Win32` and `Win64` lets `dcc64` pick up a `Win32` DCU first, then fail at link time with `F2613 Unit 'mormot.core.base' not found`. Always partition output: `<DCC_DcuOutput>$(Platform)\$(Config)</DCC_DcuOutput>` (the IDE default) and the same for `<DCC_ExeOutput>` and `<DCC_BplOutput>`. The leftover-from-IDE-shutdown variant is the most common cause of "works on my machine, fails in CI".
- **`MORMOT2_PATH` set per shell, missing from CI.** Local devs put `MORMOT2_PATH=\src\mormot2` (or wherever they cloned mORMot 2) in their user environment; CI runners have nothing. `scripts/delphi-build.ps1` exits `2` ("MORMOT2_PATH unset") with a clear message, but a hand-rolled `dcc64` call just produces `F1026 File not found: 'mormot.core.base.dcu'` with no hint about why. Set `MORMOT2_PATH` in the CI job's environment block alongside `BDS`, and assert it is non-empty as the first step of the build.

## See also

- `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-26.md` - Installation and Compilation
- `references/dcc-flags.md`
- `references/dproj-anatomy.md`
- `references/msbuild-targets.md`
- `scripts/delphi-build.ps1` - the build wrapper this skill teaches
- `fpc-build` for FPC / Lazarus / cross-compilation builds
- `mormot2-deploy` for runtime topology, services, static-library bundling
- `mormot2-core` for `RawUtf8`, `TSynLog`, and the unit conventions every snippet above leans on
