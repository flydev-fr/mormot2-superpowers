---
description: "Scaffold .claude/mormot2.config.json for a Pascal/mORMot 2 project."
---

Run the mormot2-init scaffolder. Defaults: read `--mormot2-path` from arguments, infer `--mormot2-doc-path` as `<mormot2-path>/docs`, set `compiler: auto`.

If running on Windows, prefer `scripts/mormot2-init.ps1`. On Linux/macOS or under Git Bash, use `scripts/mormot2-init.sh`.

## Argument forms

- `--mormot2-path <path>` (required) - absolute path to the mORMot 2 source tree.
- `--mormot2-doc-path <path>` (optional) - absolute path to SAD docs. Defaults to `<mormot2-path>/docs`.
- `--compiler auto|delphi|fpc` (optional) - default `auto`.
- `--force` - overwrite an existing `.claude/mormot2.config.json`.
- `--scaffold` - not yet implemented; Plan 4 ships project skeletons.

## What happens

1. Check the mORMot 2 path exists.
2. Refuse if `.claude/mormot2.config.json` already exists (unless `--force`).
3. Write the config file.
4. Print the path of the written file.

If your prompt was just "/mormot2-init" with no arguments, ask the user for the absolute path to their mORMot 2 clone. Then run the scaffolder.
