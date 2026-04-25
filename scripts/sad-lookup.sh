#!/usr/bin/env bash
# sad-lookup: resolve a mORMot 2 SAD topic or chapter number to a chapter
# excerpt. Reads MORMOT2_DOC_PATH for the docs tree and the plugin's
# references/chapter-index.json for topic -> chapter mapping.
#
# Usage: sad-lookup.sh <topic-or-number> [line-limit]
# Exit codes:
#   0 success
#   1 misuse
#   2 MORMOT2_DOC_PATH unset or invalid
#   3 chapter file missing under MORMOT2_DOC_PATH
#   4 unknown topic

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: sad-lookup.sh <topic-or-number> [line-limit]" >&2
    exit 1
fi

QUERY="$1"
LIMIT="${2:-200}"

if [ -z "${MORMOT2_DOC_PATH:-}" ]; then
    echo "error: MORMOT2_DOC_PATH is not set; run /mormot2-init or set it manually" >&2
    exit 2
fi

if [ ! -d "$MORMOT2_DOC_PATH" ]; then
    echo "error: MORMOT2_DOC_PATH=$MORMOT2_DOC_PATH not found" >&2
    exit 2
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="${PLUGIN_ROOT}/references/chapter-index.json"

# On Git Bash / MSYS, native Windows Node sees /c/... paths as literal and
# prepends C:\. Convert to a Windows path when cygpath is available so the
# script works on Windows, Linux, and macOS without changes.
NODE_INDEX="$INDEX"
if command -v cygpath >/dev/null 2>&1; then
    NODE_INDEX="$(cygpath -w "$INDEX")"
fi

# Resolve query to a 2-digit chapter number
if [[ "$QUERY" =~ ^[0-9]+$ ]]; then
    CHAPTER=$(printf '%02d' "$QUERY")
else
    # Lower-case the topic and look it up in the index via node (already a dep
    # via package.json/main).
    CHAPTER=$(NODE_INDEX="$NODE_INDEX" node -e "
        const idx = JSON.parse(require('fs').readFileSync(process.env.NODE_INDEX,'utf8'));
        const k = process.argv[1].toLowerCase();
        const v = idx.topics[k];
        if (v === undefined) { process.exit(4); }
        process.stdout.write(String(v).padStart(2,'0'));
    " "$QUERY") || {
        echo "error: unknown topic '$QUERY'" >&2
        exit 4
    }
fi

FILE="${MORMOT2_DOC_PATH}/mORMot2-SAD-Chapter-${CHAPTER}.md"
if [ ! -f "$FILE" ]; then
    echo "error: chapter ${CHAPTER} file not found at $FILE" >&2
    exit 3
fi

# Emit header + excerpt
printf 'Chapter %s - %s\n' "$CHAPTER" "$FILE"
head -n "$LIMIT" "$FILE"
