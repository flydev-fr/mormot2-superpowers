# mormot2-superpowers — Contributor Guidelines

## Scope

This is a fork of the upstream Superpowers plugin, v5.0.7, specialized for Pascal/Delphi+FPC development against the [Synopse mORMot 2](https://github.com/synopse/mORMot2) framework. The upstream methodology layer is preserved; the Pascal/mORMot 2 domain layer is added on top.

## Process for changes

- Process and methodology skills (`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, etc.) come from upstream. Prefer pulling fixes from the `upstream` remote over rewriting them. Submit upstream-relevant patches to the upstream project, not here.
- Pascal/mORMot 2 domain skills (`mormot2-*`, build scripts, `/mormot2-*` commands, the Pascal-aware code-reviewer agent) live here. Domain skill changes must keep the structural invariants in `tests/invariants.sh` green and must not regress the trigger-eval threshold.
- The fork remains MIT-licensed.

## Tests

Run `tests/run-quick.sh` (or `.ps1`) before opening a change. CI runs the full matrix described in `docs/plans/2026-04-25-mormot2-superpowers-design.md` §9.4.

## Test framework

mORMot 2 native: `TSynTestCase` only (`mormot.core.test.pas`). DUnitX, FPCUnit, and TestInsight are not supported by `/mormot2-test`. This is a deliberate, opinionated choice; see the design spec §6.

## Configuration

Per-project config is `.claude/mormot2.config.json`. The plugin reads two paths from it:
- `mormot2_path` — where the mORMot 2 source tree lives (used for compiler search paths)
- `mormot2_doc_path` — where the SAD chapter markdown files live (used by `/mormot2-doc`)

Run `/mormot2-init` to scaffold this file. A sample is in `mormot2.config.example.json` at the plugin root.
