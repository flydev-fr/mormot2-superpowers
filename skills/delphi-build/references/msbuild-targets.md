# MSBuild targets and properties for `.dproj`

`CodeGear.Delphi.Targets` (imported from `$(BDS)\Bin\`) defines the targets MSBuild knows about for a Delphi `.dproj`. Driving them from a script is the supported way to reproduce IDE builds in CI without launching the IDE.

## Targets

| Target     | What it does                                                                                  |
|------------|-----------------------------------------------------------------------------------------------|
| `Build`    | Compile + link with conditional rebuild. Default if no target is specified.                   |
| `Rebuild`  | `Clean` then `Build`. Equivalent to `dcc64 -B`.                                                |
| `Make`     | Build only the units whose source has changed (incremental). Equivalent to `dcc64` default.   |
| `Compile`  | Compile units; do not link. Useful for unit-syntax sanity checks in CI.                        |
| `Clean`    | Delete DCUs, EXE, BPLs, RES (per `<DCC_*Output>` directories). Does not delete project itself. |

Composing them:

```powershell
msbuild myserver.dproj /t:Clean;Build  # same as /t:Rebuild
msbuild myserver.dproj /t:Compile      # parse + typecheck without linking
```

## Properties (`/p:Name=Value`)

Standard MSBuild scalars that drive the build:

| Property      | Values                                                                | Default |
|---------------|-----------------------------------------------------------------------|---------|
| `Config`      | `Debug`, `Release`, or any custom configuration named in the `.dproj` | `Debug` |
| `Platform`    | `Win32`, `Win64`, `OSX64`, `Linux64`, `iOSDevice64`, `Android`, ...   | `Win32` |
| `BuildGroup`  | Build only members of a named group                                   | (all)   |
| `DCC_Define`  | Override the `<DCC_Define>` for this build (semicolon-separated)      | (`.dproj`) |
| `DCC_BuildAllUnits` | `true` to force `-B`                                            | `false` |
| `DCC_Optimize`| `true` / `false` to override `<DCC_Optimize>`                         | (per-config) |
| `DCC_DcuOutput` | Override DCU output directory                                       | (`.dproj`) |
| `DCC_ExeOutput` | Override EXE output directory                                       | (`.dproj`) |

Any `<DCC_*>` property in the `.dproj` can be overridden on the command line with `/p:<Name>=<Value>`. The MSBuild precedence is: command line > per-config group > `Base` group > `Default.Personality.proj` defaults.

Useful verbosity / output flags (MSBuild built-ins, not Delphi-specific):

| Flag                   | Effect                                                          |
|------------------------|-----------------------------------------------------------------|
| `/v:minimal`           | Show only warnings and errors (recommended for CI)              |
| `/v:normal`            | Default verbosity                                               |
| `/v:detailed`          | Show every command issued (useful for debugging)                |
| `/m`                   | Parallel build across `.dproj` files (no effect on a single one)|
| `/nologo`              | Suppress MSBuild copyright banner                               |
| `/fl /flp:LogFile=b.log` | Capture full log alongside console output                     |
| `/p:WarningLevel=4`    | Treat fewer warnings as errors                                  |

## Common command lines

```powershell
# Activate the IDE environment.
& "$env:BDS\bin\rsvars.bat"

# Win64 Release.
msbuild myserver.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal /nologo

# Win64 Debug with extra defines.
msbuild myserver.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_Define="DEBUG;FPC_X64MM"

# Force a full rebuild (clean DCUs, then build).
msbuild myserver.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64

# Compile-only (catch syntax errors without linking).
msbuild myserver.dproj /t:Compile /p:Config=Debug /p:Platform=Win64

# Clean both platforms before re-running CI.
msbuild myserver.dproj /t:Clean /p:Config=Debug   /p:Platform=Win32
msbuild myserver.dproj /t:Clean /p:Config=Debug   /p:Platform=Win64
msbuild myserver.dproj /t:Clean /p:Config=Release /p:Platform=Win32
msbuild myserver.dproj /t:Clean /p:Config=Release /p:Platform=Win64
```

## Exit codes

| Code | Meaning                                                                |
|------|------------------------------------------------------------------------|
| 0    | Success (zero errors)                                                  |
| 1    | Build failed (one or more errors)                                      |
| Other | MSBuild infrastructure error (target not found, project not found, malformed XML, missing import) |

A non-zero exit with **zero** Delphi errors in the output almost always means the import (`$(BDS)\Bin\CodeGear.Delphi.Targets`) failed to load, which means `BDS` is unset or `rsvars.bat` was not sourced. Always assert `$env:BDS` is non-empty as the first step of the build script.

## Configuration file vs IDE projects

The `.dproj` is shared between IDE and MSBuild. The IDE generates a sibling `.dproj.local` and `.dproj.identcache` for personal IDE state (ignored by source control). Never check those in. Some teams add a `.dproj.user` file too; same rule.

## `BuildGroup` and project groups

A `.groupproj` is the MSBuild-shaped wrapper around several `.dproj` files (the IDE's "Project Group"). MSBuild understands them too:

```powershell
msbuild MyApp.groupproj /t:Build /p:Config=Release /p:Platform=Win64
```

Each `.dproj` builds in declaration order. To build only a subset, use `/t:<DProjName>:Build`:

```powershell
msbuild MyApp.groupproj /t:server:Build;tools:Build /p:Config=Release /p:Platform=Win64
```

## Why prefer MSBuild over `dcc64` for `.dproj`

- It honours every `<DCC_*>` property exactly as the IDE does, including the `Base` / `Cfg_N` inheritance.
- It runs the full target chain (resources, type libraries, post-build steps) that `dcc64` skips.
- It produces the same artefacts the IDE produces, in the same output paths, so a CI binary is byte-comparable to a developer binary.

Reach for `dcc64` directly only when you do not have a `.dproj` (a small `.dpr`, an experiment, a test harness). For anything that ships, MSBuild on `.dproj` is the path. `scripts/delphi-build.ps1` picks the right one automatically based on the file extension.
