# mormot2-superpowers — Design Spec

**Date:** 2026-04-25
**Status:** Draft (awaiting user review)
**Authors:** Brainstorm session (user + Claude Opus 4.7 + Codex GPT-5.5 cross-check)

---

## 1. Purpose

Fork the `superpowers` Claude Code plugin (https://github.com/obra/superpowers, v5.0.7) into a Pascal/Delphi+FPC variant called **`mormot2-superpowers`**, specialized for software development against the Synopse mORMot 2 framework (https://github.com/synopse/mORMot2).

The fork preserves the original plugin's process-oriented methodology (TDD, brainstorming, planning, subagent-driven development, code review) and adds a layer of mORMot 2 domain expertise (ORM, REST/SOA, networking, database, deployment, security) plus Pascal-specific build, test, and debugging tooling.

## 2. Goals

- Make a Pascal/mORMot 2 developer using a Claude Code (or compatible) harness as productive as a Python/Node developer using upstream superpowers.
- Encode mORMot 2 idioms and pitfalls so agents do not have to rediscover them per session (RawUtf8 vs string, RTTI patterns, conditional defines, unit dependency order, etc.).
- Provide first-class build and test integration for both Delphi (dcc32/dcc64, MSBuild) and FPC/Lazarus (fpc, lazbuild).
- Stay portable across the harnesses upstream supports: Claude Code, Codex CLI, Cursor, OpenCode, Copilot CLI, Gemini CLI.

## 3. Non-goals

- Not a replacement for upstream superpowers in non-Pascal projects.
- Does not test or modify mORMot 2 itself; mORMot 2 is treated as a read-only library dependency.
- Does not embed full SAD chapters (26 chapters, large) into the plugin; references the user's local mORMot 2 docs path.
- Does not support test frameworks other than `TSynTestCase` (intentional opinionated choice; see §6).

## 4. Architecture

Three tiers, layered:

```
Tier 1 — Generic process skills (14, lightly augmented)
   brainstorming, writing-plans, executing-plans, test-driven-development,
   systematic-debugging, requesting-code-review, receiving-code-review,
   subagent-driven-development, dispatching-parallel-agents, using-git-worktrees,
   finishing-a-development-branch, verification-before-completion,
   writing-skills, using-superpowers

   Each gets a "## Pascal / mORMot2 Addendum" section appended.
   Addenda only fire when a Pascal project is detected (*.dpr / *.lpi / *.pas in tree).

Tier 2 — mORMot 2 domain skills (10, NEW, router-style)
   mormot2-core           RawUtf8, RTTI, JSON, mormot.defines.inc, unit hierarchy
   mormot2-orm            TOrm, TOrmModel, virtual tables, RTTI mapping
   mormot2-rest-soa       REST endpoints + interface-based services (merged)
   mormot2-net            async HTTP, WebSockets, OpenAPI, TLS/ACME
   mormot2-db             SQL/NoSQL providers, thread-safe connections, BSON
   mormot2-deploy         daemons, services, static libs (SQLite/OpenSSL/Zstd), reverse proxy
   mormot2-auth-security  sessions, JWT, ECC, AES-GCM, signing
   delphi-build           dcc32/dcc64, MSBuild, .dproj search paths
   fpc-build              fpc, lazbuild, .lpi
   pascal-debugging-logging   TSynLog, FastMM4 leaks, exception tracing

   Each domain skill has a sharp scope and an explicit "Do NOT use for" clause
   to avoid triggering collisions in a 24-skill catalogue.

Tier 3 — Tooling
   Commands (5): /mormot2-init  /delphi-build  /fpc-build  /mormot2-test  /mormot2-doc
   Agents (1):   code-reviewer (Pascal-aware, model: inherit)
   Scripts:      sad-lookup.{ps1,sh}  delphi-build.ps1  fpc-build.sh
   Hooks:        session-start (extended to load config + detect Pascal context)
   Config:       .claude/mormot2.config.json (per-project)
```

### 4.1 Triggering principle

- Process skills keep their original triggers; addenda are no-ops outside Pascal context.
- Domain skill descriptions lead with a sharp scope sentence and end with a "Do NOT use for: ..." line that names the sibling skill that owns the redirected concern.
- This addresses the codex-flagged risk that 24 skills in one catalogue would collide.

### 4.2 Portability

- Agents use `model: inherit` (no opus/haiku pinning) so they work on harnesses that don't expose model selection.
- Hooks are shell-script-based (`.sh` + `.ps1`) and degrade gracefully when the harness does not run them — domain skills check config lazily on first invocation.
- Skills are plain markdown; no Claude-only API calls.

## 5. Components

### 5.1 Tier 1 — Generic skill addenda

| Skill | Addendum content |
|---|---|
| test-driven-development | TSynTestCase RED/GREEN cycle. `TSynTestCase.Check`, `TestFailed`, `RegressionTests`. |
| systematic-debugging | TSynLog reading patterns. FastMM4 leak reports. `EAssertionFailed` traces. `with sllStackTrace`. |
| verification-before-completion | Run `dcc64`/`fpc` exit code 0. Run `TSynTestCase` suite. Confirm `.map` / DWARF generated. |
| writing-plans | Plan steps include Pascal file paths, unit dependency check, `mormot.defines.inc` toggles. |
| using-git-worktrees | Worktree includes `MORMOT2_PATH` env propagation; mORMot2 itself is shared, not cloned per-worktree. |
| requesting-code-review | Trigger Pascal-aware code-reviewer agent. Checklist: RawUtf8 vs string, interface refcount, try-finally, Free vs FreeAndNil. |
| finishing-a-development-branch | Build both compilers if both detected. Run mORMot2 regression suite if touched. |

The other 7 generic skills (brainstorming, executing-plans, subagent-driven-development, dispatching-parallel-agents, receiving-code-review, writing-skills, using-superpowers) get small or no addenda.

### 5.2 Tier 2 — Domain skill shape

Each `mormot2-<domain>/SKILL.md` follows this shape:

```yaml
---
name: mormot2-<domain>
description: <≤200 chars: sharp scope> Do NOT use for <neighbor>: use mormot2-<other>.
---

# mormot2-<domain>

## When to use
<concrete bullet triggers>

## Core idioms
<code skeletons, patterns, RawUtf8 boundaries>

## Common pitfalls
<thread-safety, lifetime, defines>

## See also
$MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-NN.md (chapter title)
references/<topic>-cheatsheet.md
```

`references/` per skill holds: chapter-index map (subset), idiom snippets ≤100 lines each, no full SAD chapters.

### 5.3 Tier 3 — Commands

| Command | Action |
|---|---|
| `/mormot2-init` | Scaffold project skeleton (.dpr + .lpi siblings, `mormot.uses.inc` reference, README, TSynTestCase test unit, `.claude/mormot2.config.json`). Supports `--brownfield` for existing repos: writes config without overwriting code; if non-TSynTestCase tests detected, emits migration guidance and refuses to scaffold tests until accepted. |
| `/delphi-build [target]` | Wraps `delphi-build.ps1`; auto-detects `.dproj`; uses `mormot2.config.json` paths. |
| `/fpc-build [target]` | Wraps `fpc-build.sh` / `lazbuild`; auto-detects `.lpi`. |
| `/mormot2-test` | Compiles and runs the project's TSynTestCase suite; emits structured pass/fail summary. Does not run other test frameworks. |
| `/mormot2-doc <topic\|chapter>` | Resolves `MORMOT2_DOC_PATH`, opens or excerpts SAD chapter via `sad-lookup` script. |

### 5.4 Tier 3 — Agent

`code-reviewer` (Pascal-aware): same role as upstream, checklist updated for RawUtf8/string/UnicodeString hazards, interface vs class refcounts, try-finally completeness, ORM access patterns, `Free` vs `FreeAndNil`, threading on `TSqlDBConnection`, mORMot2 serialization caveats. Model: `inherit`.

### 5.5 Tier 3 — Scripts

All scripts ship as both `.ps1` (Windows) and `.sh` (Unix). Required by an invariant test.

- `sad-lookup.{ps1,sh}` — chapter-index → file path → excerpt
- `delphi-build.ps1` — dcc32/dcc64 wrapper, MSBuild fallback for `.dproj`, mORMot2 search paths injected
- `fpc-build.sh` — fpc / lazbuild wrapper, mORMot2 `-Fu` / `-Fi` injected

Each build script emits a structured tail line:
```
BUILD_RESULT exit=<n> errors=<count> warnings=<count> first=<file:line:msg>
```
Skills and the code-reviewer agent grep this line.

### 5.6 Tier 3 — Config

`.claude/mormot2.config.json` (per-project, written by `/mormot2-init`):

```json
{
  "mormot2_path": "C:/Users/badb/Documents/Embarcadero/Studio/Libraries/mORMot2",
  "mormot2_doc_path": "C:/Users/badb/Documents/Embarcadero/Studio/Libraries/mORMot2/docs",
  "compiler": "auto"
}
```

Note: `test_framework` and `test_framework_pin` keys are intentionally absent — TSynTestCase is the only supported framework.

### 5.7 Hooks

`hooks/session-start` extended to:
1. Read `.claude/mormot2.config.json` if present, export `MORMOT2_PATH` and `MORMOT2_DOC_PATH`.
2. Scan cwd for `*.dpr | *.dproj | *.lpi | *.pas`; export `PASCAL_PROJECT=1` to gate Tier 1 addenda.
3. Emit one-line reminder if config missing and Pascal project detected: "run /mormot2-init".
4. Defensive: missing/malformed config does not abort the session.

## 6. Test framework decision (opinionated)

**Decision:** TSynTestCase only. No DUnitX / FPCUnit / TestInsight fallback.

**Rationale:** `mormot2-superpowers` is opinionated tooling for mORMot 2 native development. mORMot 2 ships its own test framework (`mormot.core.test.TSynTestCase`) that is tightly integrated with its logging, RTTI, and JSON serialization. Supporting multiple frameworks would dilute the addenda, complicate test-running scripts, and weaken the plugin's identity.

**Trade-off:** Brownfield Pascal shops on DUnitX/FPCUnit pay a migration cost. Mitigation: `/mormot2-init --brownfield` emits migration guidance, but does not block the user from continuing to use their existing harness outside `/mormot2-test`. Domain skills still teach idioms regardless of test framework.

## 7. Data flow

### 7.1 Plugin install / first run

```
User installs mormot2-superpowers
   → session-start hook fires
   → reads .claude/mormot2.config.json
       exists  → export $MORMOT2_PATH, $MORMOT2_DOC_PATH
       missing → reminder to run /mormot2-init
   → scans cwd for *.dpr | *.dproj | *.lpi | *.pas
       Pascal detected → export PASCAL_PROJECT=1
       none            → addenda dormant; only mormot2-doc lookup commands work
```

### 7.2 Greenfield feature flow

```
User: "build a TOrm-backed user service"
   → brainstorming  → writing-plans  → executing-plans (subagent per task)
   → during planning + execution, mormot2-orm + mormot2-rest-soa load on demand
   → TDD addendum injects TSynTestCase RED → impl → GREEN
   → /delphi-build OR /fpc-build (auto-detect)
   → /mormot2-test
   → requesting-code-review → code-reviewer agent (Pascal checklist)
   → finishing-a-development-branch
```

### 7.3 SAD doc resolution

```
Skill body: "See $MORMOT2_DOC_PATH/mORMot2-SAD-Chapter-NN.md for X"
   → agent reads env var
   → if missing, skill says "run /mormot2-doc N or set MORMOT2_DOC_PATH"
   → /mormot2-doc <topic> calls sad-lookup script:
        1. lookup topic in chapter-index.json
        2. resolve absolute path
        3. validate file exists
        4. emit excerpt (default 200 lines) or full path
```

### 7.4 Compiler detection

```
*.dproj exists           → delphi
*.lpi exists             → fpc
only *.dpr + *.pas       → ask user (or read config.compiler)
both *.dproj + *.lpi     → both; build both unless config pins one
```

### 7.5 Brownfield entry

```
User runs /mormot2-init --brownfield in existing Pascal repo
   → scan: existing test framework? mORMot2 already in uses?
   → write config.json
   → if non-TSynTestCase tests detected: emit migration guidance, do not
     scaffold tests until user accepts
   → never overwrite existing files; emit diff for user approval
```

## 8. Error handling and edge cases

| Failure | Behavior |
|---|---|
| `mormot2.config.json` missing | Hook one-line reminder. Domain skills still load. SAD lookup degrades to explicit instruction. No crash. |
| `MORMOT2_PATH` invalid | Build scripts fail fast: `MORMOT2_PATH=<path> not found. Edit .claude/mormot2.config.json`. Exit 2. |
| `MORMOT2_DOC_PATH` chapter missing | `sad-lookup` returns: index entry exists but file not found; suggest `git pull` in mORMot2 repo. |
| Config JSON malformed | Hook logs parse error, treats as missing. Session continues. |
| `F2613 Unit not found` (Delphi) | systematic-debugging addendum → check `mormot.uses.inc` + `.dproj` search paths. |
| `Fatal: Compilation aborted` (FPC) | Same path → `-Fu` / `-Fi`. |
| Linker error on static libs | mormot2-deploy skill → SQLite/OpenSSL/Zstd linkage chapter. |
| Existing non-TSynTestCase tests | Domain skill emits migration guidance; `/mormot2-test` only runs TSynTestCase suite. |
| Both `.dproj` + `.lpi` present, no pin | Build both. Test both. Skills warn: "Dual-target detected. Pin compiler in config to skip one." |
| User on Linux runs `/delphi-build` | Script detects no Delphi → exits with: "Delphi not available on this OS; use /fpc-build". |
| Delphi version mismatch | MSBuild error surfaced raw + hint to verify `$(BDS)` env or `.dproj` VersionInfo. |
| mORMot2 not installed | Banner at session start. Domain skills still teach idioms; only build/test pipeline fails. |
| Two worktrees building simultaneously | Both reference shared read-only `MORMOT2_PATH`. Safe. |

### 8.1 Harness portability degradations

| Harness | Behavior |
|---|---|
| Codex CLI | Skills load via `skill` tool. `/mormot2-doc` works as command. Agent replaced by inline prompt template. |
| Cursor | Hooks may not run; config read on first skill invocation instead. |
| Gemini CLI | `gemini-extension.json` lists skills. Agent: docs note "code-reviewer is a Claude Code optional layer". |
| OpenCode | INSTALL.md updated for new plugin name + config setup step. |
| Copilot CLI | Same as Gemini. |

Hook-dependent behavior MUST have a lazy fallback path triggered by skill invocation when the hook didn't run.

## 9. Plugin self-test

### 9.1 Layout

```
mormot2-superpowers/
└── tests/
    ├── fixtures/
    │   ├── greenfield-delphi/      sample .dpr + minimal mORMot2 use
    │   ├── greenfield-fpc/         sample .lpi
    │   ├── greenfield-dual/        both compilers
    │   └── brownfield-no-tests/    .pas files only, no test rig
    ├── skills/                     skill triggering evals (1 per skill)
    ├── scripts/                    unit tests for ps1/sh wrappers
    └── e2e/                        full flow scenarios
```

### 9.2 Test types

1. **Skill trigger evals** — markdown-driven prompts; expected_skill + forbidden_skills. Threshold ≥ 95% across 30 prompts per skill. Run via `superpowers:writing-skills` eval framework.
2. **Script unit tests** — Pester for `.ps1`, bats for `.sh`. Cover: missing env vars, BUILD_RESULT line shape, error parsing, sad-lookup chapter resolution.
3. **Fixture builds (real compile)** — CI matrix runs `/mormot2-init` → `/delphi-build` or `/fpc-build` → `/mormot2-test` against each fixture. Assert exit 0 + `errors=0`.
4. **End-to-end scenario** — single scripted run: spawn agent with feature request, assert pipeline (brainstorming → planning → TSynTestCase → build → review) executes, code-reviewer emits Pascal checklist findings, `/mormot2-doc` returns chapter excerpt.

### 9.3 Plugin invariants (`tests/invariants.sh`)

- All 24 skills have valid frontmatter (`name`, `description` ≤ 200 chars).
- Domain skills include explicit "Do NOT use for" clause.
- All `references/` pointers exist.
- No skill references absolute Windows paths (must use `$MORMOT2_PATH`).
- All scripts have both `.ps1` and `.sh` siblings.
- `chapter-index.json` references files that exist in a sample doc tree.

### 9.4 CI matrix

| Job | Runner | Compiler | Purpose |
|---|---|---|---|
| invariants | ubuntu-latest | none | structural checks |
| skill-evals | ubuntu-latest | none | trigger accuracy |
| script-units (ps1) | windows-latest | none | Pester |
| script-units (sh) | ubuntu-latest | none | bats |
| build-delphi | self-hosted Windows | Delphi 12 CE | greenfield + dual fixtures (hosted runners do not ship Delphi; self-hosted required) |
| build-fpc | ubuntu-latest | FPC 3.2 | greenfield-fpc fixture |
| build-fpc-mac | macos-latest | FPC 3.2 | macOS portability |
| e2e | self-hosted Windows | both | full scenario (advisory) |

### 9.5 Pre-merge gate

Branch cannot merge unless: invariants ✅, evals ≥95% ✅, script-units ✅, at least one build job ✅. e2e is advisory.

### 9.6 Local dev loop

`tests/run-quick.{sh,ps1}` runs invariants + script-units + skill-evals (skips real compiles). Target ~60s feedback.

## 10. Migration / fork plan

### Phase 0 — Preserve original (5 min)

```
git tag pre-mormot2-fork                                  (in superpowers-main)
git remote add upstream https://github.com/obra/superpowers.git  (if absent)
```

If superpowers-main is not a git repo: zip backup to sibling directory.

### Phase 1 — Bootstrap fork (10 min)

```
cp -r superpowers-main mormot2-superpowers
cd ../mormot2-superpowers
git init
git checkout -b main
git commit -am "fork: clone superpowers v5.0.7 baseline"
```

### Phase 2 — Identity rebrand (1-2 h)

- `package.json` → `name: "mormot2-superpowers"`, version `0.1.0`
- `gemini-extension.json` → name + description
- `README.md` rewrite
- `LICENSE` MIT preserved; `NOTICE` credits Jesse Vincent / obra/superpowers + Synopse / Arnaud Bouchez
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` strip obra-specific PR rules; add mORMot 2 contribution notes
- Resolve any `superpowers:` skill prefix collisions

**Checkpoint:** plugin loads as `mormot2-superpowers`; existing 14 skills still trigger as before.

### Phase 3 — Config + scripts (3-4 h)

- `.claude/mormot2.config.json` schema + sample
- `scripts/sad-lookup.{ps1,sh}` + `references/chapter-index.json`
- `scripts/delphi-build.ps1` + `scripts/fpc-build.sh`
- Extend `hooks/session-start`
- Add `tests/invariants.sh`

**Checkpoint:** scripts unit-tested green. Hook is no-op when config absent. Note: `/mormot2-init` (the config writer command) lands in Phase 6; until then, the schema is documented and a sample `mormot2.config.example.json` is provided for hand-copy.

### Phase 4 — Domain skills (12-20 h, parallelizable)

Order by dependency:
1. mormot2-core (foundational; others reference)
2. mormot2-orm
3. mormot2-rest-soa
4. mormot2-db
5. mormot2-net
6. mormot2-auth-security
7. mormot2-deploy
8. delphi-build
9. fpc-build
10. pascal-debugging-logging

Each: SKILL.md + `references/` + eval. Per-skill commit. Trigger eval ≥95% before merging next.

**Checkpoint:** 10 domain skills load, evals green, no triggering collisions with Tier 1.

### Phase 5 — Tier 1 addenda (2-3 h)

Append `## Pascal / mORMot2 Addendum` to the 7 affected generic skills. Other 7 untouched.

**Checkpoint:** re-run Tier 1 evals (must still pass). Pascal addenda only fire when fixture is Pascal.

### Phase 6 — Commands + agent (2-3 h)

- 5 commands (`/mormot2-init`, `/delphi-build`, `/fpc-build`, `/mormot2-test`, `/mormot2-doc`)
- Rewrite `agents/code-reviewer.md` checklist for Pascal

**Checkpoint:** each command end-to-end on greenfield fixture.

### Phase 7 — Fixtures + e2e (6-10 h)

Build the 4 fixtures and wire CI matrix.

**Checkpoint:** build-delphi + build-fpc green on hosted runners.

### Phase 8 — Distribution (1 h)

- Bump version to 1.0.0-rc.1
- `RELEASE-NOTES.md` makes clear: this is a fork, not Anthropic's superpowers
- Update `scripts/bump-version.sh` to point at new repo
- Hosting decision (GitHub user repo, marketplace listing) — out of scope for this design; flagged for Phase 9

**Checkpoint:** `1.0.0-rc.1` tagged. Manual smoke on Claude Code + one other harness.

### Rollback

Each phase is its own commit cluster with a tag. Phase failures revert via `git reset --hard <prev-checkpoint-tag>`. Original `superpowers-main` is untouched throughout.

### Effort estimate

| Phase | Effort |
|---|---|
| 0 | 5 min |
| 1 | 10 min |
| 2 | 1-2 h |
| 3 | 3-4 h |
| 4 | 12-20 h |
| 5 | 2-3 h |
| 6 | 2-3 h |
| 7 | 6-10 h |
| 8 | 1 h |
| **Total** | **~30-45 h** of agent work, parallelizable from Phase 4 onward |

## 11. Open questions for Phase 9

- Hosting / distribution channel for the fork (GitHub user repo, marketplace).
- Upstream-merge cadence: pull obra/superpowers improvements into Tier 1 generic skills, or freeze at v5.0.7?
- License metadata: confirm MIT compatibility with mORMot 2 SAD references (mORMot 2 is MPL/LGPL/GPL tri-license; the plugin is MIT and only references SAD chapter paths, not embeds content — should be safe, but confirm).

## 12. References

- Upstream plugin: https://github.com/obra/superpowers (v5.0.7)
- mORMot 2 framework: https://github.com/synopse/mORMot2
- mORMot 2 SAD docs (local): `C:\Users\badb\Documents\Embarcadero\Studio\Libraries\mORMot2\docs\` (26 chapters)
- This design was cross-checked against an independent review by GPT-5.5 (codex-assistant) on 2026-04-25.
