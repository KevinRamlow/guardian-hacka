#!/bin/bash
# linear-watcher.sh — Poll Linear GAS team for Todo/Backlog tasks (fresh dispatch)
#                     and Blocked tasks (retry up to MAX_RETRIES).
#
# Flow per card:
#   Todo/Backlog  → dispatch PM agent (dispatcher moves card to In Progress on register)
#   Blocked       → retry if retries < MAX_RETRIES, else → Done
#   In Progress   → skip (agent is running; dispatcher owns Done/Blocked transitions)
#
# Designed to be called from HEARTBEAT.md as Priority 0.
# Safe to call multiple times — idempotent via task-manager dedup.
#
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME}"
export OPENCLAW_HOME
OC_HOME="$OPENCLAW_HOME/.openclaw"
TASK_MGR="$OC_HOME/workspace/scripts/task-manager.sh"
DISPATCHER="$OC_HOME/workspace/scripts/dispatcher.sh"
MASTER_LOG="$OC_HOME/tasks/agent-logs/master.log"
LINEAR_API="https://api.linear.app/graphql"
TEAM_KEY="GAS"
MAX_RETRIES="${MAX_RETRIES:-3}"

source "$OC_HOME/.env" 2>/dev/null || true

log() {
  local level="$1"; local msg="$2"
  mkdir -p "$(dirname "$MASTER_LOG")"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$level] [linear-watcher] $msg" | tee -a "$MASTER_LOG" >&2
}

