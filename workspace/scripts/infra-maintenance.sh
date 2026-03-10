#!/bin/bash
# infra-maintenance.sh — Consolidated infrastructure maintenance (replaces individual launchd jobs)
# Runs every 15min via launchd. Combines: linear-sync, gcp-token-push, langfuse-scraper
#
set -euo pipefail

WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
LOCKFILE="/tmp/infra-maintenance.lock"

exec 200>"$LOCKFILE"
flock -n 200 || { exit 0; }

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"; source "$OC_HOME/.env" 2>/dev/null || true

TS=$(date -u +"%H:%M:%S")
echo "[$TS] Infra maintenance starting"

# --- 1. Linear Sync (every run = every 15min) ---
echo "[$TS] Linear sync..."
bash "$WORKSPACE/scripts/linear-sync-v2.sh" 2>&1 | tail -3 || echo "  linear-sync failed"

# --- 2. GCP Token Refresh (every 3rd run = ~45min) ---
COUNTER_FILE="/tmp/infra-maintenance-counter"
COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE"

if [ $((COUNTER % 3)) -eq 0 ]; then
  echo "[$TS] GCP token refresh..."
  if [ -f "$WORKSPACE/scripts/gcp-token-push.sh" ]; then
    bash "$WORKSPACE/scripts/gcp-token-push.sh" 2>&1 | tail -3 || echo "  gcp-token-push failed"
  fi
fi

# --- 3. Langfuse Scraper (every run = every 15min, was 2min but that's too aggressive) ---
echo "[$TS] Langfuse scrape..."
if [ -f "$WORKSPACE/scripts/langfuse-query.sh" ]; then
  timeout 30 bash "$WORKSPACE/scripts/langfuse-query.sh" 2>&1 | tail -3 || echo "  langfuse failed"
fi

# --- 4. State cleanup (remove old done/failed tasks >24h) ---
echo "[$TS] State cleanup..."
bash "$WORKSPACE/scripts/task-manager.sh" cleanup --max-age 86400 2>&1 || true

echo "[$TS] Infra maintenance done"
