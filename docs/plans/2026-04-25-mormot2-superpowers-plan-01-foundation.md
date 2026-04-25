# mormot2-superpowers — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap a working `mormot2-superpowers` plugin shell — fork the upstream repo, rebrand identity, add the per-project config schema, helper scripts, extended hook, and structural test invariants. After this plan completes, the plugin loads cleanly in Claude Code (and reports as a no-op when no Pascal project is in cwd), but ships zero domain content yet.

**Architecture:** Phases 0-3 of the design spec. Output is a clean plugin skeleton: identity rebranded, config schema documented, cross-platform scripts in place (`sad-lookup`, `delphi-build`, `fpc-build`), session-start hook extended to load config and detect Pascal context, and an `invariants.sh` test that locks in the structural contract.

**Tech Stack:** Bash + PowerShell scripts, plain markdown skills, JSON config, Pester (PowerShell test framework), bats (bash test framework).

**Spec:** `docs/plans/2026-04-25-mormot2-superpowers-design.md`

**Scope of this plan:** Phases 0-3 only. Phases 4-8 (domain skills, addenda, commands, agent, fixtures, CI, distribution) belong to subsequent plans (Plan 2: Domain Skills, Plan 3: Integration, Plan 4: Validation/Release).

**Working directory convention:**
- Tasks 1-2 run from `C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/`.
- Tasks 3+ run from `C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers/`.

---

### Task 1: Preserve original + bootstrap fork directory

**Files:**
- Create: `C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers/` (cloned from `superpowers-main/`)
- Tag in: `C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/superpowers-main/`

- [ ] **Step 1: Verify original is a git repo and tag baseline**

```bash
cd "C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/superpowers-main"
git rev-parse --git-dir 2>/dev/null && echo "is-git" || echo "not-git"
```

If `is-git`:
```bash
git tag pre-mormot2-fork
```

If `not-git`:
```bash
cd ..
zip -r superpowers-main-backup-2026-04-25.zip superpowers-main -x "superpowers-main/.git/*"
```

Expected: tag exists OR zip backup created.

- [ ] **Step 2: Verify the source tree is clean (no uncommitted changes)**

If git:
```bash
cd "C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/superpowers-main"
git status --porcelain
```
Expected: empty output. If non-empty, STOP and ask the user whether to commit, stash, or proceed.

- [ ] **Step 3: Clone to sibling directory**

```bash
cd "C:/Users/badb/Documents/Embarcadero/Studio/Projets/Perso"
cp -r superpowers-main mormot2-superpowers
cd mormot2-superpowers
```

- [ ] **Step 4: Initialize the fork as a fresh git repo**

```bash
rm -rf .git
git init
git checkout -b main
git add -A
git commit -m "chore: clone superpowers v5.0.7 baseline as mormot2-superpowers fork"
```

Expected: a single commit on `main` containing the entire baseline.

- [ ] **Step 5: Add upstream remote for future pull-merges**

```bash
git remote add upstream https://github.com/obra/superpowers.git
git remote -v
```

Expected: `upstream` listed alongside no `origin`.

- [ ] **Step 6: Sanity-check the clone**

```bash
ls skills | wc -l
ls commands | wc -l
ls agents | wc -l
```

Expected: 14 skills, 3 commands, 1 agent.

- [ ] **Step 7: Commit**

(Already committed in Step 4. No additional commit here; the Git remote add does not need a commit.)

---

### Task 2: Rebrand package.json

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Read the current contents**

```bash
cat package.json
```

Expected current content:
```json
{
  "name": "superpowers",
  "version": "5.0.7",
  "type": "module",
  "main": ".opencode/plugins/superpowers.js"
}
```

- [ ] **Step 2: Replace with the new manifest**

Write `package.json`:
```json
{
  "name": "mormot2-superpowers",
  "version": "0.1.0",
  "type": "module",
  "main": ".opencode/plugins/superpowers.js",
  "description": "Pascal/Delphi+FPC variant of the Superpowers plugin, specialized for the Synopse mORMot 2 framework.",
  "license": "MIT",
  "fork": {
    "of": "obra/superpowers",
    "from_version": "5.0.7"
  }
}
```

- [ ] **Step 3: Validate JSON parses**

```bash
node -e "JSON.parse(require('fs').readFileSync('package.json','utf8'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add package.json
git commit -m "chore: rebrand package.json as mormot2-superpowers v0.1.0"
```

---

### Task 3: Rebrand gemini-extension.json

**Files:**
- Modify: `gemini-extension.json`

- [ ] **Step 1: Read current contents**

```bash
cat gemini-extension.json
```

- [ ] **Step 2: Update name and description**

Replace top-level `name` field with `"mormot2-superpowers"` and `description` with `"Pascal/Delphi+FPC variant of Superpowers, specialized for the Synopse mORMot 2 framework."` Leave all other fields unchanged.

If the file contains a `version` field, set it to `"0.1.0"`.

- [ ] **Step 3: Validate JSON parses**

```bash
node -e "JSON.parse(require('fs').readFileSync('gemini-extension.json','utf8'))" && echo OK
```

- [ ] **Step 4: Commit**

```bash
git add gemini-extension.json
git commit -m "chore: rebrand gemini-extension.json"
```

---

### Task 4: Rewrite README.md top section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the first heading and intro paragraphs**

Replace the existing content from the top of the file through the "Sponsorship" section with:

```markdown
# mormot2-superpowers

A Pascal/Delphi+FPC variant of [Superpowers](https://github.com/obra/superpowers) (Jesse Vincent / Prime Radiant), specialized for the [Synopse mORMot 2](https://github.com/synopse/mORMot2) framework.

This plugin keeps the upstream methodology layer (brainstorming, planning, TDD, subagent-driven development, code review) and adds:

- A mORMot 2 domain layer covering ORM, REST/SOA, networking, database, deployment, and security.
- Pascal-aware build skills for Delphi (dcc32/dcc64, MSBuild) and FPC/Lazarus (fpc, lazbuild).
- TSynTestCase-first test discipline (no DUnitX/FPCUnit fallback).
- A `/mormot2-doc` lookup that resolves chapters of the local mORMot 2 SAD documentation tree.

## Prerequisites

- A working mORMot 2 install (clone of https://github.com/synopse/mORMot2).
- Either Delphi (RAD Studio) or Free Pascal Compiler 3.2+ on PATH.
- Bash (Git Bash on Windows) for hook execution.

## Configuration

Each project that uses this plugin needs `.claude/mormot2.config.json`. Run `/mormot2-init` to scaffold one, or copy `mormot2.config.example.json` from the plugin root.

## Upstream credit

This plugin is a fork of `obra/superpowers` v5.0.7. The methodology and most of the process skills are upstream's work; see `NOTICE` for full attribution. Distributed under MIT, the same license as upstream.
```

