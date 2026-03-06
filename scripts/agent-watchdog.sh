#!/bin/bash
# Agent Watchdog - Runs every 10 min via cron
# Detects stuck/frozen agents and writes alerts for Anton to pick up

set -e

WORKSPACE="/root/.openclaw/workspace"
ALERTS_FILE="$WORKSPACE/tasks/agent-alerts.json"
STATE_FILE="$WORKSPACE/tasks/agent-state.json"

# Ensure directories exist
mkdir -p "$WORKSPACE/tasks"

# Get current agents
AGENTS_JSON=$(openclaw subagents list --json 2>/dev/null || echo '{"active":[]}')

# Extract alerts
ALERTS=()
NOW=$(date +%s)

echo "$AGENTS_JSON" | jq -r '.active[] | [.label, .runtimeMs, .sessionKey, .startedAt] | @tsv' | while IFS=$'\t' read -r label runtimeMs sessionKey startedAt; do
    RUNTIME_MIN=$((runtimeMs / 60000))
    TASK_ID=$(echo "$label" | grep -oP '\b(CAI-\d+)\b' | head -1 || echo "unknown")
    
    # Alert thresholds
    if [ "$RUNTIME_MIN" -gt 25 ]; then
        ALERT_JSON=$(jq -n \
            --arg task "$TASK_ID" \
            --arg label "$label" \
            --arg runtime "${RUNTIME_MIN}min" \
            --arg level "CRITICAL" \
            --arg message "Agent running >25min, likely frozen" \
            '{task: $task, label: $label, runtime: $runtime, level: $level, message: $message, timestamp: now}')
        
        # Append to alerts file
        echo "$ALERT_JSON" >> "$ALERTS_FILE"
        
    elif [ "$RUNTIME_MIN" -gt 20 ]; then
        ALERT_JSON=$(jq -n \
            --arg task "$TASK_ID" \
            --arg label "$label" \
            --arg runtime "${RUNTIME_MIN}min" \
            --arg level "WARNING" \
            --arg message "Agent running >20min without update" \
            '{task: $task, label: $label, runtime: $runtime, level: $level, message: $message, timestamp: now}')
        
        echo "$ALERT_JSON" >> "$ALERTS_FILE"
    fi
done

# Update state file (for Anton to read)
echo "$AGENTS_JSON" > "$STATE_FILE"

# Keep alerts file from growing too large (last 50 alerts only)
if [ -f "$ALERTS_FILE" ]; then
    tail -50 "$ALERTS_FILE" > "$ALERTS_FILE.tmp"
    mv "$ALERTS_FILE.tmp" "$ALERTS_FILE"
fi
