---
description: "Resolve a mORMot 2 SAD topic or chapter number and emit a chapter excerpt."
---

Look up a topic or chapter number in the mORMot 2 Software Architecture Design (SAD) docs and emit the first 200 lines (or `[limit]` lines if specified).

## Argument forms

- `/mormot2-doc <topic>` - resolve topic via `references/chapter-index.json` (e.g. "torm" -> Chapter 5).
- `/mormot2-doc <number>` - look up by chapter number (1-26).
- `/mormot2-doc <topic-or-number> <limit>` - cap the excerpt at `<limit>` lines.

## What you do

1. Run `bash "$CLAUDE_PLUGIN_ROOT/scripts/sad-lookup.sh" <args>` (or `pwsh -File "$CLAUDE_PLUGIN_ROOT/scripts/sad-lookup.ps1" <args>` on Windows). The plugin root is exported as `CLAUDE_PLUGIN_ROOT` by Claude Code; do NOT use a relative path like `scripts/sad-lookup.sh` because the slash command runs from the user's project cwd, not the plugin root.
2. The script resolves topic via the chapter index, validates the file exists at `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-NN.md`, and emits `Chapter NN - <path>` followed by the excerpt.
3. Quote the excerpt verbatim back to the user.

## Topics

The chapter-index lives at `references/chapter-index.json`. Common topics: `overview` (1), `architecture` (2), `core-units` (4), `torm` / `torm-model` (5), `orm-patterns` (6), `sqlite` (7), `mongodb` (9), `rest` / `json` (10), `interface-services` (16), `mvc` (18), `security` / `auth` (21), `ecc` (23), `ddd` (24), `testing` / `logging` (25).

## Exit codes (from the script)

- 0 success
- 1 misuse (no argument)
- 2 MORMOT2_DOC_PATH unset/invalid OR chapter-index file missing
- 3 chapter file missing under MORMOT2_DOC_PATH
- 4 unknown topic

## When MORMOT2_DOC_PATH is unset

Tell the user to run `/mormot2-init --mormot2-path <path-to-mORMot2>`. The session-start hook reads the resulting config on the next session.
