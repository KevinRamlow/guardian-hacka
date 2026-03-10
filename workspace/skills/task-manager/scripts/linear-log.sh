#!/bin/bash
# Linear logging utility for agents
# Usage: linear-log.sh <task-id> <message> [status]

set -e

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
LINEAR_SCRIPT="$OC_HOME/workspace/skills/linear/scripts/linear.sh"

# Source secrets (root .env first, workspace .env.linear as fallback)
source "$OC_HOME/.env" 2>/dev/null || true
if [ -f "$OC_HOME/workspace/.env.linear" ]; then
    source "$OC_HOME/workspace/.env.linear"
fi
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
"$OC_HOME/workspace/scripts/agent-logger.sh" "$TASK_ID" "${STATUS:-log}" "$MESSAGE" "linear+slack" 2>/dev/null || true

# Slack notification handled by reporter.sh — slack-linear-post.sh is archived
