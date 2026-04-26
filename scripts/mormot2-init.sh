#!/bin/bash
# mormot2-init: scaffold .claude/mormot2.config.json for a Pascal project.
#
# Usage:
#   mormot2-init.sh --mormot2-path <path> [--mormot2-doc-path <path>] [--compiler auto|delphi|fpc] [--force]
#   mormot2-init.sh --scaffold     # not yet implemented (Plan 4)
#
# Exit codes:
#   0 success
#   1 misuse / not yet implemented
#   2 mormot2-path not found
#   3 .claude/mormot2.config.json already exists (use --force to overwrite)

set -uo pipefail

MORMOT2_PATH=""
DOC_PATH=""
COMPILER="auto"
FORCE=0
SCAFFOLD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --mormot2-path)     MORMOT2_PATH="$2"; shift 2 ;;
        --mormot2-doc-path) DOC_PATH="$2"; shift 2 ;;
        --compiler)         COMPILER="$2"; shift 2 ;;
        --force)            FORCE=1; shift ;;
        --scaffold)         SCAFFOLD=1; shift ;;
        *) echo "mormot2-init: unknown arg '$1'" >&2; exit 1 ;;
    esac
done

if [ $SCAFFOLD -eq 1 ]; then
    echo "mormot2-init: --scaffold is not yet implemented; Plan 4 ships project skeletons" >&2
    exit 1
fi

if [ -z "$MORMOT2_PATH" ]; then
    echo "mormot2-init: --mormot2-path is required" >&2
    exit 1
fi

if [ ! -d "$MORMOT2_PATH" ]; then
    echo "mormot2-init: mormot2-path not found: $MORMOT2_PATH" >&2
    exit 2
fi

CFG=".claude/mormot2.config.json"
if [ -f "$CFG" ] && [ $FORCE -eq 0 ]; then
    echo "mormot2-init: $CFG already exists (use --force to overwrite)" >&2
    exit 3
fi

if [ -z "$DOC_PATH" ]; then
    DOC_PATH="${MORMOT2_PATH}/docs"
fi

mkdir -p .claude

cat > "$CFG" <<EOF
{
  "mormot2_path": "${MORMOT2_PATH}",
  "mormot2_doc_path": "${DOC_PATH}",
  "compiler": "${COMPILER}"
}
EOF

echo "mormot2-init: wrote $CFG"
exit 0