Keep the rest of the original README (skill list, philosophy, etc.) untouched for now — those sections will be revised in later plans as content changes.

- [ ] **Step 2: Verify the file still renders sensibly**

```bash
head -60 README.md
```

Expected: new top section, then upstream content from "## The Basic Workflow" onward.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README top section for mormot2-superpowers"
```

---

### Task 5: Add NOTICE file

**Files:**
- Create: `NOTICE`

- [ ] **Step 1: Write NOTICE**

```
mormot2-superpowers
===================

This project is a fork of "Superpowers" by Jesse Vincent and Prime Radiant
(https://github.com/obra/superpowers), distributed under the MIT License.
The original project's process skills, hooks, and orchestration patterns
are retained largely unchanged and remain the work of the original
authors.

The mORMot 2 domain layer (skills under `skills/mormot2-*/`, build scripts,
the `/mormot2-*` slash commands, the Pascal-aware `code-reviewer` agent,
and the `mormot2.config.json` schema) is original work added in this fork
and is also distributed under the MIT License.

The Synopse mORMot 2 framework (https://github.com/synopse/mORMot2) by
Arnaud Bouchez is referenced by name and by file path only. No mORMot 2
source code or documentation is bundled in this plugin. mORMot 2 is
tri-licensed under MPL 1.1 / GPL 2.0 / LGPL 2.1 and remains the property
of its authors.
```

- [ ] **Step 2: Commit**

```bash
git add NOTICE
git commit -m "docs: add NOTICE for upstream and mORMot 2 attribution"
```

---

### Task 6: Strip obra-specific PR rules from contributor docs

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`

- [ ] **Step 1: Read current CLAUDE.md**

```bash
cat CLAUDE.md
```

- [ ] **Step 2: Replace the entire file with a fork-specific version**

Write `CLAUDE.md`:
```markdown
# mormot2-superpowers — Contributor Guidelines

## Scope

This is a fork of [obra/superpowers](https://github.com/obra/superpowers) v5.0.7, specialized for Pascal/Delphi+FPC development against the [Synopse mORMot 2](https://github.com/synopse/mORMot2) framework.

## Process for changes

- Process and methodology skills (`brainstorming`, `writing-plans`, `executing-plans`, `test-driven-development`, etc.) come from upstream. Prefer pulling fixes from `upstream/main` over rewriting them. Submit upstream-relevant patches to obra/superpowers, not here.
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
```

- [ ] **Step 3: Repeat for AGENTS.md and GEMINI.md**

Apply the same content to `AGENTS.md` and `GEMINI.md` (these files are harness-specific entry points but currently mirror CLAUDE.md). If a file diverges from CLAUDE.md in upstream — read it first and only replace the obra-specific PR rules section, keeping any harness-specific invocation guidance. The previous step's content is the floor.

- [ ] **Step 4: Verify no upstream PR-rule wording remains**

```bash
grep -E "94%|slop|obra/superpowers" CLAUDE.md AGENTS.md GEMINI.md
```

Expected: no matches (the obra-specific PR-quality rules and statistics should be gone). If matches appear, remove them.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AGENTS.md GEMINI.md
git commit -m "docs: replace upstream PR rules with fork-specific contributor guidelines"
```

---

### Task 7: Document the config schema and sample

**Files:**
- Create: `mormot2.config.example.json`
- Create: `docs/config-schema.md`

- [ ] **Step 1: Write the sample config**

`mormot2.config.example.json`:
```json
{
  "mormot2_path": "C:/Users/badb/Documents/Embarcadero/Studio/Libraries/mORMot2",
  "mormot2_doc_path": "C:/Users/badb/Documents/Embarcadero/Studio/Libraries/mORMot2/docs",
  "compiler": "auto"
}
```

- [ ] **Step 2: Write the schema doc**

`docs/config-schema.md`:
```markdown
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
```

- [ ] **Step 3: Validate the sample parses**

```bash
node -e "JSON.parse(require('fs').readFileSync('mormot2.config.example.json','utf8'))" && echo OK
```

- [ ] **Step 4: Commit**

```bash
git add mormot2.config.example.json docs/config-schema.md
git commit -m "docs: add mormot2.config.json schema and sample"
```

---

### Task 8: Write the chapter-index.json

**Files:**
- Create: `references/chapter-index.json`

- [ ] **Step 1: Write the topic-to-chapter mapping**

`references/chapter-index.json`:
```json
{
  "schema_version": 1,
  "source": "Synopse mORMot 2 Software Architecture Design (SAD) chapters 1-26",
  "filename_pattern": "mORMot2-SAD-Chapter-{NN}.md",
  "topics": {
    "overview": 1,
    "architecture": 2,
    "unit-structure": 3,
    "core-units": 4,
    "torm": 5,
    "torm-model": 5,
    "orm-patterns": 6,
    "sqlite": 7,
    "external-sql": 8,
    "mongodb": 9,
    "json": 10,
    "rest": 10,
    "client-server": 11,
    "orm-rest": 12,
    "orm-services": 13,
    "method-services": 14,
    "interfaces": 15,
    "soa": 16,
    "interface-services": 16,
    "cross-platform": 17,
    "mvc": 18,
    "web": 19,
    "hosting": 20,
    "security": 21,
    "auth": 21,
    "scripting": 22,
    "ecc": 23,
    "ddd": 24,
    "testing": 25,
    "logging": 25,
    "tsynlog": 25,
    "installation": 26,
    "compilation": 26
  },
  "chapter_titles": {
    "1": "Overview",
    "2": "Architecture",
    "3": "Unit Structure",
    "4": "Core Units",
    "5": "TOrm and TOrmModel",
    "6": "ORM Daily Patterns",
    "7": "SQLite3",
    "8": "External SQL",
    "9": "MongoDB",
    "10": "JSON / REST",
    "11": "Client-Server Architecture",
    "12": "ORM REST Operations",
    "13": "ORM Services",
    "14": "Method-based Services",
    "15": "Interfaces",
    "16": "Service-Oriented Architecture",
    "17": "Cross-Platform Clients",
    "18": "MVC Pattern",
    "19": "Web Applications",
    "20": "Hosting",
    "21": "Security",
    "22": "Scripting",
    "23": "ECC Encryption",
    "24": "Domain-Driven Design",
    "25": "Testing and Logging",
    "26": "Installation and Compilation"
  }
}
```

- [ ] **Step 2: Validate JSON parses**

```bash
node -e "JSON.parse(require('fs').readFileSync('references/chapter-index.json','utf8'))" && echo OK
```

- [ ] **Step 3: Commit**

```bash
mkdir -p references
git add references/chapter-index.json
git commit -m "feat: add SAD chapter-index for sad-lookup script"
```

---

### Task 9: Write `sad-lookup.sh` (TDD via bats)

**Files:**
- Create: `scripts/sad-lookup.sh`
- Test: `tests/scripts/sad-lookup.bats`

- [ ] **Step 1: Write the failing bats test**

`tests/scripts/sad-lookup.bats`:
```bash
#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/sad-lookup.sh"
    FAKE_DOCS="$(mktemp -d)"
    # Build a fake SAD doc tree
    for n in 01 05 10 25; do
        printf '# Chapter %s\nbody body body\n' "$n" > "${FAKE_DOCS}/mORMot2-SAD-Chapter-${n}.md"
    done
}

teardown() {
    rm -rf "$FAKE_DOCS"
}

@test "exits 2 when MORMOT2_DOC_PATH is unset" {
    unset MORMOT2_DOC_PATH
    run "$SCRIPT" torm
    [ "$status" -eq 2 ]
    [[ "$output" == *"MORMOT2_DOC_PATH"* ]]
}

@test "exits 2 when MORMOT2_DOC_PATH does not exist" {
    MORMOT2_DOC_PATH="/no/such/path" run "$SCRIPT" torm
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

@test "resolves topic to chapter number" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chapter 05"* ]]
}

@test "accepts a chapter number directly" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chapter 10"* ]]
}

