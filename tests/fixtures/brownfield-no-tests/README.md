# brownfield-no-tests fixture

Legacy Pascal project (no mORMot 2, no test rig). Exercises:
- The session-start hook's Pascal-detection branch (`*.dpr`/`*.pas` present).
- The brownfield path of `/mormot2-init` (Plan 3 stubs the `--scaffold` flag; verify the writer-only path leaves source files untouched).
- Reminders surface but do not block: with `.claude/mormot2.config.json` present, the "missing config" reminder is suppressed.

## How CI uses this

The `e2e` job (advisory) runs:

```bash
cd tests/fixtures/brownfield-no-tests
bash ../../../hooks/session-start > /tmp/hook-out.json
node -e "
  const j = JSON.parse(require('fs').readFileSync('/tmp/hook-out.json','utf8'));
  const ctx = j.additional_context || (j.hookSpecificOutput && j.hookSpecificOutput.additionalContext) || j.additionalContext || '';
  if (ctx.includes('Pascal project detected but')) { process.exit(1); }   // config IS present, no nudge
  process.stdout.write('hook quiet when config present\n');
"
```

The fixture is green when the hook emits valid JSON and does NOT include the "Pascal project detected but" nudge (because config is present).
