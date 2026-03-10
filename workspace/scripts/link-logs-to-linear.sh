#!/bin/bash
# Link agent logs to Linear task comments
# Usage: link-logs-to-linear.sh <TASK_ID>
set -euo pipefail

TASK_ID="$1"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
STATE_FILE="/Users/fonsecabc/.openclaw/tasks/state.json"

source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null || true

# Get Linear ID from state
LINEAR_ID=$(python3 -c "
import json
state = json.load(open('$STATE_FILE'))
task = state.get('tasks', {}).get('$TASK_ID', {})
print(task.get('linearId', ''))
" 2>/dev/null)

[ -z "$LINEAR_ID" ] && { echo "No Linear ID for $TASK_ID"; exit 1; }

# Build log summary
OUTPUT_LOG="$LOGS_DIR/${TASK_ID}-output.log"
STDERR_LOG="$LOGS_DIR/${TASK_ID}-stderr.log"
EXIT_CODE_FILE="$LOGS_DIR/${TASK_ID}-exit-code"

OUTPUT_SIZE=$([ -f "$OUTPUT_LOG" ] && wc -c < "$OUTPUT_LOG" | tr -d ' ' || echo "0")
STDERR_SIZE=$([ -f "$STDERR_LOG" ] && wc -c < "$STDERR_LOG" | tr -d ' ' || echo "0")
EXIT_CODE=$([ -f "$EXIT_CODE_FILE" ] && cat "$EXIT_CODE_FILE" || echo "unknown")

# Format bytes to KB
OUTPUT_KB=$((OUTPUT_SIZE / 1024))
STDERR_KB=$((STDERR_SIZE / 1024))

LOG_SUMMARY="Agent Logs: ~/.openclaw/tasks/agent-logs/${TASK_ID}-output.log (${OUTPUT_KB}KB), stderr: ${STDERR_KB}KB, exit: $EXIT_CODE"

# Get issue internal ID
ISSUE_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"query{issue(id:\\\"$LINEAR_ID\\\"){id}}\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issue',{}).get('id',''))" 2>/dev/null)

[ -z "$ISSUE_ID" ] && { echo "Linear issue not found: $LINEAR_ID"; exit 1; }

# Add comment
ESCAPED_BODY=$(echo "$LOG_SUMMARY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")

curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"mutation{commentCreate(input:{issueId:\\\"$ISSUE_ID\\\",body:\\\"$ESCAPED_BODY\\\"}){success}}\"}" \
  | python3 -c "import json,sys; success=json.load(sys.stdin).get('data',{}).get('commentCreate',{}).get('success'); print('✅ Logs linked to $LINEAR_ID' if success else '❌ Failed')" 2>/dev/null

