#!/usr/bin/env bash
# Structural invariants for the mormot2-superpowers plugin. Runs in CI and
# locally via tests/run-quick.sh. Fails fast on any violation.
#
# Checks (Phase-1 scope; expanded as later plans land):
#   I1: package.json declares name "mormot2-superpowers"
#   I2: NOTICE exists and mentions both upstream and mORMot 2
#   I3: scripts/ entries not in PLATFORM_SINGLETONS have both .ps1 and .sh siblings
#   I4: every script in scripts/ has a corresponding test in tests/scripts/
#       (.ps1 -> .Tests.ps1, .sh -> .bats)
#   I5: references/chapter-index.json parses and references chapter file pattern
#   I6: mormot2.config.example.json parses and includes mormot2_path
#   I7: docs/config-schema.md exists
#   I8: hooks/session-start has the mormot2 block

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

# Stems whose .ps1 or .sh sibling is intentionally absent because the tool
# they wrap is platform- or role-specific:
#   delphi-build         Windows + Delphi only (PowerShell)
#   fpc-build            cross-platform but bash-only (runs in Git Bash on Windows)
#   bump-version         repo maintenance, bash-only (inherited from upstream)
#   sync-to-codex-plugin repo maintenance, bash-only (inherited from upstream)
# Singletons are also exempt from the I4 "must have a test" rule since their
# tests would have to live in the language-appropriate framework only; the
# inherited maintenance scripts carry no Plan-1 test obligation.
PLATFORM_SINGLETONS=("delphi-build" "fpc-build" "bump-version" "sync-to-codex-plugin" "ci-fixture-build")
# Stems exempt from I4 (no test file required).
TEST_EXEMPT=("bump-version" "sync-to-codex-plugin")

is_test_exempt() {
    local stem="$1"
    local s
    for s in "${TEST_EXEMPT[@]}"; do
        if [ "$s" = "$stem" ]; then return 0; fi
    done
    return 1
}

is_singleton() {
    local stem="$1"
    local s
    for s in "${PLATFORM_SINGLETONS[@]}"; do
        if [ "$s" = "$stem" ]; then return 0; fi
    done
    return 1
}

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
        # I3: matching .ps1 sibling unless stem is a platform singleton
        if ! is_singleton "$stem"; then
            [ -f "scripts/${stem}.ps1" ] || { report "I3 missing scripts/${stem}.ps1 (sibling of ${base})"; violations_3=$((violations_3+1)); }
        fi
        # I4: matching .bats test (exempt for inherited maintenance scripts)
        if ! is_test_exempt "$stem"; then
            [ -f "tests/scripts/${stem}.bats" ] || { report "I4 missing tests/scripts/${stem}.bats"; violations_4=$((violations_4+1)); }
        fi
    else
        # ext = ps1
        if ! is_singleton "$stem"; then
            [ -f "scripts/${stem}.sh" ] || { report "I3 missing scripts/${stem}.sh (sibling of ${base})"; violations_3=$((violations_3+1)); }
        fi
        if ! is_test_exempt "$stem"; then
            [ -f "tests/scripts/${stem}.Tests.ps1" ] || { report "I4 missing tests/scripts/${stem}.Tests.ps1"; violations_4=$((violations_4+1)); }
        fi
    fi
done
[ $violations_3 -eq 0 ] && ok "I3 .ps1/.sh sibling parity (singletons exempt: ${PLATFORM_SINGLETONS[*]})"
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

