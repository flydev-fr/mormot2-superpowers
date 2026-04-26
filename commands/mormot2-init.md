---
description: "Scaffold .claude/mormot2.config.json for a Pascal/mORMot 2 project."
---

Run the mormot2-init scaffolder from the plugin root. Defaults: read `--mormot2-path` from arguments, infer `--mormot2-doc-path` as `<mormot2-path>/docs`, set `compiler: auto`. The scaffolder writes `.claude/mormot2.config.json` into the user's CURRENT working directory (not the plugin root).

The script lives inside the plugin install dir, NOT the user's cwd. Resolve it in this order:
1. `$CLAUDE_PLUGIN_ROOT/scripts/mormot2-init.{sh,ps1}` if `$CLAUDE_PLUGIN_ROOT` is non-empty in the subshell.
2. Otherwise glob `~/.claude/plugins/cache/mormot2-superpowers-dev/mormot2-superpowers/*/scripts/mormot2-init.{sh,ps1}` (latest version wins).

Then invoke:
- On Windows: `pwsh -File "<resolved-path>" <args>`
- On Linux/macOS or under Git Bash: `bash "<resolved-path>" <args>`

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
