#!/bin/bash
# infra-maintenance.sh — Consolidated infrastructure maintenance
# Runs every 15min via launchd. Combines: langfuse-query, state cleanup
#
set -euo pipefail

WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
LOCKFILE="/tmp/infra-maintenance.lock"

exec 200>"$LOCKFILE"
flock -n 200 || { exit 0; }

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"; source "$OC_HOME/.env" 2>/dev/null || true

TS=$(date -u +"%H:%M:%S")
echo "[$TS] Infra maintenance starting"

# --- 1. Langfuse Scraper (every run = every 15min) ---
echo "[$TS] Langfuse scrape..."
if [ -f "$WORKSPACE/scripts/langfuse-query.sh" ]; then
  timeout 30 bash "$WORKSPACE/scripts/langfuse-query.sh" 2>&1 | tail -3 || echo "  langfuse failed"
fi

# --- 2. State cleanup (remove old done/failed tasks >24h) ---
echo "[$TS] State cleanup..."
bash "$WORKSPACE/scripts/task-manager.sh" cleanup --max-age 86400 2>&1 || true

echo "[$TS] Infra maintenance done"
