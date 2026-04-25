# `.claude/mormot2.config.json` schema

Per-project configuration for mormot2-superpowers. Lives in the user's
project at `.claude/mormot2.config.json`. Created by `/mormot2-init` or
copied from `mormot2.config.example.json` at the plugin root.

## Fields

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `mormot2_path` | string | yes | — | Absolute path to the mORMot 2 source tree (the directory containing `src/` and `docs/`). Used by build scripts as the search-path root. |
| `mormot2_doc_path` | string | no | `${mormot2_path}/docs` | Absolute path to the SAD documentation tree. Used by `/mormot2-doc` and the `sad-lookup` script. |
| `compiler` | string | no | `"auto"` | One of `"auto"`, `"delphi"`, `"fpc"`. When `"auto"`, build scripts pick by file extension (`.dproj` → delphi, `.lpi` → fpc). |

## Forbidden fields

`test_framework` and `test_framework_pin` are intentionally absent.
mormot2-superpowers supports `TSynTestCase` only; see design spec §6.

## Loading

The session-start hook reads this file and exports `MORMOT2_PATH` and
`MORMOT2_DOC_PATH` to subsequent script invocations. If the file is
absent or malformed, the hook is a no-op and skills/scripts emit a
single-line "run /mormot2-init" hint when invoked.
