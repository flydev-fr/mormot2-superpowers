#!/bin/bash
# fpc-build: compile a Pascal project with FPC or lazbuild, with mORMot 2
# search paths injected.
#
# Usage: fpc-build.sh [--lpi <file.lpi>] [--project <file.dpr|.lpr|.lpi>]
#
# When --lpi is set or the project ends in .lpi, lazbuild is used.
# Otherwise fpc is invoked with -Mobjfpc and a curated set of -Fu/-Fi paths
# under $MORMOT2_PATH/src.
#
# Always emits a trailing BUILD_RESULT line.
#
# Exit codes:
#   0 success
#   1 misuse
#   2 MORMOT2_PATH unset or invalid
#   5 project file missing
#   6 fpc/lazbuild not on PATH
#   7 build failed (errors > 0)

set -uo pipefail

emit_result() {
    local exit_code="$1" errors="${2:-0}" warns="${3:-0}" first="${4:-}"
    echo "BUILD_RESULT exit=${exit_code} errors=${errors} warnings=${warns} first=${first}"
}

PROJECT=""
USE_LAZBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        --lpi)     PROJECT="$2"; USE_LAZBUILD=1; shift 2 ;;
        *) echo "fpc-build: unknown arg '$1'" >&2; emit_result 1 0 0 "bad arg: $1"; exit 1 ;;
    esac
done

if [ -z "$PROJECT" ]; then
    echo "fpc-build: --project or --lpi is required" >&2
    emit_result 1 0 0 "no project"
    exit 1
fi

# Fallback: when MORMOT2_PATH is unset, read it from .claude/mormot2.config.json.
# Hook-exported env vars do not propagate to Claude Code child processes.
if [ -z "${MORMOT2_PATH:-}" ] && [ -f .claude/mormot2.config.json ] && command -v node >/dev/null 2>&1; then
    MORMOT2_PATH=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('.claude/mormot2.config.json','utf8'));
            if (c.mormot2_path) process.stdout.write(c.mormot2_path);
        } catch (e) { process.exit(1); }
    " 2>/dev/null) || true
fi

if [ -z "${MORMOT2_PATH:-}" ]; then
    echo "error: MORMOT2_PATH is not set and no .claude/mormot2.config.json found in cwd" >&2
    emit_result 2 0 0 "MORMOT2_PATH unset"
    exit 2
fi

if [ ! -d "$MORMOT2_PATH" ]; then
    echo "error: MORMOT2_PATH=$MORMOT2_PATH not found" >&2
    emit_result 2 0 0 "MORMOT2_PATH missing"
    exit 2
fi

if [ ! -f "$PROJECT" ]; then
    echo "error: project file '$PROJECT' does not exist" >&2
    emit_result 5 0 0 "project missing: $PROJECT"
    exit 5
fi

if [[ "$PROJECT" == *.lpi ]]; then USE_LAZBUILD=1; fi

if [ $USE_LAZBUILD -eq 1 ]; then
    if ! command -v lazbuild >/dev/null 2>&1; then
        echo "error: lazbuild not found on PATH" >&2
        emit_result 6 0 0 "lazbuild missing"
        exit 6
    fi
    output=$(lazbuild "$PROJECT" 2>&1) || true
    exit_code=$?
else
    if ! command -v fpc >/dev/null 2>&1; then
        echo "error: fpc not found on PATH" >&2
        emit_result 6 0 0 "fpc missing"
        exit 6
    fi
    SRC="${MORMOT2_PATH}/src"
    fu_args=()
    fi_args=()
    for d in "$SRC" "$SRC/core" "$SRC/orm" "$SRC/rest" "$SRC/soa" "$SRC/db" "$SRC/crypt" "$SRC/net" "$SRC/app" "$SRC/lib"; do
        if [ -d "$d" ]; then
            fu_args+=("-Fu${d}")
            fi_args+=("-Fi${d}")
        fi
    done
    output=$(fpc -Mobjfpc -Sci "${fu_args[@]}" "${fi_args[@]}" "$PROJECT" 2>&1) || true
    exit_code=$?
fi

errors=$(printf '%s\n' "$output" | grep -cE '^Error:|^Fatal:|\.pas\([0-9]+,[0-9]+\) Error:' || true)
warns=$(printf '%s\n'  "$output" | grep -cE '^Warning:|\.pas\([0-9]+,[0-9]+\) Warning:'  || true)
first=$(printf '%s\n'  "$output" | grep -E  '^Error:|^Fatal:|\.pas\([0-9]+,[0-9]+\) Error:' | head -n1 | tr '\n' ' ')

# Print full output before the BUILD_RESULT line
printf '%s\n' "$output"

if [ "${exit_code:-0}" -ne 0 ] || [ "${errors:-0}" -gt 0 ]; then
    emit_result 7 "${errors:-0}" "${warns:-0}" "$first"
    exit 7
fi

emit_result 0 0 "${warns:-0}" ""
exit 0
