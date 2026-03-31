#!/usr/bin/env bash
# Few-Shot Database CLI wrapper
# Usage: bash scripts/few-shot-db.sh <command> [options]
#
# Commands:
#   init                          Initialize the database
#   ingest --run-dir <path>       Ingest eval results
#   query [--classification X] [--type success|failure] [--text "..."] [--limit N]
#   stats                         Show database statistics

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python3}"

PY_SCRIPT="$SCRIPT_DIR/few-shot-db.py"
if [[ ! -f "$PY_SCRIPT" ]]; then
    echo '{"error":"few-shot-db.py not found"}' >&2
    exit 1
fi

exec "$PYTHON" "$PY_SCRIPT" "$@"
