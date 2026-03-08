#!/bin/bash
# Linear Sync v2 — Match "In Progress" tasks to agent-registry
# If In Progress has no agent → move to Todo
# Simple, reliable, reads from registry (not session store or pgrep)
set -euo pipefail

REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"

source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || { echo "Error: .env.linear not found"; exit 1; }
[ -z "${LINEAR_API_KEY:-}" ] && { echo "Error: LINEAR_API_KEY not set"; exit 1; }

linear_query() {
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$1" | jq -Rs .)}" | jq -r '.data // .errors'
}

update_status() {
  local issue_id="$1" status_name="$2"
  local state_id=$(linear_query "{workflowStates(filter:{name:{eq:\"$status_name\"},team:{key:{eq:\"AUTO\"}}},first:1){nodes{id}}}" | jq -r '.workflowStates.nodes[0].id // empty')
  [ -z "$state_id" ] && { echo "  Warning: Status '$status_name' not found"; return 1; }
  linear_query "mutation{issueUpdate(id:\"$issue_id\",input:{stateId:\"$state_id\"}){success}}" > /dev/null
}

add_comment() {
  local issue_id="$1" body="$2"
  local escaped=$(echo "$body" | jq -Rs .)
  linear_query "mutation{commentCreate(input:{issueId:\"$issue_id\",body:$escaped}){success}}" > /dev/null
}

echo "=== Linear <> Registry Sync ==="

# Get list of task IDs with running agents from registry
RUNNING_TASKS=$(python3 -c "
import json, os
f = '/Users/fonsecabc/.openclaw/tasks/agent-registry.json'
try:
    d = json.load(open(f))
    for tid, a in d.get('agents', {}).items():
        try:
            os.kill(a['pid'], 0)
            print(tid)
        except:
            pass
except:
    pass
" 2>/dev/null)

echo "Running agents: $(echo "$RUNNING_TASKS" | grep -c . 2>/dev/null || echo 0)"

# Get "In Progress" tasks from Linear
IN_PROGRESS=$(linear_query '{issues(filter:{team:{key:{eq:"AUTO"}},state:{name:{eq:"In Progress"}}},first:20){nodes{id identifier title}}}')
IP_COUNT=$(echo "$IN_PROGRESS" | jq '[.issues.nodes[]?] | length')
echo "In Progress tasks: $IP_COUNT"

# Check each
ORPHANED=0
echo "$IN_PROGRESS" | jq -c '.issues.nodes[]?' 2>/dev/null | while read -r task; do
  id=$(echo "$task" | jq -r '.id')
  identifier=$(echo "$task" | jq -r '.identifier')
  title=$(echo "$task" | jq -r '.title')

  if echo "$RUNNING_TASKS" | grep -q "^${identifier}$" 2>/dev/null; then
    echo "  OK $identifier: agent running — $title"
  else
    echo "  ORPHAN $identifier: no agent — moving to Todo — $title"
    update_status "$id" "Todo"
    add_comment "$id" "🔄 **Auto-sync**: Moved to Todo — no active agent in registry. Agent likely completed, crashed, or was killed."
    ORPHANED=$((ORPHANED + 1))
  fi
done

echo ""
echo "Sync complete. Orphans moved: ${ORPHANED:-0}"
