---
description: "Build a Delphi project (.dpr or .dproj) with mORMot 2 search paths injected."
---

Invoke `scripts/delphi-build.ps1` with the user's project file. The script:
- Resolves `MORMOT2_PATH` from `.claude/mormot2.config.json`.
- Picks dcc32/dcc64/msbuild based on file extension (`.dproj` -> msbuild; `.dpr` -> dcc64).
- Emits a structured `BUILD_RESULT exit=<n> errors=<count> warnings=<count> first=<file:line:msg>` line.

## Argument forms

- `/delphi-build` - find the project file in cwd (`*.dproj`, then `*.dpr`).
- `/delphi-build <project>` - explicit project path.
- `/delphi-build <project> --compiler dcc32|dcc64|msbuild|auto` - override compiler.

## What you do

1. Resolve the project file (argument or autodiscover).
2. Run `pwsh -File scripts/delphi-build.ps1 -Project <project> [-Compiler <comp>]`.
3. Read the trailing `BUILD_RESULT` line.
4. If `exit != 0` or `errors > 0`, surface the `first` field and the BUILD_RESULT verbatim.
5. If `exit = 0`, report success with the warnings count.

## Exit codes (from the script)

- 0 success
- 1 misuse
- 2 MORMOT2_PATH unset/invalid
- 5 project file missing
- 6 no Delphi compiler on PATH (Delphi not installed)
- 7 build failed (errors > 0)

If the user's machine doesn't have Delphi (`dcc64.exe` missing), tell them to run `/fpc-build` instead or install RAD Studio.
