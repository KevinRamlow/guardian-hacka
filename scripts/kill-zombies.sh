#!/bin/bash
# Kill Zombies — Kill claude processes older than MAX_AGE_MIN
set -euo pipefail

MAX_AGE_MIN="${1:-30}"  # Default 30 min
LOG="/root/.openclaw/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*" >> "$LOG"; echo "$*"; }

CLAUDE_PIDS=$(pgrep -x claude 2>/dev/null || true)
[ -z "$CLAUDE_PIDS" ] && { echo "No claude processes running"; exit 0; }

KILLED=0
for pid in $CLAUDE_PIDS; do
    age_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
    age_min=$((age_s / 60))
    if [ "$age_min" -gt "$MAX_AGE_MIN" ]; then
        # Kill the process and its bridge
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo "")
        kill -9 "$pid" 2>/dev/null && log "KILLED zombie: PID $pid (${age_min}min)" || true
        [ -n "$ppid" ] && [ "$ppid" != "1" ] && kill -9 "$ppid" 2>/dev/null || true
        KILLED=$((KILLED + 1))
    fi
done

# Also kill orphan bridge processes with no matching claude process
for bridge_pid in $(pgrep -f "claude-agent-acp" 2>/dev/null || true); do
    # Check if bridge has a child claude process
    has_child=$(pgrep -P "$bridge_pid" -x claude 2>/dev/null || true)
    if [ -z "$has_child" ]; then
        kill -9 "$bridge_pid" 2>/dev/null && log "KILLED orphan bridge: PID $bridge_pid" || true
        KILLED=$((KILLED + 1))
    fi
done

# Clean stale session store entries
if [ -f "/root/.openclaw/agents/claude/sessions/sessions.json" ]; then
    python3 -c "
import json, time
f = '/root/.openclaw/agents/claude/sessions/sessions.json'
try:
    d = json.load(open(f))
    now = int(time.time() * 1000)
    stale_ms = $MAX_AGE_MIN * 60 * 1000
    cleaned = {k:v for k,v in d.items() if (now - v.get('updatedAt',0)) < stale_ms}
    removed = len(d) - len(cleaned)
    if removed > 0:
        json.dump(cleaned, open(f, 'w'))
        print(f'Cleaned {removed} stale session entries')
except Exception as e:
    print(f'Session cleanup error: {e}')
" 2>/dev/null
fi

echo "Killed $KILLED zombie/orphan processes"
