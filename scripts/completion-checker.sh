#!/bin/bash
# Completion Checker — detects finished/stale agents, updates Linear, notifies Slack
set -euo pipefail

LOCKFILE="/tmp/completion-checker.lock"
STATE_FILE="/root/.openclaw/tasks/agent-states.json"
SESSIONS_DIR="/root/.openclaw/agents/claude/sessions/sessions.json"

source /root/.openclaw/workspace/.env.linear 2>/dev/null || true

exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# Initialize state file if missing
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

python3 << 'PYEOF'
import json, time, os, subprocess

SESSIONS_FILE = "/root/.openclaw/agents/claude/sessions/sessions.json"
STATE_FILE = "/root/.openclaw/tasks/agent-states.json"
SPAWN_DIR = "/root/.openclaw/tasks/spawn-queue"
LINEAR_KEY = os.environ.get("LINEAR_API_KEY", "")
TIMEOUT_MS = 30 * 60 * 1000  # 30 min
STALE_MS = 15 * 60 * 1000    # 15 min no update = likely done

now = int(time.time() * 1000)

# Load current sessions
try:
    sessions = json.load(open(SESSIONS_FILE))
except:
    sessions = {}

# Load previous state
try:
    prev_state = json.load(open(STATE_FILE))
except:
    prev_state = {}

new_state = {}
completions = []
timeouts = []

for key, s in sessions.items():
    if 'acp' not in key:
        continue
    
    label = s.get('label', key.split(':')[-1])
    updated = s.get('updatedAt', 0)
    age_ms = now - updated
    tokens = s.get('totalTokens', 0)
    
    # Track in new state
    new_state[key] = {
        'label': label,
        'updatedAt': updated,
        'tokens': tokens,
        'lastSeen': now
    }
    
    prev = prev_state.get(key, {})
    was_active = prev.get('updatedAt', 0) > (now - STALE_MS * 2)
    
    # Detect completion: was recently active, now stale
    if was_active and age_ms > STALE_MS and age_ms < 86400000:
        if key not in [c['key'] for c in completions]:
            completions.append({
                'key': key,
                'label': label,
                'tokens': tokens,
                'runtime_min': round(age_ms / 60000)
            })
    
    # Detect timeout
    if age_ms > TIMEOUT_MS and age_ms < STALE_MS * 4:
        if prev.get('timed_out') != True:
            timeouts.append({'key': key, 'label': label, 'age_min': round(age_ms / 60000)})
            new_state[key]['timed_out'] = True

# Save new state
with open(STATE_FILE, 'w') as f:
    json.dump(new_state, f, indent=2)

# Report completions
for c in completions:
    label = c['label']
    tokens = c['tokens']
    runtime = c['runtime_min']
    print(f"✅ Completed: {label} ({runtime}min, {tokens} tokens)")
    
    # Clean spawn queue
    if os.path.exists(SPAWN_DIR):
        for fname in os.listdir(SPAWN_DIR):
            if label and label.lower().replace(' ','-') in fname.lower():
                os.remove(os.path.join(SPAWN_DIR, fname))

# Report timeouts
for t in timeouts:
    print(f"⏱️ Timeout: {t['label']} ({t['age_min']}min)")

if not completions and not timeouts:
    print(f"[{time.strftime('%H:%M', time.gmtime())}] No changes detected")
PYEOF
