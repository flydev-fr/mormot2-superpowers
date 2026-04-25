# Skill Trigger Eval Format

Each skill ships an `eval.md` next to its `SKILL.md`. The eval file
contains a single fenced `yaml` block of prompt-to-expected-skill
mappings.

## Schema

```yaml
positive:                 # cases where THIS skill must trigger
  - prompt: "<user prompt the skill is supposed to fire on>"
    expected: <this-skill-name>
    forbidden: [optional list of sibling skills that must NOT also trigger]

negative:                 # cases where THIS skill must NOT trigger
  - prompt: "<user prompt that belongs to a sibling skill>"
    must_not_trigger: <this-skill-name>
    expected: <whichever sibling skill is correct>
```

## Threshold

Plan 2 ships per-skill evals with at least 3 positive and 2 negative cases.
The full pressure-test threshold (>= 95% across 30+ prompts per skill, per design spec section 9.2)
is established in Plan 4. For now, every case in `eval.md` must pass before
the skill is considered shipped.

## Running

`tests/evals/run-evals.sh` parses every `skills/*/eval.md`, dispatches a
subagent per prompt with the catalog of all skills loaded, and asserts
the subagent's chosen skill matches the `expected` field.

In Plan 2 the runner is a stub that performs schema validation only;
real subagent dispatch is wired in Plan 4. The stub still catches malformed
eval files at commit time.