@test "exits 3 when chapter file is missing" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" 99
    [ "$status" -eq 3 ]
    [[ "$output" == *"not found"* ]]
}

@test "exits 4 when topic is unknown" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" not-a-topic
    [ "$status" -eq 4 ]
    [[ "$output" == *"unknown topic"* ]]
}

@test "default excerpt limit is 200 lines" {
    # Pad chapter 5 with 500 lines
    yes line | head -n 500 >> "${FAKE_DOCS}/mORMot2-SAD-Chapter-05.md"
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm
    [ "$status" -eq 0 ]
    line_count=$(printf '%s\n' "$output" | wc -l)
    [ "$line_count" -le 202 ]    # 200 + header + path
}
```

- [ ] **Step 2: Run the failing test**

```bash
mkdir -p scripts tests/scripts
bats tests/scripts/sad-lookup.bats
```

Expected: all tests fail (script does not exist).

- [ ] **Step 3: Write the script**

`scripts/sad-lookup.sh`:
```bash
#!/usr/bin/env bash
# sad-lookup: resolve a mORMot 2 SAD topic or chapter number to a chapter
# excerpt. Reads MORMOT2_DOC_PATH for the docs tree and the plugin's
# references/chapter-index.json for topic → chapter mapping.
#
# Usage: sad-lookup.sh <topic-or-number> [line-limit]
# Exit codes:
#   0 success
#   1 misuse
#   2 MORMOT2_DOC_PATH unset or invalid
#   3 chapter file missing under MORMOT2_DOC_PATH
#   4 unknown topic

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: sad-lookup.sh <topic-or-number> [line-limit]" >&2
    exit 1
fi

QUERY="$1"
LIMIT="${2:-200}"

if [ -z "${MORMOT2_DOC_PATH:-}" ]; then
    echo "error: MORMOT2_DOC_PATH is not set; run /mormot2-init or set it manually" >&2
    exit 2
fi

if [ ! -d "$MORMOT2_DOC_PATH" ]; then
    echo "error: MORMOT2_DOC_PATH=$MORMOT2_DOC_PATH not found" >&2
    exit 2
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="${PLUGIN_ROOT}/references/chapter-index.json"

# Resolve query to a 2-digit chapter number
if [[ "$QUERY" =~ ^[0-9]+$ ]]; then
    CHAPTER=$(printf '%02d' "$QUERY")
else
    # Lower-case the topic and look it up in the index via node (already a dep
    # via package.json/main).
    CHAPTER=$(node -e "
        const idx = JSON.parse(require('fs').readFileSync('$INDEX','utf8'));
        const k = process.argv[1].toLowerCase();
        const v = idx.topics[k];
        if (v === undefined) { process.exit(4); }
        process.stdout.write(String(v).padStart(2,'0'));
    " "$QUERY") || {
        echo "error: unknown topic '$QUERY'" >&2
        exit 4
    }
fi

FILE="${MORMOT2_DOC_PATH}/mORMot2-SAD-Chapter-${CHAPTER}.md"
if [ ! -f "$FILE" ]; then
    echo "error: chapter ${CHAPTER} file not found at $FILE" >&2
    exit 3
fi

# Emit header + excerpt
printf 'Chapter %s — %s\n' "$CHAPTER" "$FILE"
head -n "$LIMIT" "$FILE"
```

- [ ] **Step 4: Make the script executable**

```bash
chmod +x scripts/sad-lookup.sh
```

- [ ] **Step 5: Run the tests**

```bash
bats tests/scripts/sad-lookup.bats
```

Expected: all 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/sad-lookup.sh tests/scripts/sad-lookup.bats
git commit -m "feat: add sad-lookup.sh with bats coverage"
```

---

### Task 10: Write `sad-lookup.ps1` (TDD via Pester)

**Files:**
- Create: `scripts/sad-lookup.ps1`
- Test: `tests/scripts/sad-lookup.Tests.ps1`

- [ ] **Step 1: Write the failing Pester test**

`tests/scripts/sad-lookup.Tests.ps1`:
```powershell
BeforeAll {
    $PluginRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Script    = Join-Path $PluginRoot 'scripts/sad-lookup.ps1'
    $FakeDocs  = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "sadlookup-$(Get-Random)") -Force
    foreach ($n in '01','05','10','25') {
        Set-Content -Path (Join-Path $FakeDocs.FullName "mORMot2-SAD-Chapter-$n.md") -Value "# Chapter $n`nbody body body"
    }
}

AfterAll {
    Remove-Item -Recurse -Force $FakeDocs.FullName
}