# I9: every domain skill has SKILL.md with valid frontmatter
#     (name matches dir, description present and <= 200 chars).
DOMAIN_SKILLS=(mormot2-core mormot2-orm mormot2-rest-soa mormot2-net mormot2-db mormot2-deploy mormot2-auth-security delphi-build fpc-build pascal-debugging-logging)
violations_9=0
for s in "${DOMAIN_SKILLS[@]}"; do
    sk="skills/$s/SKILL.md"
    if [ ! -f "$sk" ]; then
        report "I9 missing $sk"
        violations_9=$((violations_9+1))
        continue
    fi
    name=$(awk '/^---$/{c++; next} c==1 && /^name:/{print $2; exit}' "$sk")
    desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description: */, ""); print; exit}' "$sk")
    if [ "$name" != "$s" ]; then
        report "I9 $sk: frontmatter name='$name' does not match dir '$s'"
        violations_9=$((violations_9+1))
    fi
    if [ ${#desc} -eq 0 ]; then
        report "I9 $sk: missing description"
        violations_9=$((violations_9+1))
    elif [ ${#desc} -gt 200 ]; then
        report "I9 $sk: description ${#desc} chars > 200"
        violations_9=$((violations_9+1))
    fi
done
[ $violations_9 -eq 0 ] && ok "I9 domain skill frontmatter"

# I10: every domain skill description ends with 'Do NOT use for' clause.
violations_10=0
for s in "${DOMAIN_SKILLS[@]}"; do
    sk="skills/$s/SKILL.md"
    [ -f "$sk" ] || continue
    desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description: */, ""); print; exit}' "$sk")
    if ! grep -qi 'Do NOT use for' <<<"$desc"; then
        report "I10 $sk: description lacks 'Do NOT use for' clause"
        violations_10=$((violations_10+1))
    fi
done
[ $violations_10 -eq 0 ] && ok "I10 domain skill scope clauses"

# I11: every domain skill has non-empty references/ and an eval.md.
violations_11=0
for s in "${DOMAIN_SKILLS[@]}"; do
    refs="skills/$s/references"
    eval_file="skills/$s/eval.md"
    if [ ! -d "$refs" ]; then
        report "I11 missing $refs"
        violations_11=$((violations_11+1))
    else
        ref_count=$(find "$refs" -type f -name '*.md' 2>/dev/null | wc -l)
        if [ "$ref_count" -lt 1 ]; then
            report "I11 $refs: needs at least 1 reference file"
            violations_11=$((violations_11+1))
        fi
    fi
    if [ ! -f "$eval_file" ]; then
        report "I11 missing $eval_file"
        violations_11=$((violations_11+1))
    fi
done
[ $violations_11 -eq 0 ] && ok "I11 domain skill references and eval"

# I12: no skill SKILL.md or reference contains hard-coded Windows absolute paths.
violations_12=0
for s in "${DOMAIN_SKILLS[@]}"; do
    if grep -nE 'C:\\|C:/Users/' "skills/$s/SKILL.md" "skills/$s/references/"*.md 2>/dev/null; then
        report "I12 hard-coded Windows path in skills/$s/"
        violations_12=$((violations_12+1))
    fi
done
[ $violations_12 -eq 0 ] && ok "I12 no hard-coded Windows paths in domain skills"

# I13: every Tier 1 skill that received an addendum (per Plan 3) contains
#      the gating sentinel and the Pascal/mORMot2 Addendum heading.
ADDENDUM_SKILLS=(test-driven-development systematic-debugging verification-before-completion writing-plans using-git-worktrees requesting-code-review finishing-a-development-branch)
violations_13=0
for s in "${ADDENDUM_SKILLS[@]}"; do
    sk="skills/$s/SKILL.md"
    if [ ! -f "$sk" ]; then
        report "I13 missing $sk"
        violations_13=$((violations_13+1))
        continue
    fi
    if ! grep -q '## Pascal / mORMot2 Addendum' "$sk"; then
        report "I13 $sk lacks '## Pascal / mORMot2 Addendum' heading"
        violations_13=$((violations_13+1))
    fi
    if ! grep -q 'PASCAL_PROJECT=1' "$sk"; then
        report "I13 $sk lacks 'PASCAL_PROJECT=1' gating sentinel"
        violations_13=$((violations_13+1))
    fi
done
[ $violations_13 -eq 0 ] && ok "I13 Tier 1 addenda gating"

# I14: every /mormot2-* and /delphi-build / /fpc-build command file exists
#      with frontmatter containing 'description'.
COMMAND_FILES=(commands/mormot2-init.md commands/delphi-build.md commands/fpc-build.md commands/mormot2-test.md commands/mormot2-doc.md)
violations_14=0
for c in "${COMMAND_FILES[@]}"; do
    if [ ! -f "$c" ]; then
        report "I14 missing $c"
        violations_14=$((violations_14+1))
        continue
    fi
    if ! awk '/^---$/{c++; next} c==1 && /^description:/{found=1; exit} END{exit !found}' "$c"; then
        report "I14 $c lacks 'description:' frontmatter"
        violations_14=$((violations_14+1))
    fi
done
[ $violations_14 -eq 0 ] && ok "I14 commands present and well-formed"

# I15: agents/code-reviewer.md contains the Pascal-aware checklist sentinel.
if [ -f agents/code-reviewer.md ] && grep -q 'Pascal/mORMot 2 specific checklist' agents/code-reviewer.md; then
    ok "I15 code-reviewer agent contains Pascal checklist"
else
    report "I15 agents/code-reviewer.md missing Pascal checklist"
fi

echo
if [ $fails -eq 0 ]; then
    echo "ALL INVARIANTS PASS"
    exit 0
else
    echo "INVARIANTS FAILED: $fails"
    exit 1
fi
