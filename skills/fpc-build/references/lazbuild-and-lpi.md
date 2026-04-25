# `lazbuild` and the `.lpi` project file

A Lazarus project ships two files alongside the source:

- `myproject.lpi` — XML project info (search paths, build modes, package deps, target OS/CPU). The IDE writes it; `lazbuild` and the IDE both consume it. Source-controlled.
- `myproject.lpr` — the program entry point (`program myproject; ... begin ... end.`). Source-controlled.

`lazbuild` is the headless command-line builder. It reads `.lpi` exactly the way the IDE does, then drives `fpc` with the flags the project specifies. CI uses `lazbuild`; developers use the IDE; both produce the same binary because both consume the same `.lpi`.

## `.lpi` schema sketch

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>                          <!-- IDE format version -->
    <General>
      <Flags>
        <CompatibilityMode Value="True"/>
      </Flags>
      <SessionStorage Value="InProjectDir"/>
      <Title Value="myserver"/>
      <Scaled Value="True"/>
      <ResourceType Value="res"/>
      <UseXPManifest Value="True"/>
    </General>
    <BuildModes Count="2">
      <Item1 Name="Debug" Default="True"/>         <!-- references CompilerOptions below -->
      <Item2 Name="Release">
        <CompilerOptions>
          <Version Value="11"/>
          <Target>
            <Filename Value="bin/$(TargetCPU)-$(TargetOS)/myserver"/>
          </Target>
          <SearchPaths>
            <IncludeFiles Value="$(MORMOT2_PATH)/src;$(MORMOT2_PATH)/src/core"/>
            <OtherUnitFiles Value="$(MORMOT2_PATH)/src;$(MORMOT2_PATH)/src/core;$(MORMOT2_PATH)/src/orm;$(MORMOT2_PATH)/src/rest;$(MORMOT2_PATH)/src/soa;$(MORMOT2_PATH)/src/db;$(MORMOT2_PATH)/src/crypt;$(MORMOT2_PATH)/src/net;$(MORMOT2_PATH)/src/app;$(MORMOT2_PATH)/src/lib"/>
            <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
          </SearchPaths>
          <Parsing>
            <SyntaxMode Value="ObjFPC"/>
            <CStyleOperator Value="True"/>          <!-- the -Sci equivalent -->
          </Parsing>
          <CodeGeneration>
            <SmartLinkUnit Value="True"/>            <!-- -CX -->
            <Optimizations>
              <OptimizationLevel Value="3"/>         <!-- -O3 -->
            </Optimizations>
          </CodeGeneration>
          <Linking>
            <Debugging>
              <GenerateDebugInfo Value="False"/>     <!-- Release: strip -->
              <UseLineInfoUnit Value="False"/>
            </Debugging>
            <LinkSmart Value="True"/>                <!-- -XX -->
            <Options>
              <Win32>
                <GraphicApplication Value="False"/>  <!-- console app -->
              </Win32>
            </Options>
          </Linking>
          <Other>
            <CustomOptions Value="-dFPC_X64MM -dFPCMM_BOOST"/>
          </Other>
        </CompilerOptions>
      </Item2>
    </BuildModes>
    <RequiredPackages Count="1">
      <Item1>
        <PackageName Value="LCL"/>
      </Item1>
    </RequiredPackages>
    <Units Count="1">
      <Unit0>
        <Filename Value="myserver.lpr"/>
        <IsPartOfProject Value="True"/>
      </Unit0>
    </Units>
  </ProjectOptions>
</CONFIG>
```

The schema is verbose; the IDE writes 200-300 lines for a non-trivial project. The four sections that matter for build reproducibility are:

- `<BuildModes>` — every CI configuration is a named `<Item>` here.
- `<SearchPaths>` — `OtherUnitFiles` (`-Fu`), `IncludeFiles` (`-Fi`), `UnitOutputDirectory` (`-FU`).
- `<Parsing>` — must specify `ObjFPC` and `CStyleOperator=True` for mORMot.
- `<Other><CustomOptions>` — flags `lazbuild` passes through to `fpc` verbatim. Where you set `-d` defines and any flag without an IDE checkbox.

## `lazbuild` command line

```bash
# Build the default mode (the one with Default="True").
lazbuild myserver.lpi

