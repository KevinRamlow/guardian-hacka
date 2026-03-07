#!/bin/bash
# Query Langfuse traces for Anton + subagents
set -euo pipefail

LANGFUSE_PUBLIC_KEY="[REDACTED]"
LANGFUSE_SECRET_KEY="[REDACTED]"
AUTH=$(echo -n "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" | base64)

ACTION="${1:-recent}"

case "$ACTION" in
  recent)
    echo "Recent traces (last 24h):"
    curl -s "https://us.cloud.langfuse.com/api/public/traces?page=1&limit=20" \
      -H "Authorization: Basic $AUTH" \
      | jq -r '.data[] | "\(.name) | \(.timestamp) | tokens: \(.usage.total // 0)"' \
      | head -20
    ;;
  
  stats)
    echo "Session statistics (last 24h):"
    curl -s "https://us.cloud.langfuse.com/api/public/traces?page=1&limit=100" \
      -H "Authorization: Basic $AUTH" \
      | jq -r '
        .data 
        | group_by(.tags[0]) 
        | map({
            type: .[0].tags[0],
            count: length,
            total_tokens: map(.usage.total // 0) | add
          })
        | .[]
        | "\(.type): \(.count) traces, \(.total_tokens) tokens"
      '
    ;;
  
  task)
    TASK_ID="${2:-CAI-304}"
    echo "Traces for $TASK_ID:"
    curl -s "https://us.cloud.langfuse.com/api/public/traces?page=1&limit=50" \
      -H "Authorization: Basic $AUTH" \
      | jq -r --arg task "$TASK_ID" '
        .data[] 
        | select(.tags[]? == $task)
        | "\(.name) | \(.timestamp) | \(.metadata.model // "unknown")"
      '
    ;;
  
  *)
    echo "Usage: $0 {recent|stats|task <CAI-XXX>}"
    exit 1
    ;;
esac
