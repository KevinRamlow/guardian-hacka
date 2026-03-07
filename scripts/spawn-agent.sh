#!/bin/bash
# Spawn Agent — Unified spawn wrapper for all agent creation
# Replaces direct sessions_spawn calls with registry-tracked spawning
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue] [--runtime subagent] [--model model] [--cwd dir] <task-file-or-text>
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"

# Defaults
TASK_ID=""
LABEL=""
TIMEOUT_MIN=25
SOURCE="manual"
RUNTIME="subagent"
MODEL=""
CWD="/root/.openclaw/workspace"
TASK_TEXT=""
TASK_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)     TASK_ID="$2"; shift 2 ;;
    --label)    LABEL="$2"; shift 2 ;;
    --timeout)  TIMEOUT_MIN="$2"; shift 2 ;;
    --source)   SOURCE="$2"; shift 2 ;;
    --runtime)  RUNTIME="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    --cwd)      CWD="$2"; shift 2 ;;
    --file)     TASK_FILE="$2"; shift 2 ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          TASK_TEXT="$1"; shift ;;
  esac
done

# Validation
if [ -z "$TASK_ID" ]; then
  echo "ERROR: --task <CAI-XX> is required" >&2
  exit 1
fi

if [ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ]; then
  echo "ERROR: Provide task text as argument or --file <path>" >&2
  exit 1
fi

if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
  TASK_TEXT=$(cat "$TASK_FILE")
elif [ -n "$TASK_FILE" ]; then
  echo "ERROR: Task file not found: $TASK_FILE" >&2
  exit 1
fi

if [ -z "$LABEL" ]; then
  LABEL="$TASK_ID"
fi

# Check capacity
SLOTS=$(bash "$REGISTRY" slots)
if [ "$SLOTS" -le 0 ]; then
  echo "ERROR: No slots available ($(bash "$REGISTRY" count) agents running)" >&2
  exit 1
fi

# Check if task already running
HAS=$(bash "$REGISTRY" has "$TASK_ID")
if [ "$HAS" = "yes" ]; then
  echo "ERROR: $TASK_ID already has a running agent" >&2
  exit 1
elif [ "$HAS" = "dead" ]; then
  # Clean up dead entry
  bash "$REGISTRY" remove "$TASK_ID"
fi

echo "[spawn] Starting $TASK_ID ($LABEL) via $RUNTIME..."

# Prepare task file for the agent
TASK_DIR="/root/.openclaw/tasks/spawn-tasks"
mkdir -p "$TASK_DIR"
TASK_PATH="$TASK_DIR/${TASK_ID}.md"
echo "$TASK_TEXT" > "$TASK_PATH"

# Inject CLAUDE.md instructions at the top
CLAUDE_MD="/root/.openclaw/workspace/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  FULL_TASK=$(cat <<INJECT
$(cat "$CLAUDE_MD")

---

$TASK_TEXT
INJECT
)
  echo "$FULL_TASK" > "$TASK_PATH"
fi

# Spawn based on runtime
AGENT_PID=0
BRIDGE_PID=0

if [ "$RUNTIME" = "subagent" ]; then
  # Use OpenClaw subagent runtime (tracked by OpenClaw natively)
  # Write a trigger file that the main OpenClaw session picks up
  # For non-interactive spawn, use claude CLI directly
  cd "$CWD"

  MODEL_ARG=""
  if [ -n "$MODEL" ]; then
    MODEL_ARG="--model $MODEL"
  fi

  # Spawn claude directly as a background process with the task
  nohup claude --print $MODEL_ARG -p "$(cat "$TASK_PATH")" \
    > "/root/.openclaw/tasks/agent-logs/${TASK_ID}-output.log" 2>&1 &
  AGENT_PID=$!

elif [ "$RUNTIME" = "acp" ]; then
  # ACP runtime — spawn via sessions_spawn but capture PID
  # We still use sessions_spawn for ACP but now track the PID
  cd "$CWD"

  MODEL_ARG=""
  if [ -n "$MODEL" ]; then
    MODEL_ARG="--model $MODEL"
  fi

  # Spawn claude directly (bypassing broken ACP bridge)
  nohup claude --print $MODEL_ARG -p "$(cat "$TASK_PATH")" \
    > "/root/.openclaw/tasks/agent-logs/${TASK_ID}-output.log" 2>&1 &
  AGENT_PID=$!

elif [ "$RUNTIME" = "direct" ]; then
  # Direct claude CLI invocation (simplest, most reliable)
  cd "$CWD"

  MODEL_ARG=""
  if [ -n "$MODEL" ]; then
    MODEL_ARG="--model $MODEL"
  fi

  nohup claude --print $MODEL_ARG -p "$(cat "$TASK_PATH")" \
    > "/root/.openclaw/tasks/agent-logs/${TASK_ID}-output.log" 2>&1 &
  AGENT_PID=$!

else
  echo "ERROR: Unknown runtime: $RUNTIME" >&2
  exit 1
fi

# Wait a moment to verify the process started
sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent process died immediately (PID=$AGENT_PID)" >&2
  echo "Check log: /root/.openclaw/tasks/agent-logs/${TASK_ID}-output.log" >&2
  exit 1
fi

# Register in registry
bash "$REGISTRY" register "$TASK_ID" "$AGENT_PID" "$BRIDGE_PID" "$LABEL" "$SOURCE" "$TIMEOUT_MIN"

# Log to Linear + disk
bash "$LOGGER" "$TASK_ID" spawn "Agent spawned: $LABEL (PID=$AGENT_PID, timeout=${TIMEOUT_MIN}min, src=$SOURCE)" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "🚀 [$(date -u +%H:%M)] Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min)" progress 2>/dev/null || true

echo "[spawn] OK: $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min"
echo "$AGENT_PID"
