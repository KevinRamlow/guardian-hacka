#!/bin/bash
# Auto-Queue Pipeline — picks up Linear tasks and spawns agents
# Runs every 5 min via cron
set -euo pipefail

LOCKFILE="/tmp/auto-queue.lock"
LOGFILE="/root/.openclaw/tasks/queue-log.md"
STATE_FILE="/root/.openclaw/tasks/queue-state.json"
CONFIG="/root/.openclaw/workspace/config/auto-queue.json"
SESSIONS_DIR="/root/.openclaw/agents/claude/sessions/sessions.json"

# Source Linear API key
source /root/.openclaw/workspace/.env.linear 2>/dev/null || true

# Lockfile — prevent concurrent runs
exec 200>"$LOCKFILE"
flock -n 200 || { echo "[$(date -u +%H:%M)] Skipped: already running"; exit 0; }

# Check if enabled
ENABLED=$(python3 -c "import json; print(json.load(open('$CONFIG'))['enabled'])" 2>/dev/null || echo "true")
[ "$ENABLED" = "False" ] && exit 0

MAX_CONCURRENT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['maxConcurrent'])" 2>/dev/null || echo "3")

# Count active agents (sessions updated < 15 min ago)
NOW_MS=$(date +%s%3N)
ACTIVE=0
if [ -f "$SESSIONS_DIR" ]; then
  ACTIVE=$(python3 -c "
import json, time
now = int(time.time() * 1000)
store = json.load(open('$SESSIONS_DIR'))
active = sum(1 for k,v in store.items() if (now - v.get('updatedAt', 0)) < 900000 and 'acp' in k)
print(active)
" 2>/dev/null || echo "0")
fi

echo "[$(date -u +%H:%M)] Active agents: $ACTIVE / max $MAX_CONCURRENT"

# If at capacity, skip
if [ "$ACTIVE" -ge "$MAX_CONCURRENT" ]; then
  echo "[$(date -u +%H:%M)] At capacity, skipping"
  exit 0
fi

SLOTS=$((MAX_CONCURRENT - ACTIVE))

# Fetch Todo tasks from Linear
TODOS=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issues(filter:{team:{key:{eq:\"CAI\"}},state:{name:{eq:\"Todo\"}}},first:5,orderBy:updatedAt){nodes{identifier title description}}}"}' 2>/dev/null)

TASK_COUNT=$(echo "$TODOS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('issues',{}).get('nodes',[])))" 2>/dev/null || echo "0")

echo "[$(date -u +%H:%M)] Todo tasks: $TASK_COUNT, slots: $SLOTS"

if [ "$TASK_COUNT" -eq 0 ]; then
  echo "[$(date -u +%H:%M)] No tasks in queue"
  exit 0
fi

# Write spawn requests for the main session to pick up
SPAWN_DIR="/root/.openclaw/tasks/spawn-queue"
mkdir -p "$SPAWN_DIR"

echo "$TODOS" | python3 -c "
import json, sys, os
d = json.load(sys.stdin)
nodes = d.get('data',{}).get('issues',{}).get('nodes',[])
slots = $SLOTS
spawn_dir = '$SPAWN_DIR'

for i, n in enumerate(nodes[:slots]):
    task_id = n['identifier']
    title = n['title']
    desc = (n.get('description') or '')[:500]
    
    # Skip if already queued
    qf = os.path.join(spawn_dir, f'{task_id}.json')
    if os.path.exists(qf):
        continue
    
    spawn = {
        'taskId': task_id,
        'title': title,
        'description': desc,
        'status': 'pending',
        'queuedAt': int(__import__('time').time())
    }
    
    with open(qf, 'w') as f:
        json.dump(spawn, f, indent=2)
    
    print(f'Queued: {task_id} — {title}')
" 2>/dev/null

echo "[$(date -u +%H:%M)] Queue check complete"
