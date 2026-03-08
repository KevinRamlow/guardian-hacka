#!/bin/bash
# Backlog Generator — Creates new tasks when Linear Todo is empty
# Called by auto-queue-v2.sh when no tasks remain, or standalone
# Generates tasks from: agent output review, Guardian improvements, infra gaps, proactive analysis
set -euo pipefail

source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || true

REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
MIN_BACKLOG=3  # Generate tasks if fewer than this many Todos exist

# Count current Todo tasks
TODO_COUNT=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issues(filter:{team:{key:{eq:\"AUT\"}},state:{name:{eq:\"Todo\"}}},first:1){nodes{identifier}}}"}' 2>/dev/null | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('issues',{}).get('nodes',[])))" 2>/dev/null || echo "0")

echo "[$(date -u +%H:%M)] Todo count: $TODO_COUNT (min: $MIN_BACKLOG)"

if [ "$TODO_COUNT" -ge "$MIN_BACKLOG" ]; then
  echo "[$(date -u +%H:%M)] Backlog sufficient, skipping generation"
  exit 0
fi

NEEDED=$((MIN_BACKLOG - TODO_COUNT))
echo "[$(date -u +%H:%M)] Need to generate $NEEDED tasks"
echo "GENERATE_NEEDED=$NEEDED"
