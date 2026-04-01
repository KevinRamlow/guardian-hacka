#!/bin/bash
# infra-maintenance.sh — Consolidated infrastructure maintenance
# Runs every 15min via launchd. Combines: langfuse-query, state cleanup
#
set -euo pipefail

WORKSPACE="${OPENCLAW_HOME:-$HOME}/.openclaw/workspace"
LOCKFILE="/tmp/infra-maintenance.lock"

exec 200>"$LOCKFILE"
flock -n 200 || { exit 0; }

OC_HOME="${OPENCLAW_HOME:-$HOME}/.openclaw"; source "$OC_HOME/.env" 2>/dev/null || true

MASTER_LOG="$OC_HOME/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$MASTER_LOG")"

log() {
  local level="$1"; local component="$2"; local msg="$3"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$level] [$component] $msg" | tee -a "$MASTER_LOG" >&2
}

CYCLE_START=$(date +%s)
log INFO infra-maintenance "Maintenance cycle started"

# --- 1. Langfuse Scraper (every run = every 15min) ---
log INFO infra-maintenance "Langfuse scrape initiated"
if [ -f "$WORKSPACE/scripts/langfuse-query.sh" ]; then
  LANGFUSE_OUT=$(timeout 30 bash "$WORKSPACE/scripts/langfuse-query.sh" 2>&1 | tail -3 || echo "langfuse failed")
  log INFO infra-maintenance "Langfuse scrape completed (output=${LANGFUSE_OUT})"
else
  log WARN infra-maintenance "Langfuse script not found — skipped"
fi

# --- 2. State cleanup (remove old done/failed tasks >24h) ---
log INFO infra-maintenance "State cleanup initiated (max_age=86400s)"
CLEANUP_RESULT=$(bash "$WORKSPACE/scripts/task-manager.sh" cleanup --max-age 86400 2>&1 || echo "cleanup error")
log INFO infra-maintenance "State cleanup completed (result=${CLEANUP_RESULT})"

CYCLE_DURATION=$(( $(date +%s) - CYCLE_START ))
log INFO infra-maintenance "Maintenance cycle completed (duration=${CYCLE_DURATION}s)"
