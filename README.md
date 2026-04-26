# mormot2-superpowers

A Claude Code plugin for the [Synopse mORMot 2](https://github.com/synopse/mORMot2) community.

mORMot 2 is a deep, opinionated framework: ORM, REST, SOA, async HTTP, WebSockets, JWT/ECC/AES, MongoDB, eight SQL providers, MVC, DDD, a full crypto suite, and 26 chapters of architecture docs (the SAD). It is also Pascal, which means your AI agent probably wants to write you `string` fields on `TOrm` classes, generate `WriteLn` "logging" instead of `TSynLog`, forget `RawUtf8` boundaries, and invent classes that do not exist.

This plugin teaches the agent how to actually use mORMot 2.

## What it does

- **Routes prompts to mORMot 2 idioms.** When you ask "add a TOrm class for users", the plugin loads a domain skill that knows about `published` properties, `RawUtf8` over `string`, `index N` for unique columns, `TOrmModel.Create([...])`, and which SAD chapter covers it. Same for REST/SOA, async HTTP/WebSockets/ACME, raw SQL providers, deployment topology (static libs, services/daemons, reverse proxies), JWT/ECC/AES, build flags, and TSynLog/FastMM4 debugging.
- **Knows your SAD docs.** `/mormot2-doc <topic>` resolves topic names ("torm", "rest", "soa", "ecc", "ddd", "logging", ...) or chapter numbers to local SAD chapter excerpts. No more "I think this is in chapter 16 somewhere".
- **Builds with the right flags.** `/delphi-build <project>` and `/fpc-build <project>` invoke `dcc32`/`dcc64`/`msbuild` or `fpc`/`lazbuild` with mORMot 2 search paths injected automatically. Both emit a structured `BUILD_RESULT exit=N errors=N warnings=N first=...` line so the agent can act on failures without parsing colorized terminal output.
- **Reviews like a mORMot 2 reviewer would.** The Pascal-aware `code-reviewer` agent checks RawUtf8 boundaries, interface refcounts, try-finally completeness, ORM access patterns, threading on `TSqlDBConnection`, and whether your build artefact ships `.map` or DWARF symbols.
- **Tests via TSynTestCase, period.** `/mormot2-test` runs `mormot.core.test.TSynTestCase` suites. DUnitX, FPCUnit, and TestInsight are intentionally not supported. If you are coming from one of those, the plugin will say so.

## Quick start

### 1. Prerequisites

- A clone of mORMot 2 somewhere on disk: `git clone https://github.com/synopse/mORMot2`.
- One of: Delphi (RAD Studio), Free Pascal Compiler 3.2+, or Lazarus.
- Bash on PATH (Git Bash on Windows is fine).
- Node.js on PATH (used by hooks and scripts; almost certainly already installed if you run Claude Code).

### 2. Install the plugin

```
/plugin marketplace add C:/path/to/mormot2-superpowers
/plugin install mormot2-superpowers@mormot2-superpowers-dev
/reload-plugins
```

### 3. Tell it where mORMot 2 lives

In your project directory:

```
/mormot2-superpowers:mormot2-init --mormot2-path C:/path/to/mORMot2
```

This writes `.claude/mormot2.config.json` with your `mormot2_path` and `mormot2_doc_path`. Restart Claude Code so the session-start hook picks it up.

### 4. Try it

```
/mormot2-superpowers:mormot2-doc torm
```

Should emit `Chapter 05 - <path>` followed by an excerpt covering `TOrm`, primary keys, field attributes, and supported types.

Now ask Claude something Pascal-flavoured:

```
Add a TOrm class for a User with email and role fields
```

The agent loads `mormot2-superpowers:mormot2-orm`, generates a `TOrm` descendant with `RawUtf8` properties, the right `index`/`stored AS_UNIQUE` attributes, and points you at how to register it on a `TOrmModel`.

## What ships

### Domain skills (10)

| Skill | Covers |
|---|---|
| `mormot2-core` | RawUtf8, RawByteString, TSynLocker, TDocVariant, `mormot.defines.inc`, unit dependency order, JSON, RTTI customization. |
| `mormot2-orm` | TOrm, TOrmModel, virtual tables, field attributes, batch operations. |
| `mormot2-rest-soa` | TRestServerDB / TRestServerFullMemory, method-based services, IInvokable interface services, sessions. |
| `mormot2-net` | useHttpAsync / useBidirAsync / useHttpApi, async WebSockets (TWebSocketAsyncServerRest), OpenAPI import, TLS via TAcmeLetsEncryptServer, mormot.net.tunnel. |
| `mormot2-db` | TSqlDBConnectionProperties (SQLite / PostgreSQL / Oracle / MSSQL OleDB / MariaDB / Firebird / ZEOS / ODBC), thread-safe pooling, TMongoClient, BSON. |
| `mormot2-deploy` | Static libs (SQLite/OpenSSL/Zstd via mormot.defines.inc), TServiceController (Windows service), TSynDaemon and TSynAngelize (systemd / launchd / supervisor), nginx / HAProxy / IIS reverse proxies. |
| `mormot2-auth-security` | TJwtAbstract / TJwtEs256 / TJwtCrypt, TEccCertificate / TEcdheProtocol, TAesGcm, TSynSigner, modular-crypt password hashes (mcfBCryptSha256, mcfSCrypt). |
| `delphi-build` | dcc32/dcc64 flags, .dproj search paths, MSBuild targets, conditional defines for build configurations. |
| `fpc-build` | -Mobjfpc / -Sci modes, -Fu / -Fi search paths, .lpi files, lazbuild, cross-compilation, FPC_X64MM. |
| `pascal-debugging-logging` | TSynLog setup, FastMM4 leak reports, .map / DWARF stack traces, ISynLog tracing. |

Each domain skill ships a sharp scope, a "Do NOT use for ..." clause, three to four reference cheatsheets, and a trigger eval to keep the routing honest.

### Slash commands (5)

- `/mormot2-init` — scaffold `.claude/mormot2.config.json` for the current project.
- `/mormot2-doc <topic|chapter> [limit]` — resolve a SAD chapter and emit an excerpt.
- `/delphi-build [project]` — Delphi build with mORMot 2 search paths injected, structured BUILD_RESULT output.
- `/fpc-build [project]` — FPC / lazbuild equivalent.
- `/mormot2-test` — build and run the project's TSynTestCase suite.

### Process layer

The plugin also ships seven of Superpowers' generic process skills with Pascal/mORMot 2 addenda that activate only when the session-start hook detects a Pascal project (`*.dpr`, `*.dproj`, `*.lpi`, `*.lpr`, `*.pas` in cwd):

- `test-driven-development` — TSynTestCase RED/GREEN cycle.
- `systematic-debugging` — TSynLog, FastMM4, EAccessViolation guidance.
- `verification-before-completion` — `BUILD_RESULT exit=0` + TSynTestCase pass + symbols-deployed gates.
- `writing-plans` — Pascal file paths, unit dependency check, defines toggles.
- `using-git-worktrees` — `MORMOT2_PATH` propagation, do-not-clone-mORMot-per-worktree.
- `requesting-code-review` — wires up the Pascal-aware code-reviewer agent.
- `finishing-a-development-branch` — dual-compiler build gate when both `.dproj` and `.lpi` exist.

## Configuration

`.claude/mormot2.config.json` (per-project):

```json
{
  "mormot2_path": "C:/path/to/mORMot2",
  "mormot2_doc_path": "C:/path/to/mORMot2/docs",
  "compiler": "auto"
}
```

`compiler` is `auto` (pick by file extension), `delphi`, or `fpc`. If your project ships both `.dproj` and `.lpi`, set this to a specific compiler to skip the other.

The session-start hook reads this file on every session and exports `MORMOT2_PATH`, `MORMOT2_DOC_PATH`, and `PASCAL_PROJECT=1` for downstream scripts. Scripts also read the file directly so they work from `Bash` tool invocations regardless of env-var propagation.

## Cross-platform notes

- **Delphi-only scripts** (`delphi-build.ps1`) live as `.ps1` only. The `dcc*` toolchain is Windows-only, so a `.sh` sibling would be a lie.
- **FPC scripts** (`fpc-build.sh`) live as `.sh` only and run on Windows (Git Bash), Linux, and macOS. FPC is cross-platform; the bash script is the canonical wrapper.
- **Other scripts** (`sad-lookup`, `mormot2-init`) ship both `.sh` and `.ps1` siblings so they work in either shell.
- The plugin runs on Windows, Linux, macOS. Hooks fall back gracefully when not run by the harness.

## Status

`1.0.0-rc.1`. Feature-complete against the design. 16 structural invariants, 25 bats tests, 21 Pester tests, 59 skill-trigger evals all green.

Known limitations:
- `/mormot2-init --scaffold` is a stub (writes config, does not yet generate a project skeleton). Coming in a later release.
- The CI Delphi job is gated `if: false` until a self-hosted Windows + Delphi runner is registered. FPC builds run on hosted Linux + macOS runners.
- Real subagent dispatch in `tests/evals/run-evals.sh` is schema-validation only for now; full per-prompt evals are a follow-up.

## Contributing

Two layers, two contribution styles:

- **Methodology layer** (the seven generic Tier 1 skills, the planning/brainstorming/TDD process). Most of this is upstream Superpowers. If you find a bug there, prefer pulling the fix from `upstream/main` over patching here. Upstream-relevant patches go to obra/superpowers, not this repo.
- **Domain layer** (`mormot2-*`, build scripts, `/mormot2-*` commands, the Pascal-aware `code-reviewer`). This is the fork's own code. Bugfixes, more SAD chapter coverage, more idioms, better trigger evals — open issues / PRs here.

Local dev loop:

```bash
tests/run-quick.sh           # 16 invariants + 25 bats tests, < 60s
pwsh -File tests/run-quick.ps1   # 16 invariants + 21 Pester tests
```

Domain skills must keep `tests/invariants.sh` green and ship at least three positive + two negative trigger evals in `eval.md`. PR template lives in `.github/PULL_REQUEST_TEMPLATE.md` (inherited from upstream and being trimmed for this fork).

## License

MIT. See `LICENSE`. mORMot 2 itself is tri-licensed under MPL 1.1 / GPL 2.0 / LGPL 2.1; this plugin only references mORMot 2 by file path, never embeds its source or docs.

---

This plugin is a fork of [obra/superpowers](https://github.com/obra/superpowers) v5.0.7 by Jesse Vincent and Prime Radiant. The upstream README has the full methodology pitch and original install matrix; see the upstream repo for that. The Synopse mORMot 2 framework is the work of Arnaud Bouchez and contributors. Thanks to both communities.