# Build a specific mode.
lazbuild myserver.lpi --build-mode=Release

# Build every mode.
lazbuild myserver.lpi --build-all

# Override target OS/CPU at the command line.
lazbuild myserver.lpi --build-mode=Release --os=linux --cpu=aarch64

# Force rebuild even when nothing changed.
lazbuild myserver.lpi --build-mode=Release -B

# Quiet mode for CI logs.
lazbuild myserver.lpi --quiet

# Enable extra verbosity to debug a failing build.
lazbuild myserver.lpi --verbose

# Skip dependency checks (sibling packages already built).
lazbuild myserver.lpi --skip-dependencies
```

Useful environment variables:

- `LAZARUSDIR` — path to the Lazarus install (so `lazbuild` finds its `lazarus.cfg`, IDE packages, and translations).
- `FPCDIR` — path to the FPC source (used by some IDE features; harmless to leave unset for `lazbuild`-only flows).
- `PP` — full path to the FPC binary; override when several FPCs are installed.

## Project versus package

A `.lpi` is a *project* (produces an executable). A `.lpk` is a *package* (produces `.ppu` files plus optional resources, registered into the IDE's package list). `lazbuild` builds both:

```bash
# Build a package, register its units so projects that depend on it can find them.
lazbuild --add-package mypackage.lpk

# Build a package without registering (just compile its units).
lazbuild --build-ide=mypackage.lpk
```

Projects depend on packages via `<RequiredPackages>` in the `.lpi`. The IDE resolves the dependency graph; `lazbuild` does the same when `--skip-dependencies` is NOT passed. CI typically wants the explicit graph: build packages first, projects last.

## Per-mode override rules

When a `.lpi` has multiple `<Item>` entries under `<BuildModes>`, each can override any compiler option independently. The default mode is the one with `Default="True"`. Modes do NOT inherit from one another: each `<CompilerOptions>` block is complete. The IDE uses a "matrix options" feature to share settings across modes; that machinery generates expanded copies into the `.lpi` so `lazbuild` always reads the resolved set.

Common patterns:

- **`Debug`** — `-O- -gw3 -gl -godwarfsets`, `LinkSmart=False`, `GenerateDebugInfo=True`, no `-XX`.
- **`Release`** — `-O3 -CX -XX -Xs`, `LinkSmart=True`, `GenerateDebugInfo=False`, `UseLineInfoUnit=False`.
- **`Test`** — like Debug plus `-dMORMOT2TESTS`, plus a different `Filename` so the test binary lives next to the prod binary.
- **`Profile`** — like Release but with `GenerateDebugInfo=True` so `pprof`/`perf` can resolve symbols.

Switch modes from CI with `--build-mode=<name>`. Switch target architecture without editing the `.lpi` with `--os=<os> --cpu=<cpu>` (the mode's own `<TargetOS>`/`<TargetCPU>` is overridden by these flags).

## IDE-only paths (the trap)

`Tools | Options | Files | Other unit files (-Fu)` adds paths to the IDE's `environmentoptions.xml`, NOT to the `.lpi`. The IDE finds those units; `lazbuild` does not, because `environmentoptions.xml` lives in the developer's home directory.

Symptom: the project compiles in the IDE, fails in CI with `Fatal: Can't find unit ...`.

Fix: move every dependency path into the `.lpi` under `Project Options | Compiler Options | Paths | Other unit files` (writes to `<OtherUnitFiles>` in the `.lpi`). Or, register the dependency as a `.lpk` package and add it to `<RequiredPackages>`, so the IDE and `lazbuild` resolve it the same way.

## `lazbuild` exit codes

| Code  | Meaning                                                              |
|-------|----------------------------------------------------------------------|
| 0     | Success                                                              |
| 1     | Misuse (bad flag, missing project file)                              |
| 2     | Project file does not exist                                          |
| Other | Build failed; `fpc` errors propagate the exit code from the compiler |

`scripts/fpc-build.sh` re-emits `BUILD_RESULT exit=... errors=... warnings=...` after the wrapped `lazbuild` so CI can parse a single line regardless of whether the underlying tool was `fpc` or `lazbuild`.