gql() {
  local query="$1"
  curl -s -X POST "$LINEAR_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "{\"query\": \"$query\"}"
}

if [ -z "${LINEAR_API_KEY:-}" ]; then
  log ERROR "LINEAR_API_KEY not set — skipping"
  exit 0
fi

# ── Fetch Todo/Backlog (fresh) + Blocked (retry) tasks ──
# In Progress is excluded — dispatcher owns that state.
TODO_RESPONSE=$(gql "{ issues(filter: { team: { key: { eq: \\\"$TEAM_KEY\\\" } }, or: [ { state: { type: { in: [\\\"backlog\\\", \\\"unstarted\\\"] } } }, { state: { name: { eq: \\\"Blocked\\\" } } } ] }, first: 20, orderBy: createdAt) { nodes { id identifier title description priority priorityLabel state { name type } labels { nodes { name } } assignee { name } createdAt } } }")

TASK_COUNT=$(echo "$TODO_RESPONSE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
nodes = d.get('data', {}).get('issues', {}).get('nodes', [])
print(len(nodes))
" 2>/dev/null || echo 0)

log INFO "Fetched $TASK_COUNT candidate tasks from Linear team $TEAM_KEY"

if [ "$TASK_COUNT" -eq 0 ]; then
  exit 0
fi

DONE_ID=$(gql "{ workflowStates(filter: { team: { key: { eq: \\\"$TEAM_KEY\\\" } }, type: { eq: \\\"completed\\\" } }) { nodes { id } } }" \
  | python3 -c "import json,sys; nodes=json.load(sys.stdin).get('data',{}).get('workflowStates',{}).get('nodes',[]); print(nodes[0]['id'] if nodes else '')" 2>/dev/null || echo "")

if [ -z "$DONE_ID" ]; then
  log WARN "Could not resolve 'Done' state for team $TEAM_KEY — completed card updates will be skipped"
fi

# ── Check available slots before processing ──
SLOTS=$(bash "$TASK_MGR" slots 2>/dev/null || echo 0)
if [ "$SLOTS" -le 0 ]; then
  log INFO "No slots available — deferring Linear tasks"
  exit 0
fi

# ── Helper: read a numeric field from state.json for a task ──
get_task_field() {
  local task_id="$1" field="$2" default="${3:-0}"
  python3 -c "
import json
try:
  d = json.load(open('$OC_HOME/tasks/state.json'))
  print(d['tasks'].get('$task_id', {}).get('$field', $default))
except Exception:
  print($default)
" 2>/dev/null || echo "$default"
}

# ── Helper: mark card Done on Linear ──
mark_linear_done() {
  local issue_uuid="$1" issue_id="$2" reason="$3"
  if [ -n "$DONE_ID" ]; then
    UPDATE_RESULT=$(gql "mutation { issueUpdate(id: \\\"$issue_uuid\\\", input: { stateId: \\\"$DONE_ID\\\" }) { success issue { identifier state { name } } } }" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); ok=d.get('data',{}).get('issueUpdate',{}).get('success',False); print('ok' if ok else 'failed')" 2>/dev/null || echo "error")
    log INFO "Linear $issue_id → Done ($reason, $UPDATE_RESULT)"
  else
    log INFO "Skipping Linear Done update for $issue_id — Done state ID not resolved"
  fi
}

# ── Process each task ──
DISPATCHED=0

while IFS= read -r TASK_JSON; do
  ISSUE_ID=$(echo    "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['identifier'])")
  ISSUE_UUID=$(echo  "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  STATE_NAME=$(echo  "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state',{}).get('name',''))")
  TITLE=$(echo       "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title','') or '')")
  DESCRIPTION=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description','') or '')")
  PRIORITY=$(echo    "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('priorityLabel','None') or 'None')")
  LABELS=$(echo      "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); print(', '.join(l['name'] for l in t.get('labels',{}).get('nodes',[])))")
  ASSIGNEE=$(echo    "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin); a=t.get('assignee'); print(a['name'] if a else 'unassigned')")

  HAS=$(bash "$TASK_MGR" has "$ISSUE_ID" 2>/dev/null || echo "no")
  IS_RETRY=0

  if [ "$STATE_NAME" = "Blocked" ]; then
    # ── Retry path ──
    RETRIES=$(get_task_field "$ISSUE_ID" retries 0)
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
      log INFO "$ISSUE_ID blocked — max retries exhausted ($RETRIES/$MAX_RETRIES)"
      mark_linear_done "$ISSUE_UUID" "$ISSUE_ID" "max retries exhausted"
      continue
    fi
    log INFO "$ISSUE_ID blocked — scheduling retry $((RETRIES + 1))/$MAX_RETRIES"
    # Reset task-manager if it still thinks the agent is running
    if [ "$HAS" != "no" ] && [ "$HAS" != "completed" ]; then
      bash "$TASK_MGR" transition "$ISSUE_ID" failed --exit-code 1 2>/dev/null || true
    fi
    bash "$TASK_MGR" set-field "$ISSUE_ID" retries "$((RETRIES + 1))" 2>/dev/null || true
    IS_RETRY=1
    # fall through to dispatch
  else
    # ── Fresh dispatch path (Todo / Backlog) ──
    if [ "$HAS" = "completed" ]; then
      mark_linear_done "$ISSUE_UUID" "$ISSUE_ID" "already processed"
      continue
    fi
    if [ "$HAS" = "yes" ] || [ "$HAS" = "eval_running" ]; then
      log INFO "Skipping $ISSUE_ID — already running (state=$HAS)"
      continue
    fi
  fi

  # Re-check slots per iteration
  SLOTS=$(bash "$TASK_MGR" slots 2>/dev/null || echo 0)
  if [ "$SLOTS" -le 0 ]; then
    log INFO "No more slots — stopping after $DISPATCHED dispatched"
    break
  fi

  # ── Build task context for PM agent ──
  SAFE_TITLE=$(echo "$TITLE" | head -c 200)
  SAFE_DESC=$(echo "$DESCRIPTION" | head -c 1000)

  TASK_BODY="# Linear Task: $ISSUE_ID
Title: $SAFE_TITLE
Priority: $PRIORITY
Labels: $LABELS
Assignee: $ASSIGNEE

## Description
$SAFE_DESC

## Instructions
Analyze this task. Use the eval metrics and per-classification breakdown to build a detailed improvement plan. Dispatch Analyst with specific forensics context."

  # ── Dispatch PM agent ──
  FORCE_FLAG=""
  if [ "$IS_RETRY" = "1" ] || [ "$(bash "$TASK_MGR" has "$ISSUE_ID" 2>/dev/null || echo no)" = "no" ]; then
    FORCE_FLAG="--force"
  fi

  log INFO "Dispatching PM agent for $ISSUE_ID (title=$SAFE_TITLE${IS_RETRY:+ retry=true}${FORCE_FLAG:+ force=true})"

  DISPATCH_OUTPUT=$(bash "$DISPATCHER" \
    --task "$ISSUE_ID" \
    --label "$(echo "$SAFE_TITLE" | tr ' ' '-' | cut -c1-50)" \
    --role pm \
    --timeout 20 \
    $FORCE_FLAG \
    "$TASK_BODY" 2>&1)
  DISPATCH_EXIT=$?

  if [ $DISPATCH_EXIT -ne 0 ]; then
    if echo "$DISPATCH_OUTPUT" | grep -q "already running"; then
      log INFO "Skipping $ISSUE_ID — agent already running"
    else
      log ERROR "Dispatch failed for $ISSUE_ID: $(echo "$DISPATCH_OUTPUT" | tail -3)"
    fi
    continue
  fi

  log INFO "PM agent dispatched for $ISSUE_ID"
  DISPATCHED=$((DISPATCHED + 1))

done < <(echo "$TODO_RESPONSE" | python3 -c "
import json, sys
nodes = json.load(sys.stdin).get('data', {}).get('issues', {}).get('nodes', [])
for t in nodes:
    print(json.dumps(t))
")

log INFO "Linear watcher cycle complete (dispatched=$DISPATCHED)"