Describe 'sad-lookup.ps1' {
    It 'exits 2 when MORMOT2_DOC_PATH is unset' {
        $env:MORMOT2_DOC_PATH = $null
        & $Script torm
        $LASTEXITCODE | Should -Be 2
    }

    It 'exits 2 when MORMOT2_DOC_PATH does not exist' {
        $env:MORMOT2_DOC_PATH = 'X:/no/such/path'
        & $Script torm
        $LASTEXITCODE | Should -Be 2
    }

    It 'resolves topic to chapter number' {
        $env:MORMOT2_DOC_PATH = $FakeDocs.FullName
        $out = & $Script torm
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'Chapter 05'
    }

    It 'accepts a chapter number directly' {
        $env:MORMOT2_DOC_PATH = $FakeDocs.FullName
        $out = & $Script 10
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'Chapter 10'
    }

    It 'exits 3 when chapter file is missing' {
        $env:MORMOT2_DOC_PATH = $FakeDocs.FullName
        & $Script 99
        $LASTEXITCODE | Should -Be 3
    }

    It 'exits 4 when topic is unknown' {
        $env:MORMOT2_DOC_PATH = $FakeDocs.FullName
        & $Script not-a-topic
        $LASTEXITCODE | Should -Be 4
    }
}
```

- [ ] **Step 2: Run failing test**

```powershell
Invoke-Pester tests/scripts/sad-lookup.Tests.ps1
```

Expected: all tests fail (script does not exist).

- [ ] **Step 3: Write the script**

`scripts/sad-lookup.ps1`:
```powershell
<#
.SYNOPSIS
sad-lookup: resolve a mORMot 2 SAD topic or chapter number to a chapter excerpt.

.DESCRIPTION
Reads MORMOT2_DOC_PATH for the docs tree and the plugin's
references/chapter-index.json for topic-to-chapter mapping.

Exit codes:
  0 success
  1 misuse
  2 MORMOT2_DOC_PATH unset or invalid
  3 chapter file missing under MORMOT2_DOC_PATH
  4 unknown topic
#>
param(
    [Parameter(Mandatory = $true)] [string]$Query,
    [int]$Limit = 200
)

$ErrorActionPreference = 'Stop'

$DocPath = $env:MORMOT2_DOC_PATH
if ([string]::IsNullOrEmpty($DocPath)) {
    Write-Error 'MORMOT2_DOC_PATH is not set; run /mormot2-init or set it manually'
    exit 2
}
if (-not (Test-Path $DocPath -PathType Container)) {
    Write-Error "MORMOT2_DOC_PATH=$DocPath not found"
    exit 2
}

$PluginRoot = Split-Path -Parent $PSScriptRoot
$Index      = Join-Path $PluginRoot 'references/chapter-index.json'

if ($Query -match '^\d+$') {
    $Chapter = "{0:D2}" -f [int]$Query
} else {
    $idx = Get-Content $Index -Raw | ConvertFrom-Json
    $key = $Query.ToLower()
    $val = $idx.topics.$key
    if ($null -eq $val) {
        Write-Error "unknown topic '$Query'"
        exit 4
    }
    $Chapter = "{0:D2}" -f [int]$val
}

$File = Join-Path $DocPath "mORMot2-SAD-Chapter-$Chapter.md"
if (-not (Test-Path $File -PathType Leaf)) {
    Write-Error "chapter $Chapter file not found at $File"
    exit 3
}

"Chapter $Chapter — $File"
Get-Content -Path $File -TotalCount $Limit
```

- [ ] **Step 4: Run tests**

```powershell
Invoke-Pester tests/scripts/sad-lookup.Tests.ps1
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/sad-lookup.ps1 tests/scripts/sad-lookup.Tests.ps1
git commit -m "feat: add sad-lookup.ps1 with Pester coverage"
```

---

### Task 11: Write `delphi-build.ps1` (TDD via Pester)

**Files:**
- Create: `scripts/delphi-build.ps1`
- Test: `tests/scripts/delphi-build.Tests.ps1`

- [ ] **Step 1: Write the failing Pester test (boundary behaviour only)**

`tests/scripts/delphi-build.Tests.ps1`:
```powershell
BeforeAll {
    $PluginRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Script    = Join-Path $PluginRoot 'scripts/delphi-build.ps1'
}

Describe 'delphi-build.ps1 — boundary behaviour' {
    It 'exits 2 when MORMOT2_PATH is unset' {
        $env:MORMOT2_PATH = $null
        $TempDpr = New-TemporaryFile
        & $Script -Project $TempDpr.FullName 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 2
        Remove-Item $TempDpr.FullName -Force
    }

    It 'exits 2 when MORMOT2_PATH does not exist' {
        $env:MORMOT2_PATH = 'X:/no/such/path'
        & $Script -Project 'fake.dpr' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'exits 5 when project file does not exist' {
        $env:MORMOT2_PATH = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mp-$(Get-Random)") -Force).FullName
        & $Script -Project 'no-such-project.dpr' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 5
        Remove-Item -Recurse -Force $env:MORMOT2_PATH
    }

    It 'exits 6 when no Delphi compiler is on PATH' {
        # Simulate by using a temp PATH that has no dcc executables
        $env:MORMOT2_PATH = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mp-$(Get-Random)") -Force).FullName
        $TempDpr = New-Item -ItemType File -Path (Join-Path $env:MORMOT2_PATH 'fake.dpr') -Force
        $oldPath = $env:PATH
        $env:PATH = $env:MORMOT2_PATH
        try {
            & $Script -Project $TempDpr.FullName 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 6
        } finally {
            $env:PATH = $oldPath
            Remove-Item -Recurse -Force $env:MORMOT2_PATH
        }
    }

    It 'emits a BUILD_RESULT line on every code path' {
        $env:MORMOT2_PATH = (New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "mp-$(Get-Random)") -Force).FullName
        $TempDpr = New-Item -ItemType File -Path (Join-Path $env:MORMOT2_PATH 'fake.dpr') -Force
        $out = & $Script -Project $TempDpr.FullName 2>&1
        ($out -join "`n") | Should -Match 'BUILD_RESULT exit='
        Remove-Item -Recurse -Force $env:MORMOT2_PATH
    }
}
```

- [ ] **Step 2: Run failing tests**

```powershell
Invoke-Pester tests/scripts/delphi-build.Tests.ps1
```

Expected: all tests fail.

- [ ] **Step 3: Write the script**

`scripts/delphi-build.ps1`:
```powershell
<#
.SYNOPSIS
delphi-build: compile a Delphi project (.dpr or .dproj) with mORMot 2
search paths injected.

