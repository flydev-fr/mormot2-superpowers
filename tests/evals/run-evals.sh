#!/usr/bin/env bash
# tests/evals/run-evals.sh - per-skill trigger eval runner.
#
# Plan 2 implements schema-validation only: every skills/*/eval.md is
# parsed, the schema is checked, and totals are reported. Real subagent
# dispatch is wired in Plan 4.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PLUGIN_ROOT"

fails=0
positive_count=0
negative_count=0

for eval_file in skills/*/eval.md; do
    [ -e "$eval_file" ] || continue
    skill_name=$(basename "$(dirname "$eval_file")")

    yaml_text=$(awk '
        BEGIN { in_block=0 }
        /^```yaml/ { in_block=1; next }
        in_block && /^```/ { in_block=0; next }
        in_block { print }
    ' "$eval_file")

    if [ -z "$yaml_text" ]; then
        echo "[FAIL] $eval_file: no yaml block found"
        fails=$((fails+1))
        continue
    fi

    parse_result=$(node -e "
        const text = process.argv[1];
        const lines = text.split('\n');
        let section = null;
        let entries = { positive: [], negative: [] };
        let cur = null;
        for (const raw of lines) {
            if (raw.match(/^positive:\s*\$/))      { section='positive'; continue; }
            if (raw.match(/^negative:\s*\$/))      { section='negative'; continue; }
            if (raw.match(/^\s*-\s*prompt:\s*/))   {
                cur = { prompt: raw.replace(/^\s*-\s*prompt:\s*/, '').replace(/^\"|\"\$/g,'') };
                if (section) entries[section].push(cur);
                continue;
            }
            const kv = raw.match(/^\s+(prompt|expected|forbidden|must_not_trigger):\s*(.*)\$/);
            if (kv && cur) {
                let v = kv[2].trim();
                if (kv[1] === 'forbidden') {
                    v = v.replace(/^\[|\]\$/g,'').split(',').map(s=>s.trim()).filter(Boolean);
                } else {
                    v = v.replace(/^\"|\"\$/g,'');
                }
                cur[kv[1]] = v;
            }
        }
        let bad = [];
        for (const p of entries.positive) {
            if (!p.prompt)   bad.push('positive: missing prompt');
            if (!p.expected) bad.push('positive: missing expected for prompt: ' + p.prompt);
        }
        for (const n of entries.negative) {
            if (!n.prompt)            bad.push('negative: missing prompt');
            if (!n.must_not_trigger)  bad.push('negative: missing must_not_trigger for prompt: ' + n.prompt);
            if (!n.expected)          bad.push('negative: missing expected for prompt: ' + n.prompt);
        }
        process.stdout.write(JSON.stringify({
            positive: entries.positive.length,
            negative: entries.negative.length,
            errors: bad
        }));
    " -- "$yaml_text")

    if [ -z "$parse_result" ]; then
        echo "[FAIL] $eval_file: parse returned empty"
        fails=$((fails+1))
        continue
    fi

    pos=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).positive))" -- "$parse_result")
    neg=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).negative))" -- "$parse_result")
    err_count=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).errors.length))" -- "$parse_result")

    if [ "$err_count" -gt 0 ]; then
        echo "[FAIL] $eval_file:"
        node -e "JSON.parse(process.argv[1]).errors.forEach(e => console.log('   - ' + e))" -- "$parse_result"
        fails=$((fails+1))
        continue
    fi

    if [ "$pos" -lt 3 ]; then
        echo "[FAIL] $eval_file: needs >= 3 positive cases, got $pos"
        fails=$((fails+1))
        continue
    fi

    if [ "$neg" -lt 2 ]; then
        echo "[FAIL] $eval_file: needs >= 2 negative cases, got $neg"
        fails=$((fails+1))
        continue
    fi

    echo "[ ok ] $skill_name (positive=$pos negative=$neg)"
    positive_count=$((positive_count+pos))
    negative_count=$((negative_count+neg))
done

echo
echo "totals: positive=$positive_count negative=$negative_count fails=$fails"

if [ $fails -eq 0 ]; then
    echo "ALL EVAL SCHEMAS PASS"
    exit 0
else
    echo "EVAL SCHEMA FAILURES: $fails"
    exit 1
fi
