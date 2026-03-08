#!/bin/bash
# Updates cockpit state file with current agent data
# Called by cron every 30s or manually

STATE_FILE="/Users/fonsecabc/.openclaw/workspace/config/cockpit-state.json"
GATEWAY_URL="ws://127.0.0.1:18789"

# Use the OpenClaw gateway API directly via curl to localhost
# The subagents data comes from the gateway's WebSocket API
# Fallback: use the task manager state

# Try to get live data from sessions list
SESSIONS=$(curl -s --max-time 5 "http://127.0.0.1:18789/api/sessions?kinds=subagent&activeMinutes=60&messageLimit=0" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$SESSIONS" ] && echo "$SESSIONS" | jq . >/dev/null 2>&1; then
    echo "$SESSIONS" > "$STATE_FILE"
else
    # Fallback: empty state
    echo '{"active":[],"recent":[],"total":0,"stale":true}' > "$STATE_FILE"
fi