.DESCRIPTION
Resolves MORMOT2_PATH, picks dcc32 vs dcc64 (default dcc64), and either
calls MSBuild on a .dproj or invokes the dcc compiler on a .dpr. Emits a
trailing structured BUILD_RESULT line that downstream skills grep.

Exit codes:
  0 success
  1 misuse
  2 MORMOT2_PATH unset or invalid
  5 project file missing
  6 no Delphi compiler on PATH
  7 build failed (errors > 0)
#>
param(
    [Parameter(Mandatory = $true)] [string]$Project,
    [ValidateSet('dcc32','dcc64','msbuild','auto')] [string]$Compiler = 'auto'
)

$ErrorActionPreference = 'Continue'

function Emit-Result {
    param([int]$ExitCode, [int]$Errors = 0, [int]$Warnings = 0, [string]$First = '')
    "BUILD_RESULT exit=$ExitCode errors=$Errors warnings=$Warnings first=$First"
}

if ([string]::IsNullOrEmpty($env:MORMOT2_PATH)) {
    Write-Error 'MORMOT2_PATH is not set'
    Emit-Result -ExitCode 2 -First 'MORMOT2_PATH unset'
    exit 2
}
if (-not (Test-Path $env:MORMOT2_PATH -PathType Container)) {
    Write-Error "MORMOT2_PATH=$env:MORMOT2_PATH not found"
    Emit-Result -ExitCode 2 -First "MORMOT2_PATH not found"
    exit 2
}
if (-not (Test-Path $Project -PathType Leaf)) {
    Write-Error "project file '$Project' does not exist"
    Emit-Result -ExitCode 5 -First "project missing: $Project"
    exit 5
}

# Resolve compiler
$ResolvedCompiler = $Compiler
if ($Compiler -eq 'auto') {
    if ($Project -match '\.dproj$') { $ResolvedCompiler = 'msbuild' }
    else                            { $ResolvedCompiler = 'dcc64'   }
}

$ExeName = switch ($ResolvedCompiler) {
    'dcc32'   { 'dcc32.exe'   }
    'dcc64'   { 'dcc64.exe'   }
    'msbuild' { 'msbuild.exe' }
}

$Found = Get-Command $ExeName -ErrorAction SilentlyContinue
if (-not $Found) {
    Write-Error "$ExeName not found on PATH"
    Emit-Result -ExitCode 6 -First "$ExeName missing from PATH"
    exit 6
}

# Build search-path arguments for dcc compilers
$SrcRoot = Join-Path $env:MORMOT2_PATH 'src'
$SearchPaths = @(
    $SrcRoot,
    (Join-Path $SrcRoot 'core'),
    (Join-Path $SrcRoot 'orm'),
    (Join-Path $SrcRoot 'rest'),
    (Join-Path $SrcRoot 'soa'),
    (Join-Path $SrcRoot 'db'),
    (Join-Path $SrcRoot 'crypt'),
    (Join-Path $SrcRoot 'net'),
    (Join-Path $SrcRoot 'app'),
    (Join-Path $SrcRoot 'lib')
) | Where-Object { Test-Path $_ -PathType Container }

if ($ResolvedCompiler -eq 'msbuild') {
    $output = & $Found.Path $Project /t:Build /p:Config=Debug 2>&1
} else {
    $unitArgs = $SearchPaths | ForEach-Object { "-U`"$_`"" }
    $incArgs  = $SearchPaths | ForEach-Object { "-I`"$_`"" }
    $output = & $Found.Path @unitArgs @incArgs $Project 2>&1
}
$exit = $LASTEXITCODE

# Parse errors and first error line (best-effort)
$errors = ($output | Select-String -Pattern '\bError:|\[dcc\d+ Error\]|\bF\d{4}:' -AllMatches).Matches.Count
$warns  = ($output | Select-String -Pattern '\bWarning:|\[dcc\d+ Warning\]'         -AllMatches).Matches.Count
$first  = ($output | Select-String -Pattern '\bError:|\[dcc\d+ Error\]|\bF\d{4}:'    | Select-Object -First 1).Line
if (-not $first) { $first = '' }

# Always print the build output to stdout so the caller can see it.
$output | ForEach-Object { Write-Output $_ }

if ($exit -ne 0 -or $errors -gt 0) {
    Emit-Result -ExitCode 7 -Errors $errors -Warnings $warns -First $first
    exit 7
}

Emit-Result -ExitCode 0 -Errors 0 -Warnings $warns -First ''
exit 0
```

- [ ] **Step 4: Run tests**

```powershell
Invoke-Pester tests/scripts/delphi-build.Tests.ps1
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/delphi-build.ps1 tests/scripts/delphi-build.Tests.ps1
git commit -m "feat: add delphi-build.ps1 with Pester boundary tests"
```

---

### Task 12: Write `fpc-build.sh` (TDD via bats)

**Files:**
- Create: `scripts/fpc-build.sh`
- Test: `tests/scripts/fpc-build.bats`

- [ ] **Step 1: Write the failing bats test**

`tests/scripts/fpc-build.bats`:
```bash
#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/fpc-build.sh"
    FAKE_MM="$(mktemp -d)"
    mkdir -p "${FAKE_MM}/src/core" "${FAKE_MM}/src/orm"
    FAKE_PROJ="$(mktemp -d)"
    printf 'program fake;\nbegin\nend.\n' > "${FAKE_PROJ}/fake.dpr"
}

teardown() {
    rm -rf "$FAKE_MM" "$FAKE_PROJ"
}

@test "exits 2 when MORMOT2_PATH is unset" {
    unset MORMOT2_PATH
    run "$SCRIPT" --project "${FAKE_PROJ}/fake.dpr"
    [ "$status" -eq 2 ]
    [[ "$output" == *"MORMOT2_PATH"* ]]
}

@test "exits 5 when project file is missing" {
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --project /no/such/file.dpr
    [ "$status" -eq 5 ]
}

@test "exits 6 when fpc is not on PATH" {
    PATH="/usr/bin:/bin" command -v fpc >/dev/null 2>&1 && skip "fpc is on PATH on this system"
    MORMOT2_PATH="$FAKE_MM" PATH="" run "$SCRIPT" --project "${FAKE_PROJ}/fake.dpr"
    [ "$status" -eq 6 ]
}

