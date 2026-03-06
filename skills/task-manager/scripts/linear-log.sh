#!/bin/bash
# Linear logging utility for agents
# Usage: linear-log.sh <task-id> <message> [status]

set -e

LINEAR_SCRIPT="/root/.openclaw/workspace/skills/linear/scripts/linear.sh"

# Source Linear config
if [ -f "/root/.openclaw/workspace/.env.linear" ]; then
    source /root/.openclaw/workspace/.env.linear
fi
export LINEAR_API_KEY="${LINEAR_API_KEY:-[REDACTED]}"
export LINEAR_DEFAULT_TEAM="${LINEAR_DEFAULT_TEAM:-CAI}"

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
/root/.openclaw/workspace/scripts/agent-logger.sh "$TASK_ID" "${STATUS:-log}" "$MESSAGE" "linear+slack" 2>/dev/null || true

# Dual-post to Slack
/root/.openclaw/workspace/scripts/slack-linear-post.sh "$TASK_ID" "$MESSAGE" "$STATUS" 2>&1 || echo "⚠️  Slack post failed (non-fatal)" >&2
