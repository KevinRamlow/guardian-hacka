#!/bin/bash
# Persistent agent logger — saves every agent event to disk
# Usage: agent-logger.sh <taskId> <event> <message> [extra]
# Events: spawn, progress, steer, complete, error, timeout, kill
set -euo pipefail

TASK_ID="${1:-unknown}"
EVENT="${2:-log}"
MESSAGE="${3:-}"
EXTRA="${4:-}"

LOGS_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-logs"
MASTER_LOG="$LOGS_DIR/master.log"
TASK_LOG="$LOGS_DIR/${TASK_ID}.log"

mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
ENTRY="[$TIMESTAMP] [$EVENT] $TASK_ID: $MESSAGE"
[ -n "$EXTRA" ] && ENTRY="$ENTRY | $EXTRA"

# Write to task-specific log
echo "$ENTRY" >> "$TASK_LOG"

# Write to master log
echo "$ENTRY" >> "$MASTER_LOG"

# Keep master log under 10K lines
if [ $(wc -l < "$MASTER_LOG" 2>/dev/null || echo 0) -gt 10000 ]; then
  tail -5000 "$MASTER_LOG" > "$MASTER_LOG.tmp" && mv "$MASTER_LOG.tmp" "$MASTER_LOG"
fi
