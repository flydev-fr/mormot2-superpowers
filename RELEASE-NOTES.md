# mormot2-superpowers Release Notes

## 1.0.0-rc.1 (2026-04-25)

First release candidate. The plugin is feature-complete for the design spec at `docs/plans/2026-04-25-mormot2-superpowers-design.md` (Phases 0-7). Phase 8 distribution decisions are open and tracked at `docs/phase9-distribution-questions.md`.

### Identity

This is a fork of [Superpowers](https://github.com/obra/superpowers) v5.0.7 by Jesse Vincent / Prime Radiant, specialized for Pascal/Delphi+FPC development against the [Synopse mORMot 2](https://github.com/synopse/mORMot2) framework. The upstream methodology layer is preserved. The Pascal/mORMot 2 layer is original work added in this fork. MIT-licensed throughout.

### What's inside

- 14 generic process skills (upstream, lightly augmented).
- 7 Tier 1 skills with `## Pascal / mORMot2 Addendum` sections that activate when the session-start hook detects a Pascal project.
- 10 mORMot 2 domain skills (`mormot2-core`, `mormot2-orm`, `mormot2-rest-soa`, `mormot2-net`, `mormot2-db`, `mormot2-deploy`, `mormot2-auth-security`, `delphi-build`, `fpc-build`, `pascal-debugging-logging`) with router-style sharp scopes and trigger evals.
- 8 commands (3 upstream + `/mormot2-init`, `/delphi-build`, `/fpc-build`, `/mormot2-test`, `/mormot2-doc`).
- 1 Pascal-aware `code-reviewer` agent.
- 4 cross-platform scripts (`sad-lookup`, `delphi-build`, `fpc-build`, `mormot2-init`) plus the `ci-fixture-build` CI helper, all with bats and/or Pester coverage.
- Per-project `.claude/mormot2.config.json` schema; session-start hook loads it and exports `MORMOT2_PATH`, `MORMOT2_DOC_PATH`, `PASCAL_PROJECT`.
- 16 structural invariants (`tests/invariants.sh`).
- 4 self-test fixtures (`greenfield-delphi`, `greenfield-fpc`, `greenfield-dual`, `brownfield-no-tests`).
- GitHub Actions CI matrix (8 jobs; Delphi build is advisory and self-hosted-only).

### Opinionated decisions

- **TSynTestCase only.** `/mormot2-test` runs `mormot.core.test.TSynTestCase` exclusively. DUnitX, FPCUnit, TestInsight are not supported. See design spec section 6.
- **No SAD chapter embedding.** The plugin references chapters via `$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-NN.md`; the user supplies the path via `mormot2.config.json`.
- **Fork is a separate git repo.** The original `superpowers-main` directory is preserved untouched; this fork is a sibling directory with its own history.

### Harness portability

Skills are plain markdown. The `code-reviewer` agent uses `model: inherit`. Commands work on Claude Code, Codex CLI, Cursor, OpenCode, Copilot CLI, and Gemini CLI. Hooks degrade gracefully when not run (skills check config lazily on first invocation).

### Known limitations

- The `/mormot2-init --scaffold` flag is a stub returning exit 1; full project-skeleton scaffolding is deferred to a later release.
- `build-delphi` CI job requires a self-hosted Windows + Delphi 12 CE runner and is gated `if: false` until one is registered.
- Real subagent dispatch in `tests/evals/run-evals.sh` is not yet wired; the runner currently performs schema validation only. Wiring full per-prompt evals is a follow-up.
- The plugin assumes `node` is on PATH (used by hook config parsing and several scripts).
- The inherited `scripts/bump-version.sh` requires `jq`; on hosts without `jq`, use the inline node helper documented in the v1.0.0-rc.1 commit.

### Migration

This is a fresh fork. There is no migration path from the upstream `obra/superpowers` plugin. Install side-by-side or replace upstream depending on your project's needs.

### Credits

- Upstream Superpowers methodology: Jesse Vincent and Prime Radiant.
- Synopse mORMot 2 framework: Arnaud Bouchez and contributors.
- This fork: built collaboratively, MIT-licensed.
