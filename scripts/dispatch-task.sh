#!/bin/bash
# dispatch-task.sh — ONE command to create Linear task + spawn agent + sync everything
#
# Usage: dispatch-task.sh --title "Fix X" --description "Details..." [--label bug] [--project "Anton Resiliência 24/7"] [--timeout 25] [--model claude-sonnet-4-6] [--cwd /path]
#
# What it does:
# 1. Creates Linear task in CAI team (Todo)
# 2. Spawns agent via spawn-agent.sh (moves to In Progress)
# 3. Agent auto-logs to Linear via CLAUDE.md instructions
# 4. On completion, watchdog detects and updates status
#
# Anton should use ONLY this to dispatch work. No manual Linear API calls needed.
set -euo pipefail

source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null
source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null

SPAWNER="/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
STATUS_CHECK="/Users/fonsecabc/.openclaw/workspace/scripts/agent-status.sh"

TITLE="" DESCRIPTION="" LABEL="" PROJECT="" TIMEOUT=25 MODEL="" CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --desc)        DESCRIPTION="$2"; shift 2 ;;
    --label)       LABEL="$2"; shift 2 ;;
    --project)     PROJECT="$2"; shift 2 ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --cwd)         CWD="$2"; shift 2 ;;
    -*)            echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)             # Treat bare arg as description if title already set
                   if [ -n "$TITLE" ] && [ -z "$DESCRIPTION" ]; then DESCRIPTION="$1"; fi; shift ;;
  esac
done

[ -z "$TITLE" ] && { echo "ERROR: --title required" >&2; exit 1; }
[ -z "$DESCRIPTION" ] && DESCRIPTION="$TITLE"

# --- Step 1: Create Linear task ---
echo "[dispatch] Creating Linear task: $TITLE"

# Build label filter with auto-classification
LABEL_IDS=()

# Auto-classify based on title + description
AUTO_LABELS=$(bash /Users/fonsecabc/.openclaw/workspace/scripts/classify-task.sh "$TITLE" "$DESCRIPTION" 2>/dev/null || echo "")
if [ -n "$AUTO_LABELS" ]; then
  for label_id in $AUTO_LABELS; do
    LABEL_IDS+=("$label_id")
  done
fi

# Add manual label if provided
if [ -n "$LABEL" ]; then
  MANUAL_LABEL_ID=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"query{issueLabels(filter:{team:{key:{eq:\\\"CAI\\\"}},name:{eq:\\\"$LABEL\\\"}},first:1){nodes{id}}}\"}" \
    2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueLabels',{}).get('nodes',[{}])[0].get('id',''))" 2>/dev/null)
  [ -n "$MANUAL_LABEL_ID" ] && LABEL_IDS+=("$MANUAL_LABEL_ID")
fi

# Deduplicate and build mutation
LABEL_MUTATION=""
if [ ${#LABEL_IDS[@]} -gt 0 ]; then
  UNIQUE_LABELS=$(printf '%s\n' "${LABEL_IDS[@]}" | sort -u)
  LABEL_JSON=$(echo "$UNIQUE_LABELS" | tr '\n' ',' | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g')
  LABEL_MUTATION=",labelIds:[$LABEL_JSON]"
fi

# Build project filter
PROJECT_MUTATION=""
if [ -n "$PROJECT" ]; then
  PROJECT_ID=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"query{projects(filter:{name:{eq:\\\"$PROJECT\\\"}},first:1){nodes{id}}}\"}" \
    2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('projects',{}).get('nodes',[{}])[0].get('id',''))" 2>/dev/null)
  [ -n "$PROJECT_ID" ] && PROJECT_MUTATION=",projectId:\"$PROJECT_ID\""
fi

# Get CAI team ID and Todo state ID
TEAM_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{teams(filter:{key:{eq:\"AUTO\"}},first:1){nodes{id}}}"}' \
  2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['teams']['nodes'][0]['id'])" 2>/dev/null)

TODO_STATE_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{workflowStates(filter:{name:{eq:\"Todo\"},team:{key:{eq:\"AUTO\"}}},first:1){nodes{id}}}"}' \
  2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['workflowStates']['nodes'][0]['id'])" 2>/dev/null)

# Escape description for GraphQL
ESCAPED_DESC=$(echo "$DESCRIPTION" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
ESCAPED_TITLE=$(echo "$TITLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")

# Create the issue
RESULT=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"mutation{issueCreate(input:{teamId:\\\"$TEAM_ID\\\",title:\\\"$ESCAPED_TITLE\\\",description:\\\"$ESCAPED_DESC\\\",stateId:\\\"$TODO_STATE_ID\\\"$LABEL_MUTATION$PROJECT_MUTATION}){success issue{identifier title}}}\"}" \
  2>/dev/null)

TASK_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueCreate',{}).get('issue',{}).get('identifier',''))" 2>/dev/null)

if [ -z "$TASK_ID" ]; then
  echo "ERROR: Failed to create Linear task" >&2
  echo "$RESULT" >&2
  exit 1
fi

echo "[dispatch] Created $TASK_ID: $TITLE"

# --- Step 2: Spawn agent ---
SPAWN_ARGS="--task $TASK_ID --label $(echo "$TITLE" | tr ' ' '-' | cut -c1-30) --timeout $TIMEOUT --source dispatch"
[ -n "$MODEL" ] && SPAWN_ARGS="$SPAWN_ARGS --model $MODEL"
[ -n "$CWD" ] && SPAWN_ARGS="$SPAWN_ARGS --cwd $CWD"

echo "[dispatch] Spawning agent for $TASK_ID..."
SPAWN_OUTPUT=$(bash "$SPAWNER" $SPAWN_ARGS "$DESCRIPTION" 2>&1)
SPAWN_EXIT=$?

if [ $SPAWN_EXIT -ne 0 ]; then
  echo "ERROR: Spawn failed for $TASK_ID" >&2
  echo "$SPAWN_OUTPUT" >&2
  # Mark as blocked in Linear
  bash /Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh "$TASK_ID" "Spawn failed: $SPAWN_OUTPUT" blocked 2>/dev/null || true
  exit 1
fi

AGENT_PID=$(echo "$SPAWN_OUTPUT" | tail -1)
echo "[dispatch] $TASK_ID spawned (PID=$AGENT_PID)"

echo ""
echo "✅ $TASK_ID dispatched"
echo "   Title: $TITLE"
echo "   PID: $AGENT_PID"
echo "   Timeout: ${TIMEOUT}min"
echo "   Monitor: bash scripts/agent-peek.sh $TASK_ID follow"
