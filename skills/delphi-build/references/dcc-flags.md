# dcc32 / dcc64 command-line flags

`dcc32.exe` and `dcc64.exe` are the standalone Delphi compilers (Win32 and Win64 respectively). They share the same flag set; the difference is the target platform and the default `dcc<32|64>.cfg` next to the binary. MSBuild eventually invokes one of them, but the IDE and `.dproj` plumbing pass through dozens of `<DCC_*>` properties that map onto these flags. When you build a `.dpr` directly, you spell them out yourself.

## Most-used flags

| Flag                  | Meaning                                                                         | Multiple-allowed | Maps to `.dproj` property |
|-----------------------|---------------------------------------------------------------------------------|------------------|---------------------------|
| `-U<path>`            | Add to **unit** search path (where `.dcu` and `.pas` are looked up)             | Yes              | `<DCC_UnitSearchPath>`    |
| `-I<path>`            | Add to **include** search path (where `{$I file.inc}` is resolved)              | Yes              | `<DCC_Include>`           |
| `-R<path>`            | Add to **resource** search path (`{$R file.res}`)                               | Yes              | `<DCC_ResourcePath>`      |
| `-O<path>`            | Object/DCU **output** directory                                                 | No               | `<DCC_DcuOutput>`         |
| `-N<X><path>`         | Specific output dir per artefact: `-NB` BPLs, `-NH` HPP, `-NS<ns>` namespace    | Yes              | `<DCC_*Output>` family    |
| `-NS<namespace>`      | Implicit namespace (e.g. `-NSSystem -NSWinapi -NSData.DB`)                      | Yes              | `<DCC_Namespace>`         |
| `-D<symbol>[;...]`    | Define conditional symbol(s)                                                    | Yes              | `<DCC_Define>`            |
| `-LE<path>`           | Package output: `.bpl` files                                                    | No               | `<DCC_BplOutput>`         |
| `-LN<path>`           | Package output: `.dcp` files                                                    | No               | `<DCC_DcpOutput>`         |
| `-B`                  | Build **all** units (force rebuild, ignore DCU timestamps)                      | n/a              | `<DCC_BuildAllUnits>`     |
| `-M`                  | Make: rebuild changed units only (default behaviour, but explicit)              | n/a              | n/a                       |
| `-Q`                  | Quiet: suppress informational output (errors and warnings still print)          | n/a              | `<DCC_Quiet>`             |
| `-W[+\|-]<warning>`   | Warning toggle, e.g. `-W-IMPLICIT_STRING_CAST`                                  | Yes              | `<DCC_Warnings>`          |
| `-CC`                 | Console application target                                                      | n/a              | `<DCC_ConsoleTarget>`     |
| `-CG`                 | GUI application target                                                          | n/a              | `<DCC_ConsoleTarget>`=False |
| `-V[<level>]`         | Debug info: `-V` (full), `-VR` (reference), `-VN` (none)                        | n/a              | `<DCC_DebugInformation>`  |
| `-GD`                 | Generate **detailed `.map`** for the linker (used by stack-trace tools)         | n/a              | `<DCC_MapFile>`=3         |
| `-GS`                 | Generate **segments-only `.map`**                                                | n/a              | `<DCC_MapFile>`=1         |
| `-Z`                  | Output `.dpu`/`.drc` for translation                                            | n/a              | `<DCC_DependencyCheckOutputName>` |
| `-AB<unit>=<alias>`   | Unit alias, e.g. `-ABWinTypes=Windows`                                          | Yes              | `<DCC_UnitAlias>`         |
| `--no-config`         | Ignore `dcc<32\|64>.cfg` next to the executable                                 | n/a              | n/a                       |
| `--help`              | List all flags (the canonical reference is the binary itself)                   | n/a              | n/a                       |

## Optimisation and runtime flags

| Flag                 | Meaning                                                                                     |
|----------------------|---------------------------------------------------------------------------------------------|
| `-$O+` / `-$O-`      | Optimisations on/off (per-source `{$O+}` overrides)                                         |
| `-$R+` / `-$R-`      | Range checks on/off                                                                         |
| `-$Q+` / `-$Q-`      | Overflow checks on/off                                                                      |
| `-$D+` / `-$D-`      | Debug info on/off (note: `-V` controls *map/RTI*; `-$D` controls *unit DCU* debug data)     |
| `-$L+` / `-$L-`      | Local symbols on/off                                                                        |
| `-$Y+` / `-$Y-`      | Symbol reference info on/off                                                                |

For a Release build mORMot is happy with: `-$O+ -$R- -$Q- -$D- -$L- -$Y-` plus `-V` and `-GD` (so you keep a `.map` for stack traces). For a Debug build: `-$O- -$R+ -$Q+ -$D+ -$L+ -$Y+ -V -GD`. The `.dproj` IDE templates produce equivalents; this list is the equivalent for hand-rolled `dcc64` calls.

## GExperts and IDE-only overrides

GExperts (and other expert add-ons) can register additional library paths globally. When MSBuild runs from a CI runner without the GExperts library installed, the global path disappears and the build breaks with `F1026 File not found`. Two ways out:

- Move the GExperts-only path into the `.dproj` `<DCC_UnitSearchPath>` so it ships in source control.
- Pass the path explicitly to `dcc64` via `-U` from the build script.

Never rely on a path that lives only in the IDE registry. CI does not have it.

## Quoting paths

`dcc64 -U\src\mormot 2\src\core` parses as two arguments. Always quote:

```
dcc64.exe -U"\src\mormot 2\src\core" -U"\src\mormot 2\src\orm" myserver.dpr
```

PowerShell quoting needs the backtick form (`-U`"$path`"`) because `&`-style invocation of an external `.exe` parses tokens before quotes are stripped. `scripts/delphi-build.ps1` uses `"-U`"$_`""` which compiles to the literal `-U"<path>"` once PowerShell escapes its own backticks.

## Configuration files

`dcc32` reads `dcc32.cfg` next to the binary; `dcc64` reads `dcc64.cfg`. Each line is a flag (without the leading dash on Delphi versions earlier than XE; with the leading dash on XE+). The IDE writes these from `Tools | Environment | Library`. CI runners typically do not have these files, which is why bare-runner builds need `rsvars.bat` first or a checked-in `dcc64.cfg` shipped with the project.
