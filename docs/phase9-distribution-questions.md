# Phase 9 - Distribution decisions

These questions are open at the end of Plan 4 (1.0.0-rc.1). They are not blockers for using the plugin locally; they are blockers for publishing it.

## 1. Hosting

Where does this fork live publicly?

- **Option A:** new GitHub repo under your user (e.g. `<your-handle>/mormot2-superpowers`).
- **Option B:** new GitHub repo under a synopse-aligned org (requires approval).
- **Option C:** keep it private; share via direct clone instructions.

Implications:
- Public repo + MIT license + clear NOTICE = smallest friction.
- Private repo means no harness marketplace listings (Claude Code, Cursor, Copilot, Gemini all expect a public source).

## 2. Marketplace listings

Which harnesses get a marketplace listing?

- **Claude Code** - official marketplace requires Anthropic review.
- **Cursor** - supports plugin marketplace via `/add-plugin`.
- **OpenCode** - supports `obra/...` style references.
- **Codex CLI / Copilot CLI / Gemini CLI** - each has its own marketplace flow.

Recommendation: pick 1-2 to start. Claude Code + Cursor cover the common case.

## 3. Listing copy

Each marketplace needs a short description (often 150-250 chars). Recommended draft:

> "Pascal/Delphi+FPC variant of the Superpowers methodology, specialized for Synopse mORMot 2. Covers ORM, REST, SOA, networking, deployment, auth, and TSynTestCase TDD. Cross-platform."

## 4. Versioning channel

After 1.0.0-rc.1, the next versions are:
- `1.0.0-rc.2`, `1.0.0-rc.3`, ... for fixes.
- `1.0.0` for stable.
- `1.1.0` for additive changes.

Should we follow semver strictly, or use date-based releases (e.g. `2026.04.25`) like upstream sometimes does? Upstream uses semver; recommend matching.

## 5. Upstream pull cadence

Plan 1 added `upstream` remote pointing at `obra/superpowers`. How often do we pull upstream changes into the methodology layer?

- **Option A:** never (fork goes its own way).
- **Option B:** opportunistic (pull only when upstream fixes a real bug we'd otherwise hit).
- **Option C:** scheduled (e.g. monthly review).

Recommendation: B. The fork's value is the Pascal/mORMot 2 layer; the methodology layer is stable.

## 6. CI runner for Delphi

`build-delphi` is gated `if: false` in `.github/workflows/ci.yml` and requires a self-hosted Windows + Delphi 12 CE runner. Decisions:

- **Option A:** keep `if: false`, document that Delphi builds are unverified by CI.
- **Option B:** stand up a self-hosted runner (your machine, Hetzner, etc.).
- **Option C:** find a hosted Delphi-on-cloud option (Embarcadero offers some).

Until this is decided, treat any Delphi-specific change as manually-verified.

## 7. License of generated content

The mORMot 2 SAD docs (referenced via `MORMOT2_DOC_PATH`) are part of the mORMot 2 tri-license (MPL/LGPL/GPL). The plugin only references chapter file paths; it does not embed SAD prose. Confirm your usage stays within MIT compatibility:

- Quoting up to 5 lines per skill body for illustration: clearly fair use.
- Embedding a full SAD chapter into a skill: would conflict with MIT distribution. Don't do this.

## How to use this file

When you're ready to publish, walk through these questions, record decisions, then open a final follow-up issue/task to wire the answers (e.g. push to GitHub, submit Claude Code marketplace listing, set up self-hosted CI). At that point this file can be deleted or archived.
