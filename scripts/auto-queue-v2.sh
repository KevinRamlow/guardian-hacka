#!/bin/bash
# Auto-Queue v2 — Fetches Linear Todo tasks and spawns agents via spawn-agent.sh
# Uses agent-registry.sh for capacity checks (not pgrep or session store)
# Runs every 5 min via cron
#
# SPAWN CRITERIA (to avoid token waste):
# ✅ Spawn: eval, multi-hypothesis, code implementation, PR review, >20 min work
# ❌ Skip: read/analyze only, quick fixes (<5 min), documentation, data queries
set -euo pipefail

LOCKFILE="/tmp/auto-queue-v2.lock"
REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
SPAWNER="/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
CONFIG="/Users/fonsecabc/.openclaw/workspace/config/auto-queue.json"

# Source Linear API key
source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || true

# Lockfile
exec 200>"$LOCKFILE"
flock -n 200 || { echo "[$(date -u +%H:%M)] Skipped: already running"; exit 0; }

# Check if enabled
ENABLED=$(python3 -c "import json; print(json.load(open('$CONFIG'))['enabled'])" 2>/dev/null || echo "true")
[ "$ENABLED" = "False" ] && exit 0

# Check budget before spawning
BUDGET_STATUS=$(python3 -c "import json; print(json.load(open('/Users/fonsecabc/.openclaw/workspace/self-improvement/loop/budget-status.json')).get('status','ok'))" 2>/dev/null || echo "ok")
if [ "$BUDGET_STATUS" = "over_monthly_limit" ] || [ "$BUDGET_STATUS" = "critical" ]; then
  echo "[$(date -u +%H:%M)] Budget $BUDGET_STATUS — skipping spawn"
  exit 0
fi

# Check available slots via registry
SLOTS=$(bash "$REGISTRY" slots)
echo "[$(date -u +%H:%M)] Available slots: $SLOTS"

if [ "$SLOTS" -le 0 ]; then
  echo "[$(date -u +%H:%M)] At capacity, skipping"
  exit 0
fi

# Fetch Todo tasks from Linear (CAI team) WITH LABELS
TODOS=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issues(filter:{team:{key:{eq:\"AUT\"}},state:{name:{eq:\"Todo\"}}},first:5,orderBy:updatedAt){nodes{identifier title description labels{nodes{name}}}}}"}' 2>/dev/null)

TASK_COUNT=$(echo "$TODOS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('issues',{}).get('nodes',[])))" 2>/dev/null || echo "0")

echo "[$(date -u +%H:%M)] Todo tasks: $TASK_COUNT, slots: $SLOTS"

if [ "$TASK_COUNT" -eq 0 ]; then
  echo "[$(date -u +%H:%M)] No tasks in queue"
  exit 0
fi

# Spawn agents for available tasks (with spawn criteria filters)
TMPFILE=$(mktemp)
echo "$TODOS" > "$TMPFILE"
python3 <<EOF
import json, sys, subprocess, os, re

d = json.load(open('$TMPFILE'))
nodes = d.get('data', {}).get('issues', {}).get('nodes', [])
slots = $SLOTS
spawned = 0
skipped = 0

REGISTRY = '/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh'
SPAWNER = '/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh'

# Spawn criteria heuristics
def should_spawn(task_id, title, desc, labels):
    """
    Return (should_spawn: bool, reason: str)
    
    ✅ Spawn when:
    - Has 'agent-required' label
    - Title/desc mentions: eval, hypothesis, implement, PR review, refactor, test
    - Mentions time estimate >20 min
    
    ❌ Skip when:
    - Has 'quick-win' or 'manual' label
    - Title starts with: Read, Analyze, Document, Update (without implement)
    - Mentions: "5 min", "quick", "just read", "only analyze"
    - Analysis-only tasks (no code changes)
    """
    title_lower = title.lower()
    desc_lower = (desc or '').lower()
    label_names = [l for l in labels]
    
    # Explicit labels
    if 'agent-required' in label_names:
        return True, 'label:agent-required'
    if 'quick-win' in label_names or 'manual' in label_names:
        return False, 'label:quick-win/manual'
    
    # Skip quick/read-only tasks
    skip_patterns = [
        r'\b(just|only)\s+(read|analyze|document)',
        r'\b(quick|fast|5\s*min|simple)\b',
        r'^(read|analyze|document|review)\s+(?!and\s+(implement|fix|test))',
    ]
    for pattern in skip_patterns:
        if re.search(pattern, title_lower) or re.search(pattern, desc_lower):
            return False, f'pattern:{pattern[:20]}'
    
    # Spawn for implementation work
    spawn_keywords = ['eval', 'hypothesis', 'implement', 'fix', 'refactor', 'test', 'pr review', 'build', 'create', 'deploy', 'feature', 'improve', 'optimize', 'migrate', 'resilience', 'investigation', 'investigate', 'budget', 'strategy', 'fallback']
    for kw in spawn_keywords:
        if kw in title_lower or kw in desc_lower:
            return True, f'keyword:{kw}'
    
    # Default: skip (conservative)
    return False, 'default:no-spawn-keyword'

for n in nodes:
    if spawned >= slots:
        break

    task_id = n['identifier']
    title = n['title']
    desc = (n.get('description') or '')[:1000]
    labels = [l['name'] for l in n.get('labels', {}).get('nodes', [])]

    # Check if already running
    result = subprocess.run(['bash', REGISTRY, 'has', task_id], capture_output=True, text=True)
    status = result.stdout.strip()
    if status == 'yes':
        print(f'  SKIP: {task_id} already running')
        skipped += 1
        continue

    # Apply spawn criteria
    should, reason = should_spawn(task_id, title, desc, labels)
    if not should:
        print(f'  SKIP: {task_id} - {reason} - "{title[:40]}"')
        skipped += 1
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
    task_file = f'/Users/fonsecabc/.openclaw/tasks/spawn-tasks/{task_id}.md'
    os.makedirs('/Users/fonsecabc/.openclaw/tasks/spawn-tasks', exist_ok=True)
    with open(task_file, 'w') as f:
        f.write(task_text)

    # Spawn
    print(f'  SPAWN: {task_id} ({reason}) - {title}')
    # Sanitize label: remove apostrophes, quotes, and special chars
    safe_label = re.sub(r"['\"]", '', title[:30].replace(" ", "-").lower())
    safe_label = re.sub(r'[^a-z0-9\-]', '', safe_label)
    result = subprocess.run(
        ['bash', SPAWNER, '--task', task_id, '--label', f'{task_id}-{safe_label}',
         '--timeout', '25', '--source', 'auto-queue', '--file', task_file],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        last_line = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ''
        print(f'    OK: {last_line}')
        spawned += 1
    else:
        # Log both stdout and stderr for debugging
        print(f'    FAIL: returncode={result.returncode}')
        if result.stderr:
            print(f'      stderr: {result.stderr.strip()[:200]}')
        if result.stdout:
            print(f'      stdout: {result.stdout.strip()[:200]}')

print(f'\nSpawned {spawned} agents, skipped {skipped}')
EOF

rm -f "$TMPFILE"
echo "[$(date -u +%H:%M)] Queue check complete"
