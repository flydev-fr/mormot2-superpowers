# Conditional Defines (mormot.defines.inc)

Every mORMot unit starts with `{$I ..\mormot.defines.inc}`. That include file resolves a small set of project-wide toggles. Set them in **project options** (FPC `-d`, Delphi project conditional defines), never in unit source.

## Toggle reference

| Define           | Compiler   | Default       | Controls                                                        | When to set                                               | When to unset                                          |
|------------------|------------|---------------|-----------------------------------------------------------------|-----------------------------------------------------------|--------------------------------------------------------|
| `PUREMORMOT2`    | Both       | unset         | Hides mORMot 1.18 compatibility aliases and deprecated names    | New projects; want compile-time error on legacy symbols   | Migrating from mORMot 1; need transitional aliases     |
| `FPC_X64MM`      | FPC x64    | unset         | Replaces the FPC heap with `mormot.core.fpcx64mm`               | High-throughput servers on Linux/Windows x64              | Embedded/small targets; debugging an MM bug            |
| `FPCMM_BOOST`    | FPC x64    | unset         | Multi-threaded boost mode for `FPC_X64MM` (more arenas)         | Many threads, allocation-heavy workload                   | Single-threaded apps; tight memory budget              |
| `FPCMM_SERVER`  | FPC x64    | unset         | Server-tuned mode for `FPC_X64MM` (larger arenas, less trim)    | Long-lived server processes with steady-state allocation  | Short-lived CLIs                                       |
| `NEWRTTINOTUSED` | Delphi 2010+ | unset       | Excludes Delphi 2010+ enhanced RTTI from emitted binaries       | Want smallest EXE, do not need Delphi-style RTTI scanning | Code uses `Rtti.GetType` extensively on plain classes  |
| `NOPATCHVMT`     | Both       | unset         | Disables runtime VMT patches mORMot applies for speed           | Anti-cheat / signed-binary scenarios that scan VMT        | Default; performance matters                           |
| `NOPATCHRTL`     | Both       | unset         | Disables RTL function patches (e.g. faster `Move`, `FillChar`)  | Diagnosing crashes that look like RTL replacements        | Default; performance matters                           |

## Memory manager combinations

`FPCMM_BOOST` and `FPCMM_SERVER` are mutually exclusive. Both require `FPC_X64MM` to be active. Picking one without the other has no effect.

| Goal                           | Set                                  |
|--------------------------------|--------------------------------------|
| Default fast x64 MM            | `FPC_X64MM`                          |
| Many-threaded x64 server       | `FPC_X64MM` + `FPCMM_BOOST`          |
| Long-running x64 daemon        | `FPC_X64MM` + `FPCMM_SERVER`         |
| Stay on default FPC heap       | (no defines)                         |

## How to set them

### FPC

```bash
fpc -dFPC_X64MM -dFPCMM_SERVER -dPUREMORMOT2 myserver.dpr
```

### Delphi

Project Options -> Building -> Delphi Compiler -> Conditional defines:
`PUREMORMOT2;NEWRTTINOTUSED`

### Per-program override

You can set them in the `.dpr` BEFORE the first `uses` clause, but the convention is project-level. Setting them in unit source is wrong because most units have already been compiled by the time the unit is reached.

## Verifying

After a build, search the produced binary or the `.fpc.cfg` / `.dproj` for the active define names. A mismatch between project-level and IDE-level defines is a frequent source of "works on my machine" bugs.
