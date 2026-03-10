#!/bin/bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node/.openclaw}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_BIND="${GATEWAY_BIND:-lan}"

# ── Validate critical env vars ──
MISSING=()
[ -z "${ANTHROPIC_API_KEY:-}" ] && MISSING+=("ANTHROPIC_API_KEY")
[ -z "${SLACK_BOT_TOKEN:-}" ] && MISSING+=("SLACK_BOT_TOKEN")
[ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "FATAL: Missing required env vars: ${MISSING[*]}" >&2
  exit 1
fi

# ── Git identity & auth (needed for agents to commit/push) ──
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Anton [bot]}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-anton-bot@fonsecabc.dev}"

git config --global user.name "${GIT_AUTHOR_NAME}"
git config --global user.email "${GIT_AUTHOR_EMAIL}"
git config --global safe.directory '*'

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
  echo "Git: configured HTTPS auth via GITHUB_TOKEN"
else
  echo "WARN: GITHUB_TOKEN not set — git push to GitHub will fail" >&2
fi

# ── Setup sub-agent workspaces (idempotent) ──
bash "${OPENCLAW_HOME}/workspace/scripts/setup-workspaces.sh"

echo "=== Anton OpenClaw Gateway ==="
echo "OPENCLAW_HOME=${OPENCLAW_HOME}"
echo "NODE_ENV=${NODE_ENV:-development}"
echo "GATEWAY_PORT=${GATEWAY_PORT}"
echo "Secrets: loaded from environment (${#ANTHROPIC_API_KEY} chars ANTHROPIC_API_KEY)"

# ── Start background schedulers ──
echo "Starting infra-maintenance (15m interval)..."
(
  while true; do
    sleep 900
    bash "${OPENCLAW_HOME}/workspace/scripts/infra-maintenance.sh" 2>/dev/null || true
  done
) &

# ── Exec into OpenClaw ──
exec openclaw "$@" --port "${GATEWAY_PORT}" --bind "${GATEWAY_BIND}"
