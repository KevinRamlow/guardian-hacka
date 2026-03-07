#!/bin/bash
# Spawn Agent — Unified spawn wrapper for all agent creation
# All spawns go through this script → registry-tracked, PID-captured, Linear-logged
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue] [--model model] [--cwd dir] [--file path] "task text"
#
# SUCCESS CRITERIA REQUIREMENT:
# Every task MUST include clear success criteria. Use templates/TASK-template.md.
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/root/.openclaw/tasks/agent-logs"
TASKS_DIR="/root/.openclaw/tasks/spawn-tasks"

TASK_ID="" LABEL="" TIMEOUT_MIN=25 SOURCE="manual" MODEL="" CWD="/root/.openclaw/workspace" TASK_TEXT="" TASK_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK_ID="$2"; shift 2 ;;
    --label)   LABEL="$2"; shift 2 ;;
    --timeout) TIMEOUT_MIN="$2"; shift 2 ;;
    --source)  SOURCE="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    --cwd)     CWD="$2"; shift 2 ;;
    --file)    TASK_FILE="$2"; shift 2 ;;
    -*)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)         TASK_TEXT="$1"; shift ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task <CAI-XX> required" >&2; exit 1; }
[ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ] && { echo "ERROR: Provide task text or --file <path>" >&2; exit 1; }
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$LABEL" ] && LABEL="$TASK_ID"

# Pre-flight: check if API is accessible (catches spending limits before spawning)
API_CHECK=$(claude --print -p "Say OK" 2>&1 || true)
if echo "$API_CHECK" | grep -qi "usage limits\|rate limit\|billing\|quota exceeded\|API Error"; then
  ERROR_MSG=$(echo "$API_CHECK" | head -1)
  echo "ERROR: API health check failed: $ERROR_MSG" >&2
  bash "$LINEAR_LOG" "$TASK_ID" "BLOCKED: API limit reached - $ERROR_MSG" blocked 2>/dev/null || true
  exit 1
fi

# Check capacity
SLOTS=$(bash "$REGISTRY" slots)
[ "$SLOTS" -le 0 ] && { echo "ERROR: No slots ($(bash "$REGISTRY" count) running)" >&2; exit 1; }

# Check duplicate
HAS=$(bash "$REGISTRY" has "$TASK_ID")
[ "$HAS" = "yes" ] && { echo "ERROR: $TASK_ID already running" >&2; exit 1; }
[ "$HAS" = "dead" ] && bash "$REGISTRY" remove "$TASK_ID"

# Prepare task file with CLAUDE.md injected
mkdir -p "$LOGS_DIR" "$TASKS_DIR"
TASK_PATH="$TASKS_DIR/${TASK_ID}.md"
CLAUDE_MD="/root/.openclaw/workspace/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  { cat "$CLAUDE_MD"; echo -e "\n---\n"; echo "$TASK_TEXT"; } > "$TASK_PATH"
else
  echo "$TASK_TEXT" > "$TASK_PATH"
fi

# Source all credentials for sub-agents
[ -f /root/.openclaw/workspace/.env.secrets ] && source /root/.openclaw/workspace/.env.secrets
[ -f /root/.openclaw/workspace/.env.linear ] && source /root/.openclaw/workspace/.env.linear

# Source GCP credentials if available (for BigQuery/Cloud SQL access)
GCP_ENV="/root/.openclaw/workspace/.gcp-env"
[ -f "$GCP_ENV" ] && source "$GCP_ENV"

# Export env vars that sub-agents need
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-/root/.openclaw/workspace/.gcp-credentials.json}"

# Spawn claude CLI directly (no ACP bridge — it creates invisible zombies)
# Separate stdout (output) and stderr (errors) into different files
cd "$CWD"
MODEL_ARG=""
[ -n "$MODEL" ] && MODEL_ARG="--model $MODEL"

nohup bash -c "
  claude --print --permission-mode dontAsk --allowedTools 'Write,Edit,Bash,Read,Glob,Grep' $MODEL_ARG -p \"\$(cat '$TASK_PATH')\" \
    > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log';
  EXIT_CODE=\$?;
  echo \"\$EXIT_CODE\" > '$LOGS_DIR/${TASK_ID}-exit-code';
" &>/dev/null &
AGENT_PID=$!

# Verify process started
sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent died immediately (PID=$AGENT_PID)" >&2
  echo "Stderr: $(cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null)" >&2
  exit 1
fi

# Register + log
bash "$REGISTRY" register "$TASK_ID" "$AGENT_PID" 0 "$LABEL" "$SOURCE" "$TIMEOUT_MIN"
bash "$LOGGER" "$TASK_ID" spawn "PID=$AGENT_PID timeout=${TIMEOUT_MIN}min src=$SOURCE" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min)" progress 2>/dev/null || true

echo "[spawn] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min"
echo "$AGENT_PID"
