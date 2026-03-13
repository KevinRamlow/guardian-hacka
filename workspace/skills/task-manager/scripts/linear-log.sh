#!/bin/bash
# Linear logging utility for agents
# Usage: linear-log.sh <task-id> <message> [status]

set -e

OC_HOME="${OPENCLAW_HOME:-$HOME}/.openclaw"
LINEAR_SCRIPT="$OC_HOME/workspace/skills/linear/scripts/linear.sh"

# Source secrets
source "$OC_HOME/.env" 2>/dev/null || true
export LINEAR_API_KEY="${LINEAR_API_KEY}"
export LINEAR_DEFAULT_TEAM="${LINEAR_DEFAULT_TEAM:-AUT}"

TASK_ID="$1"
MESSAGE="$2"
STATUS="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: $0 <task-id> <message> [status]" >&2
    exit 1
fi

# Add comment
"$LINEAR_SCRIPT" comment "$TASK_ID" "$MESSAGE"

# Update status if provided (todo|progress|review|done|blocked)
if [ -n "$STATUS" ]; then
    "$LINEAR_SCRIPT" status "$TASK_ID" "$STATUS"
fi

echo "✅ Logged to Linear $TASK_ID" >&2

# Persistent disk log (ALWAYS — survives API failures)
MASTER_LOG="$OC_HOME/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$MASTER_LOG")"
TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "[$TS] [linear-log] $TASK_ID: ${STATUS:-log} — $MESSAGE" >> "$MASTER_LOG" 2>/dev/null || true

# Slack reporting handled by HEARTBEAT.md (sole Slack reporter)
