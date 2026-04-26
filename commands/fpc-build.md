---
description: "Build a Pascal project with FPC or lazbuild, with mORMot 2 search paths injected."
---

Invoke the plugin's `scripts/fpc-build.sh` (resolve via `$CLAUDE_PLUGIN_ROOT`, not via a cwd-relative path) with the user's project file. The script:
- Resolves `MORMOT2_PATH` from `.claude/mormot2.config.json`.
- Picks `lazbuild` for `.lpi`, plain `fpc -Mobjfpc -Sci` otherwise.
- Emits a structured `BUILD_RESULT exit=<n> errors=<count> warnings=<count> first=<file:line:msg>` line.

## Argument forms

- `/fpc-build` - find the project file in cwd (`*.lpi`, then `*.dpr`/`*.lpr`).
- `/fpc-build <project>` - explicit project path.
- `/fpc-build --lpi <file.lpi>` - force lazbuild path.

## What you do

1. Resolve the project file (argument or autodiscover).
2. Run `bash "$CLAUDE_PLUGIN_ROOT/scripts/fpc-build.sh" --project <project>` (or `--lpi <file>`).
3. Read the trailing `BUILD_RESULT` line.
4. If `exit != 0` or `errors > 0`, surface the `first` field and the BUILD_RESULT verbatim.
5. If `exit = 0`, report success with the warnings count.

## Exit codes (from the script)

- 0 success
- 1 misuse / no project
- 2 MORMOT2_PATH unset/invalid
- 5 project file missing
- 6 fpc/lazbuild not on PATH
- 7 build failed (errors > 0)

If the user's machine doesn't have FPC, tell them to run `/delphi-build` instead or install Free Pascal.
