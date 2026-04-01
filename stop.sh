#!/bin/bash
# Stop Sentinel locally

OPENCLAW_HOME="${OPENCLAW_HOME:-$(cd "$(dirname "$0")" && pwd)}"
MASTER_LOG="${OPENCLAW_HOME}/.openclaw/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$MASTER_LOG")"

log() {
  local level="$1"; local component="$2"; local msg="$3"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$level] [$component] $msg" | tee -a "$MASTER_LOG" >&2
}

log INFO stop "Shutdown initiated"

echo "=== Stopping gateway ==="
openclaw gateway stop 2>/dev/null || pkill -f openclaw-gateway 2>/dev/null
log INFO stop "OpenClaw gateway stopped"

echo "=== Stopping claude agents ==="
AGENT_COUNT=$(pgrep -c -f "claude --print" 2>/dev/null || echo 0)
pkill -f "claude --print" 2>/dev/null || true
log INFO stop "Agent processes terminated (count=${AGENT_COUNT})"

echo "All stopped"
log INFO stop "Shutdown complete"
