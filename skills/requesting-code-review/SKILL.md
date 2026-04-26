---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements
---

# Requesting Code Review

Dispatch superpowers:code-reviewer subagent to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history. This keeps the reviewer focused on the work product, not your thought process, and preserves your own context for continued work.

**Core principle:** Review early, review often.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code-reviewer subagent:**

Use Task tool with superpowers:code-reviewer type, fill template at `code-reviewer.md`

**Placeholders:**
- `{WHAT_WAS_IMPLEMENTED}` - What you just built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit
- `{DESCRIPTION}` - Brief summary

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)

[Dispatch superpowers:code-reviewer subagent]
  WHAT_WAS_IMPLEMENTED: Verification and repair functions for conversation index
  PLAN_OR_REQUIREMENTS: Task 2 from docs/superpowers/plans/deployment-plan.md
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types

[Subagent returns]:
  Strengths: Clean architecture, real tests
  Issues:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Fix progress indicators]
[Continue to Task 3]
```

## Integration with Workflows

**Subagent-Driven Development:**
- Review after EACH task
- Catch issues before they compound
- Fix before moving to next task

**Executing Plans:**
- Review after each batch (3 tasks)
- Get feedback, apply, continue

**Ad-Hoc Development:**
- Review before merge
- Review when stuck

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: requesting-code-review/code-reviewer.md

## Pascal / mORMot2 Addendum

> **When this section applies:** the session is operating on a Pascal project (the
> `PASCAL_PROJECT=1` env was exported by the mormot2-superpowers session-start hook).
> If `PASCAL_PROJECT` is unset, ignore this section.

Dispatch the Pascal-aware `code-reviewer` agent (in `agents/code-reviewer.md`) - its checklist already covers the items below. When constructing the review request, give the agent:

- The diff range (e.g. `git diff plan-02-domain-skills-complete..HEAD`).
- The plan task or design section the change implements.
- The BUILD_RESULT lines from `/delphi-build` and/or `/fpc-build`.
- The `/mormot2-test` exit status.

### Pascal review checklist (what the agent will check)

- **String types:** `RawUtf8` for storage/transport, `string` only at UI/RTL boundary, `RawByteString` for binary, `UnicodeString` for VCL - see `mormot2-core`.
- **Interface lifetime:** every `IInvokable` / `IFoo` declared interface has a `[GUID]` literal, and reference-counted lifetime is respected (no `as TObject` on an interface unless the source backs it).
- **try-finally completeness:** every `Create`/`Init`/`Open` has a matching `Free`/`Done`/`Close` in a `try`/`finally` (or the resource is interface-typed and self-managed).
- **`Free` vs `FreeAndNil`:** `FreeAndNil` for fields that may be re-checked; `Free` is acceptable for locals about to leave scope.
- **Threading on `TSqlDBConnection`:** each thread owns its connection; no shared connection across threads. See `mormot2-db/references/thread-safety.md`.
- **ORM reflexes:** no `string` fields on `TOrm` descendants, no `TOrm.ID` self-set, every `published` matters.
- **Build symbols deployed:** `.map` (Delphi) or DWARF (FPC) accompanies the binary.
- **No em dashes** in commit messages or docs (per global rule).