@test "emits BUILD_RESULT on every code path" {
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --project /no/such/file.dpr
    [[ "$output" == *"BUILD_RESULT exit="* ]]
}
```

- [ ] **Step 2: Run failing tests**

```bash
bats tests/scripts/fpc-build.bats
```

- [ ] **Step 3: Write the script**

`scripts/fpc-build.sh`:
```bash
#!/usr/bin/env bash
# fpc-build: compile a Pascal project with FPC or lazbuild, with mORMot 2
# search paths injected.
#
# Usage: fpc-build.sh [--lpi <file.lpi>] [--project <file.dpr|.lpr|.lpi>]
#
# When --lpi is set or the project ends in .lpi, lazbuild is used.
# Otherwise fpc is invoked with -Mobjfpc and a curated set of -Fu/-Fi paths
# under $MORMOT2_PATH/src.
#
# Always emits a trailing BUILD_RESULT line.
#
# Exit codes:
#   0 success
#   1 misuse
#   2 MORMOT2_PATH unset or invalid
#   5 project file missing
#   6 fpc/lazbuild not on PATH
#   7 build failed (errors > 0)

set -uo pipefail

emit_result() {
    local exit_code="$1" errors="${2:-0}" warns="${3:-0}" first="${4:-}"
    echo "BUILD_RESULT exit=${exit_code} errors=${errors} warnings=${warns} first=${first}"
}

PROJECT=""
USE_LAZBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        --lpi)     PROJECT="$2"; USE_LAZBUILD=1; shift 2 ;;
        *) echo "fpc-build: unknown arg '$1'" >&2; emit_result 1 0 0 "bad arg: $1"; exit 1 ;;
    esac
done

if [ -z "$PROJECT" ]; then
    echo "fpc-build: --project or --lpi is required" >&2
    emit_result 1 0 0 "no project"
    exit 1
fi

if [ -z "${MORMOT2_PATH:-}" ]; then
    echo "error: MORMOT2_PATH is not set" >&2
    emit_result 2 0 0 "MORMOT2_PATH unset"
    exit 2
fi

if [ ! -d "$MORMOT2_PATH" ]; then
    echo "error: MORMOT2_PATH=$MORMOT2_PATH not found" >&2
    emit_result 2 0 0 "MORMOT2_PATH missing"
    exit 2
fi

if [ ! -f "$PROJECT" ]; then
    echo "error: project file '$PROJECT' does not exist" >&2
    emit_result 5 0 0 "project missing: $PROJECT"
    exit 5
fi

if [[ "$PROJECT" == *.lpi ]]; then USE_LAZBUILD=1; fi

if [ $USE_LAZBUILD -eq 1 ]; then
    if ! command -v lazbuild >/dev/null 2>&1; then
        echo "error: lazbuild not found on PATH" >&2
        emit_result 6 0 0 "lazbuild missing"
        exit 6
    fi
    output=$(lazbuild "$PROJECT" 2>&1) || true
    exit_code=$?
else
    if ! command -v fpc >/dev/null 2>&1; then
        echo "error: fpc not found on PATH" >&2
        emit_result 6 0 0 "fpc missing"
        exit 6
    fi
    SRC="${MORMOT2_PATH}/src"
    fu_args=()
    fi_args=()
    for d in "$SRC" "$SRC/core" "$SRC/orm" "$SRC/rest" "$SRC/soa" "$SRC/db" "$SRC/crypt" "$SRC/net" "$SRC/app" "$SRC/lib"; do
        if [ -d "$d" ]; then
            fu_args+=("-Fu${d}")
            fi_args+=("-Fi${d}")
        fi
    done
    output=$(fpc -Mobjfpc -Sci "${fu_args[@]}" "${fi_args[@]}" "$PROJECT" 2>&1) || true
    exit_code=$?
fi

errors=$(printf '%s\n' "$output" | grep -cE '^Error:|^Fatal:|\.pas\([0-9]+,[0-9]+\) Error:' || true)
warns=$(printf '%s\n'  "$output" | grep -cE '^Warning:|\.pas\([0-9]+,[0-9]+\) Warning:'  || true)
first=$(printf '%s\n'  "$output" | grep -E  '^Error:|^Fatal:|\.pas\([0-9]+,[0-9]+\) Error:' | head -n1 | tr '\n' ' ')

# Print full output before the BUILD_RESULT line
printf '%s\n' "$output"

if [ "${exit_code:-0}" -ne 0 ] || [ "${errors:-0}" -gt 0 ]; then
    emit_result 7 "${errors:-0}" "${warns:-0}" "$first"
    exit 7
fi

emit_result 0 0 "${warns:-0}" ""
exit 0
```

- [ ] **Step 4: Make executable + run tests**

```bash
chmod +x scripts/fpc-build.sh
bats tests/scripts/fpc-build.bats
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/fpc-build.sh tests/scripts/fpc-build.bats
git commit -m "feat: add fpc-build.sh with bats boundary tests"
```

---

### Task 13: Extend the session-start hook

**Files:**
- Modify: `hooks/session-start`

- [ ] **Step 1: Read current hook**

```bash
cat hooks/session-start
```

(Already read in the briefing; the hook is a bash script that injects the `using-superpowers` skill into session context.)

- [ ] **Step 2: Append the mORMot 2 config-loading + Pascal-detection block**

Add this block immediately before the final `if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then` dispatch (so it runs unconditionally):

```bash
# --- mormot2-superpowers: config + Pascal detection ----------------------
# Defensive — never abort the session on config issues.
mormot2_block=""
config_path=".claude/mormot2.config.json"
if [ -f "$config_path" ]; then
    if mormot2_path=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('$config_path','utf8'));
            if (c.mormot2_path) process.stdout.write(c.mormot2_path);
        } catch (e) { process.exit(1); }
    " 2>/dev/null); then
        if [ -n "$mormot2_path" ]; then
            export MORMOT2_PATH="$mormot2_path"
        fi
    fi
    if mormot2_doc=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('$config_path','utf8'));
            const p = c.mormot2_doc_path || (c.mormot2_path ? c.mormot2_path + '/docs' : '');
            if (p) process.stdout.write(p);
        } catch (e) { process.exit(1); }
    " 2>/dev/null); then
        if [ -n "$mormot2_doc" ]; then
            export MORMOT2_DOC_PATH="$mormot2_doc"
        fi
    fi
fi

