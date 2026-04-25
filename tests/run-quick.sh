#!/usr/bin/env bash
# tests/run-quick.sh - run invariants and bash script tests in <60s.
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
