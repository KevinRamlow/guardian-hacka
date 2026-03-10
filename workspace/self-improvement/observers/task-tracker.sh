#!/bin/bash
# task-tracker.sh - Track Linear task completion metrics for CAI team

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$BASE_DIR/metrics/daily-scores"

# Source secrets
OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
source "$OC_HOME/.env" 2>/dev/null || true
source "$OC_HOME/workspace/.env.linear" 2>/dev/null || true

TODAY=$(date -u +%Y-%m-%d)
OUTPUT_FILE="$METRICS_DIR/$TODAY.json"

echo "[task-tracker] Querying Linear API for AUT team tasks..."

# Query for tasks completed today
COMPLETED_QUERY='query {
  issues(
    filter: {
      team: { key: { eq: "AUTO" } }
      completedAt: { gte: "'$(date -u +%Y-%m-%d)'T00:00:00.000Z" }
    }
  ) {
    nodes {
      identifier
      title
      completedAt
      createdAt
    }
  }
}'

COMPLETED_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":$(echo "$COMPLETED_QUERY" | jq -Rs .)}")

COMPLETED_COUNT=$(echo "$COMPLETED_RESPONSE" | jq '.data.issues.nodes | length')

# Query for blocked tasks
BLOCKED_QUERY='query {
  issues(
    filter: {
      team: { key: { eq: "AUTO" } }
      state: { name: { eq: "Blocked" } }
    }
  ) {
    nodes {
      identifier
      title
    }
  }
}'

BLOCKED_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":$(echo "$BLOCKED_QUERY" | jq -Rs .)}")

BLOCKED_COUNT=$(echo "$BLOCKED_RESPONSE" | jq '.data.issues.nodes | length')

# Query for in-progress tasks
PROGRESS_QUERY='query {
  issues(
    filter: {
      team: { key: { eq: "AUTO" } }
      state: { name: { eq: "In Progress" } }
    }
  ) {
    nodes {
      identifier
      title
    }
  }
}'

PROGRESS_RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":$(echo "$PROGRESS_QUERY" | jq -Rs .)}")

PROGRESS_COUNT=$(echo "$PROGRESS_RESPONSE" | jq '.data.issues.nodes | length')

# Calculate average cycle time for completed tasks today (in hours)
AVG_CYCLE_TIME=0
if [[ $COMPLETED_COUNT -gt 0 ]]; then
  TOTAL_SECONDS=0
  for row in $(echo "$COMPLETED_RESPONSE" | jq -r '.data.issues.nodes[] | @base64'); do
    _jq() {
      echo "$row" | base64 --decode | jq -r "$1"
    }
    CREATED=$(_jq '.createdAt')
    COMPLETED=$(_jq '.completedAt')
    
    CREATED_TS=$(date -jf "%Y-%m-%dT%H:%M:%S" "${CREATED%%.*}" +%s 2>/dev/null || echo 0)
    COMPLETED_TS=$(date -jf "%Y-%m-%dT%H:%M:%S" "${COMPLETED%%.*}" +%s 2>/dev/null || echo 0)
    DIFF=$((COMPLETED_TS - CREATED_TS))
    TOTAL_SECONDS=$((TOTAL_SECONDS + DIFF))
  done
  AVG_CYCLE_TIME=$(echo "scale=1; $TOTAL_SECONDS / $COMPLETED_COUNT / 3600" | bc)
fi

# Merge into existing output file or create new
if [[ -f "$OUTPUT_FILE" ]]; then
  # Merge with existing JSON
  EXISTING=$(cat "$OUTPUT_FILE")
  MERGED=$(echo "$EXISTING" | jq ". + {
    \"task_metrics\": {
      \"completed_today\": $COMPLETED_COUNT,
      \"blocked\": $BLOCKED_COUNT,
      \"in_progress\": $PROGRESS_COUNT,
      \"avg_cycle_time_hours\": $AVG_CYCLE_TIME
    }
  }")
  echo "$MERGED" > "$OUTPUT_FILE"
else
  # Create new file
  cat > "$OUTPUT_FILE" <<EOF
{
  "date": "$TODAY",
  "task_metrics": {
    "completed_today": $COMPLETED_COUNT,
    "blocked": $BLOCKED_COUNT,
    "in_progress": $PROGRESS_COUNT,
    "avg_cycle_time_hours": $AVG_CYCLE_TIME
  }
}
EOF
fi

echo "[task-tracker] ✅ Task metrics written to $OUTPUT_FILE"
cat "$OUTPUT_FILE" | jq .task_metrics
