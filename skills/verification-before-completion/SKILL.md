---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always
---

# Verification Before Completion

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## Why This Matters

From 24 failure memories:
- your human partner said "I don't believe you" - trust broken
- Undefined functions shipped - would crash
- Missing requirements shipped - incomplete features
- Time wasted on false completion → redirect → rework
- Violates: "Honesty is a core value. If you lie, you'll be replaced."

## When To Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. THEN claim the result.

This is non-negotiable.

## Pascal / mORMot2 Addendum

> **When this section applies:** the session is operating on a Pascal project (the
> `PASCAL_PROJECT=1` env was exported by the mormot2-superpowers session-start hook).
> If `PASCAL_PROJECT` is unset, ignore this section.

For mORMot 2 / Pascal projects, "verification before completion" means concrete, automatable evidence in this exact order:

### 1. Compiler exit code 0

Run `/delphi-build` (Delphi project) or `/fpc-build` (FPC/Lazarus project), or both if the project ships dual-target. The wrappers emit a single trailing line:

```
BUILD_RESULT exit=<n> errors=<count> warnings=<count> first=<file:line:msg>
```

Verification passes only if `exit=0` AND `errors=0`. Any non-zero `errors` is a failure even when the linker succeeds.

### 2. Test suite green

Run `/mormot2-test`. The runner exits 0 only when every `TSynTestCase` in the project's regression suite passes. The runner does not invoke DUnitX, FPCUnit, or TestInsight; if the project depends on those, this is a partial verification (call it out in the report).

### 3. Symbols deployed

Confirm the build artefact ships with debug symbols so a future `pascal-debugging-logging` session can resolve stack traces:

- Delphi: `<Project>.map` next to the `.exe` (build with `-GD`).
- FPC: DWARF embedded (`-gw3 -gl`) or `.dbg` sidecar.

Missing symbols is a "verified compiles" not a "verified ships" - say so explicitly.

### 4. Lint signal

Skim BUILD_RESULT `warnings=<count>`. Treat any warning count > 0 as a follow-up task; do not silently accept new warnings introduced by your change.

### Don't claim verification when

- A `TSynTestCase` was added but not run.
- The `.map` or DWARF symbols are missing from the build output.
- Only one compiler was exercised when both `.dproj` and `.lpi` exist.
- The build was a `Make` (incremental); a release `Build` (full) wasn't run.
