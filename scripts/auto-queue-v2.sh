#!/bin/bash
# Auto-Queue v2 — Fetches Linear Todo tasks and spawns agents via spawn-agent.sh
# Uses agent-registry.sh for capacity checks (not pgrep or session store)
# Runs every 5 min via cron
set -euo pipefail

LOCKFILE="/tmp/auto-queue-v2.lock"
REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
SPAWNER="/root/.openclaw/workspace/scripts/spawn-agent.sh"
CONFIG="/root/.openclaw/workspace/config/auto-queue.json"

# Source Linear API key
source /root/.openclaw/workspace/.env.linear 2>/dev/null || true

# Lockfile
exec 200>"$LOCKFILE"
flock -n 200 || { echo "[$(date -u +%H:%M)] Skipped: already running"; exit 0; }

# Check if enabled
ENABLED=$(python3 -c "import json; print(json.load(open('$CONFIG'))['enabled'])" 2>/dev/null || echo "true")
[ "$ENABLED" = "False" ] && exit 0

# Check available slots via registry
SLOTS=$(bash "$REGISTRY" slots)
echo "[$(date -u +%H:%M)] Available slots: $SLOTS"

if [ "$SLOTS" -le 0 ]; then
  echo "[$(date -u +%H:%M)] At capacity, skipping"
  exit 0
fi

# Fetch Todo tasks from Linear (CAI team)
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

# Spawn agents for available tasks
echo "$TODOS" | python3 -c "
import json, sys, subprocess, os

d = json.load(sys.stdin)
nodes = d.get('data', {}).get('issues', {}).get('nodes', [])
slots = $SLOTS
spawned = 0

REGISTRY = '/root/.openclaw/workspace/scripts/agent-registry.sh'
SPAWNER = '/root/.openclaw/workspace/scripts/spawn-agent.sh'

for n in nodes:
    if spawned >= slots:
        break

    task_id = n['identifier']
    title = n['title']
    desc = (n.get('description') or '')[:1000]

    # Check if already running
    result = subprocess.run(['bash', REGISTRY, 'has', task_id], capture_output=True, text=True)
    status = result.stdout.strip()
    if status == 'yes':
        print(f'  SKIP: {task_id} already running')
        continue

    # Build task text
    task_text = f'''## Task Context
- **Linear Task:** {task_id}
- **Timeout:** 25 minutes

## Task
**{title}**

{desc}
'''

    # Write task file
    task_file = f'/root/.openclaw/tasks/spawn-tasks/{task_id}.md'
    os.makedirs('/root/.openclaw/tasks/spawn-tasks', exist_ok=True)
    with open(task_file, 'w') as f:
        f.write(task_text)

    # Spawn
    print(f'  SPAWN: {task_id} - {title}')
    result = subprocess.run(
        ['bash', SPAWNER, '--task', task_id, '--label', f'{task_id}-{title[:30].replace(\" \", \"-\").lower()}',
         '--timeout', '25', '--source', 'auto-queue', '--file', task_file],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        print(f'    OK: {result.stdout.strip().split(chr(10))[-1]}')
        spawned += 1
    else:
        print(f'    FAIL: {result.stderr.strip()}')

print(f'\nSpawned {spawned} agents')
" 2>/dev/null

echo "[$(date -u +%H:%M)] Queue check complete"
