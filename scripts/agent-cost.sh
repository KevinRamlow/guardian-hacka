#!/bin/bash
# Track agent token usage and cost from Langfuse
# Usage: agent-cost.sh [--period 24h|7d|30d] [--task CAI-XX]
set -euo pipefail

source /Users/fonsecabc/.openclaw/workspace/.env.secrets

PERIOD="${1:-24h}"
TASK_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --period) PERIOD="$2"; shift 2 ;;
    --task) TASK_FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Convert period to hours
case "$PERIOD" in
  24h|1d) HOURS=24 ;;
  7d) HOURS=168 ;;
  30d) HOURS=720 ;;
  *) HOURS=24 ;;
esac

# Query Langfuse API for traces
AUTH=$(echo -n "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" | base64)
SINCE=$(date -u -d "$HOURS hours ago" --iso-8601=seconds)

TRACES=$(curl -s "https://us.cloud.langfuse.com/api/public/traces?page=1&limit=1000" \
  -H "Authorization: Basic $AUTH" \
  | jq -r --arg since "$SINCE" --arg task "$TASK_FILTER" '
    .data[]
    | select(.timestamp >= $since)
    | select(if $task != "" then (.tags[]? == $task) else true end)
    | {
        name: .name,
        sessionId: .sessionId,
        timestamp: .timestamp,
        totalTokens: (.usage.total // 0),
        tags: .tags
      }
  ')

if [ -z "$TRACES" ] || [ "$TRACES" = "null" ]; then
  echo "No traces found for period $PERIOD"
  exit 0
fi

# Aggregate by task ID (from tags)
echo "$TRACES" | jq -s '
  group_by(.tags[0] // "unknown")
  | map({
      task: .[0].tags[0] // "unknown",
      count: length,
      totalTokens: map(.totalTokens) | add,
      avgTokens: (map(.totalTokens) | add) / length | floor,
      estimatedCost: ((map(.totalTokens) | add) * 0.000003) | (. * 100 | floor) / 100
    })
  | sort_by(.totalTokens) | reverse
' > /tmp/agent-cost-report.json

cat /tmp/agent-cost-report.json | jq -r '
  .[] | "\(.task): \(.count) runs, \(.totalTokens) tokens, $\(.estimatedCost)"
'

echo ""
echo "Total cost: $"$(cat /tmp/agent-cost-report.json | jq -r '[.[].estimatedCost] | add')
echo "Report saved: /tmp/agent-cost-report.json"
