#!/bin/bash
# Register Eval Process — Convenience wrapper for agents to register an eval with the process manager.
#
# Usage: register-eval-process.sh --task AUTO-XX --pid <eval-PID> [--context "what changes were made"]
#
# This is what agents should call INSTEAD of polling. After calling this, the agent can exit.
# The process-completion-checker will detect when the eval finishes and spawn a callback agent.
#
set -euo pipefail

PROCESS_MGR="/Users/fonsecabc/.openclaw/workspace/scripts/process-manager.sh"
GUARDIAN_DIR="/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real"

TASK_ID="" PID="" CONTEXT="" TIMEOUT=90

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK_ID="$2"; shift 2 ;;
    --pid)     PID="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *)         echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task required" >&2; exit 1; }
[ -z "$PID" ] && { echo "ERROR: --pid required" >&2; exit 1; }

# Find the most recent eval run directory (created by the eval process)
LATEST_RUN_DIR=$(ls -td "${GUARDIAN_DIR}/evals/.runs/content_moderation/run_"* 2>/dev/null | head -1)
METRICS_PATH=""
if [ -n "$LATEST_RUN_DIR" ]; then
  METRICS_PATH="${LATEST_RUN_DIR}/metrics.json"
fi

# Find the eval log
EVAL_LOG=$(ls -t /tmp/guardian-eval-*.log 2>/dev/null | head -1)
RESULT_PATH="${EVAL_LOG:-/tmp/guardian-eval.log}"

# Register with process manager
PROC_ID=$(bash "$PROCESS_MGR" register \
  --pid "$PID" \
  --type eval \
  --task "$TASK_ID" \
  --result-path "$RESULT_PATH" \
  --metrics-path "$METRICS_PATH" \
  --callback dispatch \
  --context "$CONTEXT" \
  --timeout "$TIMEOUT")

echo "$PROC_ID"
echo ""
echo "Eval registered with process manager."
echo "You can now EXIT safely. The process-completion-checker will:"
echo "  1. Detect when eval finishes"
echo "  2. Read the results"
echo "  3. Spawn a callback agent with results to continue your task"
echo ""
echo "Monitor: bash scripts/process-manager.sh status"
