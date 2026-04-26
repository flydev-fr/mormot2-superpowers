#!/bin/bash
# ci-fixture-build: helper for CI to rewrite a fixture's mormot2.config.json
# with the real MORMOT2_PATH, then invoke the appropriate build wrapper(s).
#
# Usage:
#   ci-fixture-build.sh --fixture <path> [--dry-run] [--project <relpath>]
#
# Exit codes:
#   0 success (or dry-run rewrite-only success)
#   1 misuse / config issue
#   2 build failed (BUILD_RESULT exit != 0)

set -uo pipefail

FIXTURE=""
DRY_RUN=0
PROJECT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --fixture) FIXTURE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --project) PROJECT="$2"; shift 2 ;;
        *) echo "ci-fixture-build: unknown arg '$1'" >&2; exit 1 ;;
    esac
done

if [ -z "${MORMOT2_PATH:-}" ]; then
    echo "ci-fixture-build: MORMOT2_PATH is not set" >&2
    exit 1
fi

if [ -z "$FIXTURE" ] || [ ! -d "$FIXTURE" ]; then
    echo "ci-fixture-build: fixture not found: $FIXTURE" >&2
    exit 1
fi

CFG="$FIXTURE/.claude/mormot2.config.json"
if [ ! -f "$CFG" ]; then
    echo "ci-fixture-build: missing $CFG" >&2
    exit 1
fi

# Rewrite the config in-place. Pure-bash sed (avoids MSYS path translation
# that affects native node on Windows; node is reserved for JSON parsing
# in callers that need it).
escaped_mm=$(printf '%s\n' "$MORMOT2_PATH" | sed -e 's/[\/&]/\\&/g')
sed -i.bak -e "s/REPLACE_WITH_MORMOT2_PATH/${escaped_mm}/g" "$CFG"
rm -f "${CFG}.bak"

if [ $DRY_RUN -eq 1 ]; then
    echo "ci-fixture-build: dry-run rewrite complete for $CFG"
    exit 0
fi

if [ -z "$PROJECT" ]; then
    echo "ci-fixture-build: --project is required (or --dry-run for rewrite-only)" >&2
    exit 1
fi

PROJECT_PATH="$FIXTURE/$PROJECT"
if [ ! -f "$PROJECT_PATH" ]; then
    echo "ci-fixture-build: project not found: $PROJECT_PATH" >&2
    exit 1
fi

# Pick build wrapper by extension
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$PROJECT_PATH" in
    *.dpr|*.dproj)
        if ! command -v pwsh >/dev/null 2>&1; then
            echo "ci-fixture-build: pwsh not on PATH, cannot build Delphi project" >&2
            exit 1
        fi
        output=$(pwsh -File "$PLUGIN_ROOT/scripts/delphi-build.ps1" -Project "$PROJECT_PATH" 2>&1) || true
        ;;
    *.lpr|*.lpi|*.pp)
        output=$(bash "$PLUGIN_ROOT/scripts/fpc-build.sh" --project "$PROJECT_PATH" 2>&1) || true
        ;;
    *)
        echo "ci-fixture-build: unknown project extension: $PROJECT_PATH" >&2
        exit 1
        ;;
esac

# Echo full output then check the BUILD_RESULT line
printf '%s\n' "$output"
build_line=$(printf '%s\n' "$output" | grep '^BUILD_RESULT' | tail -n1 || true)
if [ -z "$build_line" ]; then
    echo "ci-fixture-build: no BUILD_RESULT line found" >&2
    exit 2
fi

# Parse exit=N
build_exit=$(echo "$build_line" | sed -nE 's/.*exit=([0-9]+).*/\1/p')
if [ "${build_exit:-1}" -ne 0 ]; then
    echo "ci-fixture-build: BUILD_RESULT failed: $build_line" >&2
    exit 2
fi

echo "ci-fixture-build: success ($build_line)"
exit 0