# Detect Pascal context: any .dpr/.dproj/.lpi/.lpr/.pas in cwd or one level deep
if compgen -G "*.dpr" > /dev/null 2>&1 \
   || compgen -G "*.dproj" > /dev/null 2>&1 \
   || compgen -G "*.lpi" > /dev/null 2>&1 \
   || compgen -G "*.lpr" > /dev/null 2>&1 \
   || compgen -G "*.pas" > /dev/null 2>&1 \
   || compgen -G "*/*.dpr" > /dev/null 2>&1 \
   || compgen -G "*/*.lpi" > /dev/null 2>&1 \
   || compgen -G "*/*.pas" > /dev/null 2>&1; then
    export PASCAL_PROJECT=1
    if [ ! -f "$config_path" ]; then
        mormot2_block="\n\n<important-reminder>Pascal project detected but .claude/mormot2.config.json is missing. Run /mormot2-init to scaffold one, or copy mormot2.config.example.json from the plugin root.</important-reminder>"
    fi
fi
mormot2_block_escaped=$(escape_for_json "$mormot2_block")
session_context="${session_context}${mormot2_block_escaped}"
# --- end mormot2-superpowers block ---------------------------------------
```

- [ ] **Step 3: Verify the hook still parses with bash -n**

```bash
bash -n hooks/session-start && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Smoke test the hook on a non-Pascal directory**

```bash
cd /tmp
mkdir -p smoke-non-pascal && cd smoke-non-pascal
unset MORMOT2_PATH MORMOT2_DOC_PATH PASCAL_PROJECT
CLAUDE_PLUGIN_ROOT="$(cd "/c/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers" && pwd)" \
  bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start" > /tmp/hook-out.json 2>&1
echo "exit=$?"
node -e "JSON.parse(require('fs').readFileSync('/tmp/hook-out.json','utf8'))" && echo "valid JSON"
```

Expected: `exit=0`, `valid JSON`. Hook output does NOT contain the Pascal reminder.

- [ ] **Step 5: Smoke test on a Pascal directory**

```bash
mkdir -p /tmp/smoke-pascal && cd /tmp/smoke-pascal
echo 'program smoke; begin end.' > smoke.dpr
CLAUDE_PLUGIN_ROOT="$(cd "/c/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers" && pwd)" \
  bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start" > /tmp/hook-out.json 2>&1
node -e "
  const j = JSON.parse(require('fs').readFileSync('/tmp/hook-out.json','utf8'));
  const ctx = j.additional_context || (j.hookSpecificOutput && j.hookSpecificOutput.additionalContext) || j.additionalContext;
  if (!ctx.includes('Pascal project detected')) { process.exit(1); }
  process.stdout.write('reminder present\n');
"
```

Expected: `reminder present`.

- [ ] **Step 6: Smoke test with a valid config**

```bash
mkdir -p /tmp/smoke-pascal-config/.claude && cd /tmp/smoke-pascal-config
echo 'program smoke; begin end.' > smoke.dpr
cp "/c/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers/mormot2.config.example.json" .claude/mormot2.config.json
CLAUDE_PLUGIN_ROOT="$(cd "/c/Users/badb/Documents/Embarcadero/Studio/Projets/Perso/mormot2-superpowers" && pwd)" \
  bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start" > /tmp/hook-out.json 2>&1
node -e "
  const j = JSON.parse(require('fs').readFileSync('/tmp/hook-out.json','utf8'));
  const ctx = j.additional_context || (j.hookSpecificOutput && j.hookSpecificOutput.additionalContext) || j.additionalContext;
  if (ctx.includes('Pascal project detected but')) { process.exit(1); }
  process.stdout.write('no reminder when config present\n');
"
```

Expected: `no reminder when config present`.

- [ ] **Step 7: Commit**

```bash
git add hooks/session-start
git commit -m "feat(hooks): load mormot2.config.json and detect Pascal context"
```

---

### Task 14: Write `tests/invariants.sh`

**Files:**
- Create: `tests/invariants.sh`

- [ ] **Step 1: Write the invariants script**

`tests/invariants.sh`:
```bash
#!/usr/bin/env bash
# Structural invariants for the mormot2-superpowers plugin. Runs in CI and
# locally via tests/run-quick.sh. Fails fast on any violation.
#
# Checks (Phase-1 scope; expanded as later plans land):
#   I1: package.json declares name "mormot2-superpowers"
#   I2: NOTICE exists and mentions both upstream and mORMot 2
#   I3: every script in scripts/ has both a .ps1 and a .sh sibling
#   I4: every script in scripts/ has a corresponding test in tests/scripts/
#   I5: references/chapter-index.json parses and references chapter file pattern
#   I6: mormot2.config.example.json parses and includes mormot2_path
#   I7: docs/config-schema.md exists
#   I8: hooks/session-start has the mormot2 block

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

fails=0
report() { echo "[FAIL] $1"; fails=$((fails+1)); }
ok()     { echo "[ ok ] $1"; }

# I1
name=$(node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('package.json','utf8')).name||'')")
[ "$name" = "mormot2-superpowers" ] && ok "I1 package.json name" || report "I1 package.json name '$name'"

# I2
if [ -f NOTICE ] && grep -q "obra/superpowers" NOTICE && grep -q "mORMot 2" NOTICE; then
    ok "I2 NOTICE attribution"
else
    report "I2 NOTICE missing or incomplete"
fi

# I3 + I4
violations_3=0
violations_4=0
for f in scripts/*.sh scripts/*.ps1; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    stem="${base%.*}"
    ext="${base##*.}"
    if [ "$ext" = "sh" ]; then
        [ -f "scripts/${stem}.ps1" ] || { report "I3 missing scripts/${stem}.ps1"; violations_3=$((violations_3+1)); }
        [ -f "tests/scripts/${stem}.bats" ] || { report "I4 missing tests/scripts/${stem}.bats"; violations_4=$((violations_4+1)); }
    else
        [ -f "scripts/${stem}.sh" ] || { report "I3 missing scripts/${stem}.sh"; violations_3=$((violations_3+1)); }
        [ -f "tests/scripts/${stem}.Tests.ps1" ] || { report "I4 missing tests/scripts/${stem}.Tests.ps1"; violations_4=$((violations_4+1)); }
    fi
done
[ $violations_3 -eq 0 ] && ok "I3 .ps1/.sh sibling parity"
[ $violations_4 -eq 0 ] && ok "I4 every script has a test"

# I5
if node -e "
    const idx = JSON.parse(require('fs').readFileSync('references/chapter-index.json','utf8'));
    if (!idx.filename_pattern || !idx.topics || !idx.chapter_titles) process.exit(1);
" 2>/dev/null; then
    ok "I5 chapter-index.json schema"
else
    report "I5 chapter-index.json malformed"
fi

# I6
if node -e "
    const c = JSON.parse(require('fs').readFileSync('mormot2.config.example.json','utf8'));
    if (!c.mormot2_path) process.exit(1);
" 2>/dev/null; then
    ok "I6 config example parses"
else
    report "I6 config example malformed"
fi

# I7
[ -f docs/config-schema.md ] && ok "I7 config-schema.md exists" || report "I7 docs/config-schema.md missing"

# I8
if grep -q 'mormot2-superpowers: config + Pascal detection' hooks/session-start; then
    ok "I8 session-start contains mormot2 block"
else
    report "I8 session-start missing mormot2 block"
fi

echo
if [ $fails -eq 0 ]; then
    echo "ALL INVARIANTS PASS"
    exit 0
else
    echo "INVARIANTS FAILED: $fails"
    exit 1
fi
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x tests/invariants.sh
tests/invariants.sh
```

