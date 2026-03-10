#!/bin/bash
# Gateway Auto-Respawn — Ensures openclaw-gateway stays alive
# Runs every 60s via cron. If gateway is down, restarts it.
# If gateway has been down for >2 consecutive checks, alerts Slack.
set -euo pipefail

LOCKFILE="/tmp/gateway-respawn.lock"
STATE_FILE="/tmp/gateway-respawn-state"
GATEWAY_PORT=18789
LOG_TAG="[gateway-respawn]"
SLACK_WEBHOOK_URL=""  # Set if you want Slack alerts via webhook

# Lockfile (prevent overlapping runs)
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$LOG_TAG Skipped: already running"; exit 0; }

TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Check if gateway is running
GATEWAY_PID=$(pgrep -f "openclaw-gateway" 2>/dev/null | head -1 || true)

if [ -n "$GATEWAY_PID" ]; then
    # Gateway alive — reset failure counter
    echo "0" > "$STATE_FILE"
    echo "$LOG_TAG [$TS] OK: gateway running (PID=$GATEWAY_PID)"
    exit 0
fi

# Gateway is down — increment failure counter
FAIL_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
FAIL_COUNT=$((FAIL_COUNT + 1))
echo "$FAIL_COUNT" > "$STATE_FILE"

echo "$LOG_TAG [$TS] Gateway DOWN (consecutive failures: $FAIL_COUNT). Restarting..."

# Kill any zombie node processes on the gateway port
# Kill process on port (macOS-compatible)
lsof -ti ":$GATEWAY_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

# Restart gateway
nohup openclaw gateway --port "$GATEWAY_PORT" > /tmp/gateway.log 2>&1 &
sleep 8

# Verify
NEW_PID=$(pgrep -f "openclaw-gateway" 2>/dev/null | head -1 || true)

if [ -n "$NEW_PID" ]; then
    echo "$LOG_TAG [$TS] Restarted successfully (PID=$NEW_PID)"

    # Check if port is listening (lsof works on macOS; ss is Linux-only)
    if lsof -i :"$GATEWAY_PORT" -sTCP:LISTEN > /dev/null 2>&1; then
        echo "$LOG_TAG [$TS] Port $GATEWAY_PORT confirmed listening"
    else
        echo "$LOG_TAG [$TS] WARNING: Gateway running but port $GATEWAY_PORT not listening yet"
    fi
else
    echo "$LOG_TAG [$TS] FAILED to restart gateway"

    # Alert via linear-log.sh if repeated failures (posts to both Linear and Slack)
    if [ "$FAIL_COUNT" -ge 3 ]; then
        LINEAR_LOG="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/task-manager/scripts/linear-log.sh"
        if [ -f "$LINEAR_LOG" ]; then
            bash "$LINEAR_LOG" "CAI-INFRA" "CRITICAL: Gateway failed to restart after $FAIL_COUNT consecutive attempts. Manual intervention may be required." blocked 2>/dev/null || true
        fi
    fi
fi
