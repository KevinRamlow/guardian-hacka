#!/bin/bash
# Start Sentinel locally — gateway only
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# openclaw always reads config from $HOME/.openclaw/.
# OPENCLAW_HOME must be $HOME so all runtime paths resolve under ~/.openclaw/.
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME}"
export OPENCLAW_HOME

OC_DIR="$OPENCLAW_HOME/.openclaw"
mkdir -p "$OC_DIR"

# ── Local-dev bootstrap: bridge project files into ~/.openclaw/ ──
# Without these symlinks openclaw can't find its config and the gateway
# refuses to start ("gateway.mode is unset; gateway start will be blocked").
if [ ! -e "$OC_DIR/openclaw.json" ]; then
  ln -sf "$PROJECT_ROOT/openclaw.json" "$OC_DIR/openclaw.json"
  echo "[bootstrap] linked openclaw.json → $OC_DIR/openclaw.json"
fi
if [ ! -e "$OC_DIR/workspace" ]; then
  ln -sf "$PROJECT_ROOT/workspace" "$OC_DIR/workspace"
  echo "[bootstrap] linked workspace → $OC_DIR/workspace"
fi
if [ ! -e "$OC_DIR/.env" ]; then
  ln -sf "$PROJECT_ROOT/.env" "$OC_DIR/.env"
  echo "[bootstrap] linked .env → $OC_DIR/.env"
fi

MASTER_LOG="$OC_DIR/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$MASTER_LOG")"

log() {
  local level="$1"; local component="$2"; local msg="$3"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$level] [$component] $msg" | tee -a "$MASTER_LOG" >&2
}

log INFO start "Local startup initiated (project=$PROJECT_ROOT openclaw_home=$OPENCLAW_HOME)"

# Load secrets from .env (local) or env vars (GKE)
if [ -f "$PROJECT_ROOT/.env" ]; then
  echo "=== Loading secrets from .env ==="
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Validate critical env vars
MISSING=()
[ -z "${ANTHROPIC_API_KEY:-}" ] && MISSING+=("ANTHROPIC_API_KEY")
[ -z "${SLACK_BOT_TOKEN:-}" ] && MISSING+=("SLACK_BOT_TOKEN")
[ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN")

if [ ${#MISSING[@]} -gt 0 ]; then
  for var in "${MISSING[@]}"; do
    log ERROR start "Required env var missing: $var"
  done
  echo "FATAL: Missing required env vars: ${MISSING[*]}" >&2
  echo "Copy .env.example to .env and fill in values." >&2
  exit 1
fi

log INFO start "Env validation passed (vars=3)"

# Setup sub-agent workspaces
bash "$PROJECT_ROOT/workspace/scripts/setup-workspaces.sh"
log INFO start "Sub-agent workspaces initialized"

# Initialize few-shot database
bash "$PROJECT_ROOT/workspace/scripts/few-shot-db.sh" init 2>/dev/null || true
log INFO start "Few-shot database initialized"

echo "=== Starting Sentinel Gateway ==="
echo "OPENCLAW_HOME=${OPENCLAW_HOME}"
log INFO start "Launching openclaw gateway (port=${GATEWAY_PORT:-18789})"
openclaw gateway --port "${GATEWAY_PORT:-18789}"
