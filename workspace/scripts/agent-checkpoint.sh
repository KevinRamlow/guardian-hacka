#!/bin/bash
# agent-checkpoint.sh — Save agent progress checkpoint for timeout recovery
#
# Usage:
#   agent-checkpoint.sh <task_id> <step_name> <summary_text>
#
# What it does:
#   - Saves a JSON checkpoint to ${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/checkpoints/<task_id>/
#   - Each call overwrites the "latest" checkpoint (one active checkpoint per task)
#   - Checkpoint is read by auto-queue when re-spawning a timed-out agent
#
# Example:
#   agent-checkpoint.sh CAI-42 "phase1_complete" "Analyzed 50/200 eval items. Accuracy so far: 72%. Next: items 51-100."
#   agent-checkpoint.sh CAI-42 "eval_launched" "Eval PID=12345. Run dir: evals/.runs/content_moderation/run_20260308_143200"

TASK_ID="${1:-}"
STEP_NAME="${2:-}"
SUMMARY="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$STEP_NAME" ] || [ -z "$SUMMARY" ]; then
  echo "Usage: agent-checkpoint.sh <task_id> <step_name> <summary>" >&2
  exit 1
fi

CHECKPOINT_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/checkpoints/${TASK_ID}"
mkdir -p "$CHECKPOINT_DIR"

CHECKPOINT_FILE="${CHECKPOINT_DIR}/checkpoint.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EPOCH=$(date +%s)

python3 - <<PYEOF
import json, os

checkpoint = {
    "task_id": "$TASK_ID",
    "step": "$STEP_NAME",
    "summary": """$SUMMARY""",
    "saved_at": "$TIMESTAMP",
    "epoch": $EPOCH
}

with open("$CHECKPOINT_FILE", "w") as f:
    json.dump(checkpoint, f, indent=2)

print(f"Checkpoint saved: $TASK_ID / $STEP_NAME")
PYEOF
