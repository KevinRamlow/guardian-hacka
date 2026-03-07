#!/bin/bash
# Agent Monitor — Process-level monitoring for ACP + subagent sessions
# Replaces the broken sessions.json-based monitoring
set -euo pipefail

SESSIONS_FILE="/root/.openclaw/agents/claude/sessions/sessions.json"
LOG="/root/.openclaw/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*" >> "$LOG"; echo "$*"; }

# Count ACTUAL claude processes (not session store entries)
CLAUDE_PIDS=$(pgrep -x claude 2>/dev/null || true)
CLAUDE_COUNT=$(echo "$CLAUDE_PIDS" | grep -c . 2>/dev/null || echo 0)
[ -z "$CLAUDE_PIDS" ] && CLAUDE_COUNT=0

# Count bridge processes
BRIDGE_COUNT=$(pgrep -f "claude-agent-acp" 2>/dev/null | wc -l || echo 0)

# Count subagents via OpenClaw API (the only reliable source for subagent runtime)
# Note: This only works for runtime=subagent, NOT runtime=acp
SUBAGENT_JSON=$(timeout 5 openclaw sessions list --json 2>/dev/null || echo '[]')

echo "=== Agent Monitor Report ==="
echo "Claude processes: $CLAUDE_COUNT (PIDs: ${CLAUDE_PIDS:-none})"
echo "Bridge processes: $BRIDGE_COUNT"

# For each claude process, show age and memory
if [ -n "$CLAUDE_PIDS" ]; then
    echo ""
    echo "Process details:"
    for pid in $CLAUDE_PIDS; do
        age_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "?")
        age_min=$((age_s / 60))
        mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.0fMB", $1/1024}' || echo "?")
        cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ' || echo "?")
        echo "  PID=$pid age=${age_min}min mem=$mem cpu=${cpu}%"
    done
fi

# Detect zombies: processes running > 30 min are likely stuck
echo ""
echo "Health:"
ZOMBIE_COUNT=0
if [ -n "$CLAUDE_PIDS" ]; then
    for pid in $CLAUDE_PIDS; do
        age_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$age_s" -gt 1800 ]; then
            ZOMBIE_COUNT=$((ZOMBIE_COUNT + 1))
            log "ZOMBIE: PID $pid running ${age_s}s ($(( age_s / 60 ))min)"
            echo "  ⚠️ ZOMBIE: PID $pid (${age_s}s / $((age_s/60))min)"
        fi
    done
fi

if [ "$ZOMBIE_COUNT" -eq 0 ] && [ "$CLAUDE_COUNT" -eq 0 ]; then
    echo "  ✅ Clean — no agents running"
elif [ "$ZOMBIE_COUNT" -eq 0 ]; then
    echo "  ✅ All agents healthy (under 30min)"
else
    echo "  ❌ $ZOMBIE_COUNT zombie(s) detected"
fi

# Output machine-readable summary
echo ""
echo "SUMMARY: agents=$CLAUDE_COUNT bridges=$BRIDGE_COUNT zombies=$ZOMBIE_COUNT"
