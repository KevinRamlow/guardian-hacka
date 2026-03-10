#!/bin/bash
# interactive-checkpoint.sh — Post a checkpoint to Slack and wait for feedback
# Called by agents in interactive mode between steps
#
# Usage: interactive-checkpoint.sh <task-id> <step-name> <summary>
set -euo pipefail

TASK_ID="${1:?Task ID required}"
STEP_NAME="${2:?Step name required}"
SUMMARY="${3:?Summary required}"

source ${OPENCLAW_HOME:-$HOME/.openclaw}/.env 2>/dev/null || true
SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
CAIO_DM="D0AK1B981QR"

[ -z "$SLACK_BOT_TOKEN" ] && { echo "No Slack token, skipping checkpoint"; exit 0; }

# Post checkpoint to Caio's DM
MESSAGE=$(python3 -c "
import json
msg = ':arrows_counterclockwise: *Checkpoint: $TASK_ID — $STEP_NAME*\n\n' + '''$SUMMARY''' + '\n\n_Reply with:_\n' + \
  '• \`!continue\` — proceed to next step\n' + \
  '• \`!steer <direction>\` — change approach\n' + \
  '• \`!abort\` — stop this task'
print(json.dumps({'channel': '$CAIO_DM', 'text': msg, 'mrkdwn': True}))
" 2>/dev/null)

if [ -n "$MESSAGE" ]; then
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$MESSAGE" > /dev/null 2>&1 || true
fi

# Write checkpoint file for the agent to detect
CHECKPOINT_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/checkpoints"
mkdir -p "$CHECKPOINT_DIR"
CHECKPOINT_FILE="$CHECKPOINT_DIR/${TASK_ID}.checkpoint"

echo "waiting" > "$CHECKPOINT_FILE"
echo "Checkpoint posted. Waiting for feedback..."

# Poll for response (max 30 min)
TIMEOUT=1800
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  if [ -f "$CHECKPOINT_FILE" ]; then
    RESPONSE=$(cat "$CHECKPOINT_FILE")
    case "$RESPONSE" in
      continue|!continue)
        rm -f "$CHECKPOINT_FILE"
        echo "continue"
        exit 0
        ;;
      abort|!abort)
        rm -f "$CHECKPOINT_FILE"
        echo "abort"
        exit 1
        ;;
      steer:*)
        DIRECTION="${RESPONSE#steer:}"
        rm -f "$CHECKPOINT_FILE"
        echo "steer:$DIRECTION"
        exit 0
        ;;
      waiting)
        # Still waiting
        ;;
    esac
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

# Timeout — default to continue
rm -f "$CHECKPOINT_FILE"
echo "timeout-continue"
exit 0
