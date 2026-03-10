#!/bin/bash
# dispatcher.sh — Create Linear task + register in state + spawn agent
# Replaces dispatch-task.sh. Uses task-manager.sh as the single source of truth.
#
# Usage: dispatcher.sh --title "Fix X" --desc "Details" [--label Bug] [--timeout 25]
#        [--role developer|reviewer|architect|guardian-tuner|debugger]
#        [--mode yolo|interactive]
#
set -euo pipefail

source ${OPENCLAW_HOME:-$HOME/.openclaw}/.env 2>/dev/null || true

TASK_MGR="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/task-manager.sh"
SPAWNER="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/spawn-agent.sh"
CLASSIFY="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/classify-task.sh"

TITLE="" DESCRIPTION="" LABEL="" PROJECT="" TIMEOUT=25 ROLE="" MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --desc)        DESCRIPTION="$2"; shift 2 ;;
    --label)       LABEL="$2"; shift 2 ;;
    --project)     PROJECT="$2"; shift 2 ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    --role)        ROLE="$2"; shift 2 ;;
    --mode)        MODE="$2"; shift 2 ;;
    -*)            echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)             [ -n "$TITLE" ] && [ -z "$DESCRIPTION" ] && DESCRIPTION="$1"; shift ;;
  esac
done

[ -z "$TITLE" ] && { echo "ERROR: --title required" >&2; exit 1; }
[ -z "$DESCRIPTION" ] && DESCRIPTION="$TITLE"

# --- Pre-flight: guardrails check ---
GUARDRAILS="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/guardrails.sh"
if [ -f "$GUARDRAILS" ]; then
  if ! bash "$GUARDRAILS" --check state 2>/dev/null; then
    echo "ERROR: Guardrails check failed — state.json may be corrupt. Fix before dispatching." >&2
    exit 1
  fi
fi

# --- Step 1: Create Linear task ---
echo "[dispatch] Creating Linear task: $TITLE"

LABEL_IDS=()
# Disabled: AUTO team has no labels yet
# AUTO_LABELS=$(bash "$CLASSIFY" "$TITLE" "$DESCRIPTION" 2>/dev/null || echo "")
# if [ -n "$AUTO_LABELS" ]; then
#   for label_id in $AUTO_LABELS; do
#     LABEL_IDS+=("$label_id")
#   done
# fi

if [ -n "$LABEL" ]; then
  MANUAL_LABEL_ID=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"query{issueLabels(filter:{team:{key:{eq:\\\"AUTO\\\"}},name:{eq:\\\"$LABEL\\\"}},first:1){nodes{id}}}\"}" \
    2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueLabels',{}).get('nodes',[{}])[0].get('id',''))" 2>/dev/null)
  [ -n "$MANUAL_LABEL_ID" ] && LABEL_IDS+=("$MANUAL_LABEL_ID")
fi

LABEL_MUTATION=""
if [ ${#LABEL_IDS[@]} -gt 0 ]; then
  UNIQUE_LABELS=$(printf '%s\n' "${LABEL_IDS[@]}" | sort -u)
  LABEL_JSON=$(echo "$UNIQUE_LABELS" | tr '\n' ',' | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g')
  LABEL_MUTATION=",labelIds:[$LABEL_JSON]"
fi

PROJECT_MUTATION=""
if [ -n "$PROJECT" ]; then
  PROJECT_ID=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"query{projects(filter:{name:{eq:\\\"$PROJECT\\\"}},first:1){nodes{id}}}\"}" \
    2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('projects',{}).get('nodes',[{}])[0].get('id',''))" 2>/dev/null)
  [ -n "$PROJECT_ID" ] && PROJECT_MUTATION=",projectId:\"$PROJECT_ID\""
fi

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

RESULT=$(python3 << PYEOF
import json, sys, subprocess
title = """$TITLE"""
desc = """$DESCRIPTION"""
team_id = "$TEAM_ID"
state_id = "$TODO_STATE_ID"
label_mut = "$LABEL_MUTATION"
project_mut = "$PROJECT_MUTATION"

mutation = f'mutation{{issueCreate(input:{{teamId:"{team_id}",title:{json.dumps(title)},description:{json.dumps(desc)},stateId:"{state_id}"{label_mut}{project_mut}}}){{success issue{{identifier title}}}}}}'
payload = json.dumps({"query": mutation})

result = subprocess.run(
    ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
     "-H", "Authorization: $LINEAR_API_KEY",
     "-H", "Content-Type: application/json",
     "-d", payload],
    capture_output=True, text=True
)
print(result.stdout)
PYEOF
)

TASK_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueCreate',{}).get('issue',{}).get('identifier',''))" 2>/dev/null)

if [ -z "$TASK_ID" ]; then
  echo "ERROR: Failed to create Linear task" >&2
  echo "$RESULT" >&2
  exit 1
fi
echo "[dispatch] Created $TASK_ID: $TITLE"

# --- Step 2: Register in unified state ---
bash "$TASK_MGR" create --task "$TASK_ID" --label "$(echo "$TITLE" | tr ' ' '-' | cut -c1-40)" --timeout "$TIMEOUT"

# --- Step 3: Spawn agent ---
SPAWN_ARGS="--task $TASK_ID --label $(echo "$TITLE" | tr ' ' '-' | cut -c1-30) --timeout $TIMEOUT --source dispatch"
[ -n "$ROLE" ] && SPAWN_ARGS="$SPAWN_ARGS --role $ROLE"
[ -n "$MODE" ] && SPAWN_ARGS="$SPAWN_ARGS --mode $MODE"

echo "[dispatch] Spawning agent for $TASK_ID..."
SPAWN_OUTPUT=$(bash "$SPAWNER" $SPAWN_ARGS "$DESCRIPTION" 2>&1)
SPAWN_EXIT=$?

if [ $SPAWN_EXIT -ne 0 ]; then
  echo "ERROR: Spawn failed for $TASK_ID" >&2
  echo "$SPAWN_OUTPUT" >&2
  bash "$TASK_MGR" transition "$TASK_ID" blocked 2>/dev/null || true
  bash ${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/task-manager/scripts/linear-log.sh "$TASK_ID" "Spawn failed: $SPAWN_OUTPUT" blocked 2>/dev/null || true
  exit 1
fi

AGENT_PID=$(echo "$SPAWN_OUTPUT" | tail -1)
echo "[dispatch] $TASK_ID spawned (PID=$AGENT_PID)"
echo ""
echo "✅ $TASK_ID dispatched"
echo "   Title: $TITLE"
echo "   PID: $AGENT_PID"
echo "   Timeout: ${TIMEOUT}min"
echo "   Monitor: bash scripts/task-manager.sh list"