Expected: `ALL INVARIANTS PASS`. (If any fail, fix the offending Task 1-13 output, do not weaken the invariant.)

- [ ] **Step 3: Commit**

```bash
git add tests/invariants.sh
git commit -m "test: add structural invariants for foundation"
```

---

### Task 15: Write `tests/run-quick.sh` and `tests/run-quick.ps1`

**Files:**
- Create: `tests/run-quick.sh`
- Create: `tests/run-quick.ps1`

- [ ] **Step 1: Write the bash quick-runner**

`tests/run-quick.sh`:
```bash
#!/usr/bin/env bash
# tests/run-quick.sh — run invariants and bash script tests in <60s.
# (Domain skill evals and PowerShell tests are run by run-quick.ps1.)

set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

echo "==> invariants"
tests/invariants.sh || exit 1

echo "==> bats (script unit tests)"
if command -v bats >/dev/null 2>&1; then
    bats tests/scripts/*.bats || exit 1
else
    echo "[skip] bats not installed; install via 'npm i -g bats' or your package manager"
fi

echo "ALL QUICK CHECKS PASS"
```

- [ ] **Step 2: Write the PowerShell quick-runner**

`tests/run-quick.ps1`:
```powershell
#!/usr/bin/env pwsh
# tests/run-quick.ps1 — run invariants and Pester tests in <60s.
$ErrorActionPreference = 'Stop'
$PluginRoot = Split-Path -Parent $PSScriptRoot
Set-Location $PluginRoot

Write-Host "==> invariants"
& bash 'tests/invariants.sh'
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Pester (script unit tests)"
if (Get-Module -ListAvailable -Name Pester) {
    $r = Invoke-Pester -Path 'tests/scripts/*.Tests.ps1' -PassThru
    if ($r.FailedCount -gt 0) { exit 1 }
} else {
    Write-Host "[skip] Pester not installed; install via 'Install-Module Pester'"
}

Write-Host "ALL QUICK CHECKS PASS"
```

- [ ] **Step 3: Make bash runner executable and run both**

```bash
chmod +x tests/run-quick.sh
tests/run-quick.sh
```

Expected: `ALL QUICK CHECKS PASS`.

```powershell
pwsh -File tests/run-quick.ps1
```

Expected: `ALL QUICK CHECKS PASS`.

- [ ] **Step 4: Commit**

```bash
git add tests/run-quick.sh tests/run-quick.ps1
git commit -m "test: add cross-platform quick test runners"
```

---

### Task 16: End-of-foundation smoke check

**Files:** none (validation only)

- [ ] **Step 1: Confirm the plugin still loads in Claude Code (manual)**

In a Claude Code session, run `/plugin` and confirm `mormot2-superpowers` appears with the new name. If running this plan inside an existing session that already has the plugin loaded, request a session restart from the user.

- [ ] **Step 2: Confirm the upstream skill catalogue still reports 14 skills**

```bash
ls skills | wc -l
```

Expected: `14`.

- [ ] **Step 3: Confirm no Pascal-specific content was added to skills yet**

```bash
grep -rE "mormot2|mORMot|TOrm|TSynTestCase|RawUtf8" skills/ commands/ agents/ || true
```

Expected: no matches. Pascal/mORMot 2 content lives in `scripts/`, `references/`, `hooks/`, `docs/`, and `NOTICE` only at this point. (Domain skills + addenda land in Plans 2 and 3.)

- [ ] **Step 4: Tag the foundation milestone**

```bash
git tag plan-01-foundation-complete
```

- [ ] **Step 5: Final commit (none expected — verify)**

```bash
git status --porcelain
```

Expected: empty output.

---

## Self-Review (run before handoff)

**Spec coverage:** Each spec section that this plan claims to cover (§4 architecture skeleton, §5.5 scripts, §5.6 config, §5.7 hooks, §10 phases 0-3) has at least one task implementing it. Tier 1 addenda (§5.1), Tier 2 domain skills (§5.2), Tier 3 commands and agent (§5.3-§5.4), and CI/fixtures (§9.4) are intentionally out of scope here and assigned to Plans 2-4.

**Placeholder scan:** No "TBD", "TODO", "implement later" anywhere. Every code block contains the exact content the engineer needs. The Task 6 step that references "this file" of harness-specific divergence still gives a concrete content floor.

**Type/contract consistency:**
- BUILD_RESULT line format `BUILD_RESULT exit=<n> errors=<count> warnings=<count> first=<file:line:msg>` is used identically in `delphi-build.ps1` and `fpc-build.sh`.
- Exit codes are consistent: 0 success, 1 misuse, 2 config issue, 3 chapter file missing (sad-lookup), 4 unknown topic (sad-lookup), 5 project file missing (build), 6 compiler missing (build), 7 build failed (build).
- `mormot2_path` and `mormot2_doc_path` in the config schema match the env-var names `MORMOT2_PATH` / `MORMOT2_DOC_PATH` used by the hook and scripts.
- Invariant I3/I4 enforce the .ps1/.sh + tests parity that the spec §9.3 calls out.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-04-25-mormot2-superpowers-plan-01-foundation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Uses `superpowers:subagent-driven-development`.
2. **Inline Execution** — execute tasks in this session with checkpoints between phases. Uses `superpowers:executing-plans`.

After this plan completes (tag `plan-01-foundation-complete`), the next plan will be **Plan 2: Domain Skills** (Phase 4 — the 10 `mormot2-*` skills with their references and trigger evals). It is generated when foundation is green.

Which approach?
