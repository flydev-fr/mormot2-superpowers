---
description: "Run the project's TSynTestCase regression suite. mORMot 2 native tests only - no DUnitX/FPCUnit fallback."
---

Build and run the project's TSynTestCase test executable, then surface pass/fail.

## Convention

The plugin assumes the project ships a test program at one of:
- `tests/<projectname>Test.dpr` (Delphi)
- `tests/<projectname>Test.lpr` (FPC)
- `tests/run-tests.dpr` (generic)

The test program's `begin ... end.` block calls `Test.RunFromConsole;` from a top-level test class.

If no test executable is present, tell the user how to scaffold one (cross-link the `test-driven-development` skill's Pascal addendum) and exit.

## What you do

1. Locate the test program (in order: `tests/<name>Test.dpr`, `tests/<name>Test.lpr`, `tests/run-tests.dpr`, `tests/run-tests.lpr`, then `tests/*.dpr`/`*.lpr` if exactly one match).
2. Build it: `/delphi-build <test-program>` or `/fpc-build <test-program>` (pick by extension).
3. If build BUILD_RESULT exit != 0, surface and stop.
4. Run the resulting executable.
5. The runner exits 0 only when every TSynTestCase passes; non-zero means at least one assertion failed. Read the output's "Failed tests" lines.
6. Report pass/fail with the failed test names if any.

## Important

This command does NOT invoke DUnitX, FPCUnit, or TestInsight. If the project only has those, tell the user - `/mormot2-test` is opinionated TSynTestCase-only by design (see design spec section 6).
