#!/bin/bash
# Start Sentinel locally — gateway only
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$(cd "$(dirname "$0")" && pwd)}"
export OPENCLAW_HOME

# Load secrets from .env (local) or env vars (GKE)
if [ -f "$OPENCLAW_HOME/.env" ]; then
  echo "=== Loading secrets from .env ==="
  set -a
  source "$OPENCLAW_HOME/.env"
  set +a
fi

# Validate critical env vars
MISSING=()
[ -z "${ANTHROPIC_API_KEY:-}" ] && MISSING+=("ANTHROPIC_API_KEY")
[ -z "${SLACK_BOT_TOKEN:-}" ] && MISSING+=("SLACK_BOT_TOKEN")
[ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "FATAL: Missing required env vars: ${MISSING[*]}" >&2
  echo "Copy .env.example to .env and fill in values." >&2
  exit 1
fi

# Setup sub-agent workspaces
bash "$OPENCLAW_HOME/workspace/scripts/setup-workspaces.sh"

# Initialize few-shot database
bash "$OPENCLAW_HOME/workspace/scripts/few-shot-db.sh" init 2>/dev/null || true

echo "=== Starting Sentinel Gateway ==="
echo "OPENCLAW_HOME=${OPENCLAW_HOME}"
openclaw gateway --port "${GATEWAY_PORT:-18789}"
