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
PLATFORM_SINGLETONS=("delphi-build" "fpc-build" "bump-version" "sync-to-codex-plugin")
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

echo
if [ $fails -eq 0 ]; then
    echo "ALL INVARIANTS PASS"
    exit 0
else
    echo "INVARIANTS FAILED: $fails"
    exit 1
fi
