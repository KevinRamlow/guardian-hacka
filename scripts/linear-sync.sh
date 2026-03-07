#!/bin/bash
# Linear Task Sync — Match "In Progress" tasks to active subagents
# If a task is "In Progress" but has no subagent → move to Todo (agent died)
# If a subagent is running but task isn't "In Progress" → update to In Progress
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$WORKSPACE_DIR/.env.linear" 2>/dev/null || { echo "Error: .env.linear not found"; exit 1; }
[ -z "${LINEAR_API_KEY:-}" ] && { echo "Error: LINEAR_API_KEY not set"; exit 1; }

linear_query() {
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$1" | jq -Rs .)}" | jq -r '.data // .errors'
}

update_status() {
  local issue_id="$1" status_name="$2"
  local state_id=$(linear_query "{workflowStates(filter:{name:{eq:\"$status_name\"},team:{key:{eq:\"CAI\"}}},first:1){nodes{id}}}" | jq -r '.workflowStates.nodes[0].id // empty')
  [ -z "$state_id" ] && { echo "  ⚠️ Status '$status_name' not found"; return 1; }
  linear_query "mutation{issueUpdate(id:\"$issue_id\",input:{stateId:\"$state_id\"}){success}}" > /dev/null
}

add_comment() {
  local issue_id="$1" body="$2"
  local escaped=$(echo "$body" | jq -Rs .)
  linear_query "mutation{commentCreate(input:{issueId:\"$issue_id\",body:$escaped}){success}}" > /dev/null
}

echo "=== Linear ↔ Agent Sync ==="

# 1. Get active subagents (labels like "CAI-77-...", check for task IDs)
SUBAGENT_LABELS=""
SUBAGENT_COUNT=0

# Check actual running subagents via process (the only reliable source)
CLAUDE_PIDS=$(pgrep -x claude 2>/dev/null || true)
CLAUDE_COUNT=0
[ -n "$CLAUDE_PIDS" ] && CLAUDE_COUNT=$(echo "$CLAUDE_PIDS" | wc -l)

# Also check OpenClaw subagents API for labels
SUBAGENT_JSON=$(timeout 5 openclaw sessions 2>/dev/null | grep -oP 'CAI-\d+' || true)

# Build list of task IDs with active agents from session store labels
ACTIVE_TASK_IDS=""
if [ -f "/root/.openclaw/agents/claude/sessions/sessions.json" ]; then
  ACTIVE_TASK_IDS=$(python3 -c "
import json, time
now = int(time.time() * 1000)
store = json.load(open('/root/.openclaw/agents/claude/sessions/sessions.json'))
for k, v in store.items():
    label = v.get('label', '')
    age_ms = now - v.get('updatedAt', 0)
    # Consider active if updated in last 30 min
    if age_ms < 1800000:
        # Extract CAI-XX from label
        import re
        m = re.search(r'CAI-\d+', label)
        if m:
            print(m.group())
" 2>/dev/null || true)
fi

echo "Active agents: $CLAUDE_COUNT processes"
echo "Active task IDs from sessions: ${ACTIVE_TASK_IDS:-none}"

# 2. Get "In Progress" tasks from Linear
IN_PROGRESS=$(linear_query '{issues(filter:{team:{key:{eq:"CAI"}},state:{name:{eq:"In Progress"}}},first:20){nodes{id identifier title}}}')
IP_COUNT=$(echo "$IN_PROGRESS" | jq '[.issues.nodes[]?] | length')
echo "In Progress tasks: $IP_COUNT"

# 3. Check each "In Progress" task for matching agent
ORPHANED=0
echo "$IN_PROGRESS" | jq -c '.issues.nodes[]?' 2>/dev/null | while read -r task; do
  id=$(echo "$task" | jq -r '.id')
  identifier=$(echo "$task" | jq -r '.identifier')
  title=$(echo "$task" | jq -r '.title')
  
  # Check if this task has an active agent
  has_agent=false
  if echo "$ACTIVE_TASK_IDS" | grep -q "^${identifier}$" 2>/dev/null; then
    has_agent=true
  fi
  
  if [ "$has_agent" = true ]; then
    echo "  ✅ $identifier: agent active — $title"
  else
    echo "  ❌ $identifier: NO AGENT — moving to Todo — $title"
    update_status "$id" "Todo"
    add_comment "$id" "🔄 **Auto-sync**: Moved to Todo — no active sub-agent found. Agent likely died or was killed during gateway restart."
    ORPHANED=$((ORPHANED + 1))
  fi
done

# 4. Summary
echo ""
if [ "$ORPHANED" -gt 0 ]; then
  echo "SYNC: $ORPHANED orphaned tasks moved to Todo"
else
  echo "SYNC: OK — all In Progress tasks have agents (or none in progress)"
fi
