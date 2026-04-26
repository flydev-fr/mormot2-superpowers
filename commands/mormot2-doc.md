---
description: "Resolve a mORMot 2 SAD topic or chapter number and emit a chapter excerpt."
---

Look up a topic or chapter number in the mORMot 2 Software Architecture Design (SAD) docs and emit the first 200 lines (or `[limit]` lines if specified).

## Argument forms

- `/mormot2-doc <topic>` - resolve topic via `references/chapter-index.json` (e.g. "torm" -> Chapter 5).
- `/mormot2-doc <number>` - look up by chapter number (1-26).
- `/mormot2-doc <topic-or-number> <limit>` - cap the excerpt at `<limit>` lines.

## What you do

1. Resolve the script path. The plugin scripts live inside the installed plugin directory, NOT the user's cwd. Try in this order:
   1. Use `$CLAUDE_PLUGIN_ROOT` if it expands to a non-empty path inside the bash subshell.
   2. If `$CLAUDE_PLUGIN_ROOT` is empty (some Claude Code builds do not propagate it to slash-command Bash invocations), glob for the script under the user's plugin cache: `~/.claude/plugins/cache/mormot2-superpowers-dev/mormot2-superpowers/*/scripts/sad-lookup.sh` (latest version wins). On Windows this resolves to `C:/Users/<user>/.claude/plugins/cache/mormot2-superpowers-dev/mormot2-superpowers/<version>/scripts/sad-lookup.sh`.
2. Invoke `bash "<resolved-path>/sad-lookup.sh" <args>` (or `pwsh -File "<resolved-path>/sad-lookup.ps1" <args>` on Windows-native).
3. The script reads `$MORMOT2_DOC_PATH` (set by the session-start hook from `.claude/mormot2.config.json`), validates the chapter file exists, and emits `Chapter NN - <path>` followed by the excerpt.
4. Quote the excerpt verbatim back to the user.

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
