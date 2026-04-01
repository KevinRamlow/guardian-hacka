#!/bin/bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_BIND="${GATEWAY_BIND:-lan}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5m}"
export HEARTBEAT_INTERVAL

MASTER_LOG="${OPENCLAW_HOME}/.openclaw/tasks/agent-logs/master.log"
mkdir -p "$(dirname "$MASTER_LOG")"

log() {
  local level="$1"; local component="$2"; local msg="$3"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$level] [$component] $msg" | tee -a "$MASTER_LOG" >&2
}

log INFO entrypoint "Container startup initiated"

# ── Validate critical env vars ──
MISSING=()
[ -z "${ANTHROPIC_API_KEY:-}" ] && MISSING+=("ANTHROPIC_API_KEY")
[ -z "${SLACK_BOT_TOKEN:-}" ] && MISSING+=("SLACK_BOT_TOKEN")
[ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN")

if [ ${#MISSING[@]} -gt 0 ]; then
  for var in "${MISSING[@]}"; do
    log ERROR entrypoint "Required env var missing: $var"
  done
  echo "FATAL: Missing required env vars: ${MISSING[*]}" >&2
  exit 1
fi

log INFO entrypoint "Env validation passed (vars=3)"

# ── Clean stale lock files (pod restart safety) ──
rm -f /tmp/openclaw-*/gateway.*.lock 2>/dev/null || true
log INFO entrypoint "Stale lock cleanup completed"

# ── Initialize OpenClaw runtime state ──
mkdir -p "${OPENCLAW_HOME}/.openclaw/agents/main/sessions"

# ── Git identity & auth (needed for agents to commit/push) ──
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Anton [bot]}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-anton-bot@fonsecabc.dev}"

git config --global user.name "${GIT_AUTHOR_NAME}"
git config --global user.email "${GIT_AUTHOR_EMAIL}"
git config --global safe.directory /home/node/.openclaw/workspace

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
  echo "Git: configured HTTPS auth via GITHUB_TOKEN"
else
  echo "WARN: GITHUB_TOKEN not set — git push to GitHub will fail" >&2
fi

log INFO entrypoint "Git identity configured (user=bruno_guardian)"

# ── GCP credentials (from GOOGLE_ACCOUNT_CREDENTIALS env var) ──
if [ -n "${REPLICANT_GOOGLE_ACCOUNT_CREDENTIALS:-}" ]; then
  GCP_CREDS_FILE="${OPENCLAW_HOME}/.openclaw/gcp-credentials.json"
  echo "${REPLICANT_GOOGLE_ACCOUNT_CREDENTIALS}" > "${GCP_CREDS_FILE}"
  chmod 600 "${GCP_CREDS_FILE}"
  export GOOGLE_APPLICATION_CREDENTIALS="${GCP_CREDS_FILE}"
  echo "GCP: credentials written to ${GCP_CREDS_FILE}"
  log INFO entrypoint "GCP credentials configured"
else
  echo "WARN: REPLICANT_GOOGLE_ACCOUNT_CREDENTIALS not set — GCP tools will not work" >&2
fi

# ── Persist MEMORY.md across deploys (backed up to PVC tasks/) ──
MEMORY_FILE="${OPENCLAW_HOME}/.openclaw/workspace/MEMORY.md"
MEMORY_BACKUP="${OPENCLAW_HOME}/.openclaw/tasks/MEMORY.md"
if [ -f "${MEMORY_BACKUP}" ]; then
  echo "Memory: restoring MEMORY.md from PVC backup ($(wc -l < "${MEMORY_BACKUP}") lines)"
  cp "${MEMORY_BACKUP}" "${MEMORY_FILE}"
  log INFO entrypoint "MEMORY.md restored from PVC backup"
elif [ -f "${MEMORY_FILE}" ]; then
  echo "Memory: seeding PVC backup from image MEMORY.md"
  cp "${MEMORY_FILE}" "${MEMORY_BACKUP}"
else
  log WARN entrypoint "No PVC backup found, starting fresh"
fi
# Background sync: save MEMORY.md to PVC every 2 minutes
(while true; do
  sleep 120
  [ -f "${MEMORY_FILE}" ] && cp "${MEMORY_FILE}" "${MEMORY_BACKUP}" 2>/dev/null || true
done) &

# ── Setup sub-agent workspaces (idempotent) ──
bash "${OPENCLAW_HOME}/.openclaw/workspace/scripts/setup-workspaces.sh"

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
    bash "${OPENCLAW_HOME}/.openclaw/workspace/scripts/infra-maintenance.sh" 2>/dev/null || true
  done
) &
log INFO entrypoint "Infra maintenance scheduler started (interval=15min)"

# ── Start dashboard ──
DASHBOARD_DIR="${OPENCLAW_HOME}/.openclaw/workspace/dashboard"
if [ -f "${DASHBOARD_DIR}/server.js" ]; then
  echo "Starting dashboard on port 8080..."
  node "${DASHBOARD_DIR}/server.js" &
  DASHBOARD_PID=$!
  log INFO entrypoint "Dashboard server started (port=8080 pid=$DASHBOARD_PID)"
fi

log INFO entrypoint "Handing off to openclaw gateway (port=${GATEWAY_PORT})"

# ── Exec into OpenClaw ──
exec openclaw "$@" --port "${GATEWAY_PORT}" --bind "${GATEWAY_BIND}"
