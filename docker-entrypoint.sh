#!/bin/bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node/.openclaw}"

# ── Validate critical env vars ──
MISSING=()
[ -z "${ANTHROPIC_API_KEY:-}" ] && MISSING+=("ANTHROPIC_API_KEY")
[ -z "${SLACK_BOT_TOKEN:-}" ] && MISSING+=("SLACK_BOT_TOKEN")
[ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "FATAL: Missing required env vars: ${MISSING[*]}" >&2
  exit 1
fi

# ── Setup sub-agent workspaces (idempotent) ──
bash "${OPENCLAW_HOME}/workspace/scripts/setup-workspaces.sh"

echo "=== Anton OpenClaw Gateway ==="
echo "OPENCLAW_HOME=${OPENCLAW_HOME}"
echo "NODE_ENV=${NODE_ENV:-development}"
echo "Secrets: loaded from environment (${#ANTHROPIC_API_KEY} chars ANTHROPIC_API_KEY)"

# ── Exec into OpenClaw ──
exec openclaw "$@"
