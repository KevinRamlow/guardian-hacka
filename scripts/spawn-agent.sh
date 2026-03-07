#!/bin/bash
# Spawn Agent — Unified spawn wrapper for all agent creation
# All spawns go through this script → registry-tracked, PID-captured, Linear-logged
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue] [--model model] [--cwd dir] [--file path] [--no-fallback] "task text"
#
# Model fallback: On API limit errors, auto-retries with next model tier (opus→sonnet→haiku).
# Use --no-fallback to disable this behavior for tasks requiring a specific model.
#
# SUCCESS CRITERIA REQUIREMENT:
# Every task MUST include clear success criteria. Use templates/TASK-template.md.
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/root/.openclaw/tasks/agent-logs"
TASKS_DIR="/root/.openclaw/tasks/spawn-tasks"

TASK_ID="" LABEL="" TIMEOUT_MIN=25 SOURCE="manual" MODEL="" CWD="/root/.openclaw/workspace" TASK_TEXT="" TASK_FILE="" NO_FALLBACK=false

# Model fallback chain: opus → sonnet → haiku
FALLBACK_CHAIN=("claude-opus-4-6" "claude-sonnet-4-6" "claude-haiku-4-5-20251001")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK_ID="$2"; shift 2 ;;
    --label)   LABEL="$2"; shift 2 ;;
    --timeout) TIMEOUT_MIN="$2"; shift 2 ;;
    --source)  SOURCE="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    --cwd)     CWD="$2"; shift 2 ;;
    --file)    TASK_FILE="$2"; shift 2 ;;
    --no-fallback) NO_FALLBACK=true; shift ;;
    -*)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)         TASK_TEXT="$1"; shift ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task <CAI-XX> required" >&2; exit 1; }
[ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ] && { echo "ERROR: Provide task text or --file <path>" >&2; exit 1; }
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$LABEL" ] && LABEL="$TASK_ID"

# --- Model Fallback Helpers ---
is_api_limit_error() {
  local text="$1"
  echo "$text" | grep -qiE "usage limits|rate limit|billing|quota exceeded|API Error|spending limit|overloaded|capacity"
}

get_next_fallback_model() {
  local current="$1"
  local found=false
  for m in "${FALLBACK_CHAIN[@]}"; do
    if $found; then
      echo "$m"
      return 0
    fi
    if [[ "$m" == "$current" ]]; then
      found=true
    fi
  done
  # If current model not in chain, or no next model available
  return 1
}

get_effective_model() {
  local model="$1"
  # If no model specified, resolve from claude default (assume opus)
  if [ -z "$model" ]; then
    echo "claude-opus-4-6"
  else
    echo "$model"
  fi
}

log_fallback_event() {
  local task_id="$1" from_model="$2" to_model="$3" reason="$4"
  local msg="FALLBACK: $task_id model $from_model -> $to_model (reason: $reason)"
  echo "[spawn] $msg"
  bash "$LINEAR_LOG" "$task_id" "$msg" progress 2>/dev/null || true

  # Alert to Slack via linear-log (already posts to Slack)
  # Also mark in a fallback indicator file for downstream consumers
  echo "{\"task\":\"$task_id\",\"from\":\"$from_model\",\"to\":\"$to_model\",\"reason\":\"$reason\",\"ts\":$(date +%s)}" \
    >> "$LOGS_DIR/fallback-events.jsonl"
}

# --- Pre-flight: check API accessibility with fallback ---
EFFECTIVE_MODEL=$(get_effective_model "$MODEL")
SPAWN_MODEL="$MODEL"  # Original model arg (may be empty = use default)

preflight_check() {
  local model_arg=""
  [ -n "$1" ] && model_arg="--model $1"
  claude --print $model_arg -p "Say OK" 2>&1 || true
}

API_CHECK=$(preflight_check "$SPAWN_MODEL")
if is_api_limit_error "$API_CHECK"; then
  if $NO_FALLBACK; then
    ERROR_MSG=$(echo "$API_CHECK" | head -1)
    echo "ERROR: API health check failed (--no-fallback set): $ERROR_MSG" >&2
    bash "$LINEAR_LOG" "$TASK_ID" "BLOCKED: API limit reached, no fallback allowed - $ERROR_MSG" blocked 2>/dev/null || true
    exit 1
  fi

  # Try fallback models
  ORIGINAL_MODEL="$EFFECTIVE_MODEL"
  FELL_BACK=false
  NEXT_MODEL="$EFFECTIVE_MODEL"
  while NEXT_MODEL=$(get_next_fallback_model "$NEXT_MODEL"); do
    echo "[spawn] API limit on $EFFECTIVE_MODEL, trying fallback: $NEXT_MODEL"
    API_CHECK=$(preflight_check "$NEXT_MODEL")
    if ! is_api_limit_error "$API_CHECK"; then
      SPAWN_MODEL="$NEXT_MODEL"
      EFFECTIVE_MODEL="$NEXT_MODEL"
      FELL_BACK=true
      log_fallback_event "$TASK_ID" "$ORIGINAL_MODEL" "$NEXT_MODEL" "pre-flight API limit"
      break
    fi
  done

  if ! $FELL_BACK; then
    ERROR_MSG=$(echo "$API_CHECK" | head -1)
    echo "ERROR: API limit on all model tiers: $ERROR_MSG" >&2
    bash "$LINEAR_LOG" "$TASK_ID" "BLOCKED: API limit on all models (tried full fallback chain)" blocked 2>/dev/null || true
    exit 1
  fi
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
[ -n "$SPAWN_MODEL" ] && MODEL_ARG="--model $SPAWN_MODEL"

# Fallback indicator file — downstream consumers can check if task used fallback
FALLBACK_INDICATOR="$LOGS_DIR/${TASK_ID}-fallback"
[ "$SPAWN_MODEL" != "$(get_effective_model "$MODEL")" ] && [ -n "$SPAWN_MODEL" ] && \
  echo "$SPAWN_MODEL" > "$FALLBACK_INDICATOR"

# Build the spawn command with fallback retry wrapper
# If agent dies with API limit error and fallback is allowed, retry with next model
FALLBACK_SCRIPT=""
if ! $NO_FALLBACK; then
  # Generate the fallback retry script that runs inside nohup
  REMAINING_MODELS=""
  CURRENT="$EFFECTIVE_MODEL"
  while NEXT=$(get_next_fallback_model "$CURRENT" 2>/dev/null); do
    REMAINING_MODELS="$REMAINING_MODELS $NEXT"
    CURRENT="$NEXT"
  done
  REMAINING_MODELS=$(echo "$REMAINING_MODELS" | xargs)  # trim

  if [ -n "$REMAINING_MODELS" ]; then
    FALLBACK_SCRIPT="
    # Post-run fallback: if agent failed with API limit, retry with next model
    if [ \$EXIT_CODE -ne 0 ] || grep -qiE 'usage limits|rate limit|billing|quota exceeded|API Error|spending limit|overloaded|capacity' '$LOGS_DIR/${TASK_ID}-stderr.log' '$LOGS_DIR/${TASK_ID}-output.log' 2>/dev/null; then
      for FALLBACK_MODEL in $REMAINING_MODELS; do
        echo \"[fallback] Retrying $TASK_ID with \$FALLBACK_MODEL\" >> '$LOGS_DIR/${TASK_ID}-stderr.log'
        echo \"{\\\"task\\\":\\\"$TASK_ID\\\",\\\"from\\\":\\\"$EFFECTIVE_MODEL\\\",\\\"to\\\":\\\"\$FALLBACK_MODEL\\\",\\\"reason\\\":\\\"runtime API limit\\\",\\\"ts\\\":\$(date +%s)}\" >> '$LOGS_DIR/fallback-events.jsonl'
        bash '$LINEAR_LOG' '$TASK_ID' \"FALLBACK: runtime API limit, retrying with \$FALLBACK_MODEL\" progress 2>/dev/null || true
        echo \"\$FALLBACK_MODEL\" > '$FALLBACK_INDICATOR'
        claude --print --permission-mode dontAsk --allowedTools 'Write,Edit,Bash,Read,Glob,Grep' --model \"\$FALLBACK_MODEL\" -p \"\$(cat '$TASK_PATH')\" \
          > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log'
        EXIT_CODE=\$?
        if [ \$EXIT_CODE -eq 0 ] && ! grep -qiE 'usage limits|rate limit|billing|quota exceeded|API Error|spending limit|overloaded|capacity' '$LOGS_DIR/${TASK_ID}-stderr.log' '$LOGS_DIR/${TASK_ID}-output.log' 2>/dev/null; then
          break
        fi
      done
    fi"
  fi
fi

nohup bash -c "
  claude --print --permission-mode dontAsk --allowedTools 'Write,Edit,Bash,Read,Glob,Grep' $MODEL_ARG -p \"\$(cat '$TASK_PATH')\" \
    > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log';
  EXIT_CODE=\$?;
  $FALLBACK_SCRIPT
  echo \"\$EXIT_CODE\" > '$LOGS_DIR/${TASK_ID}-exit-code';
" &>/dev/null &
AGENT_PID=$!

# Verify process started
sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent died immediately (PID=$AGENT_PID)" >&2
  STDERR_CONTENT=$(cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null || true)
  echo "Stderr: $STDERR_CONTENT" >&2

  # If died immediately with API limit and fallback allowed, try sync fallback
  if ! $NO_FALLBACK && is_api_limit_error "$STDERR_CONTENT"; then
    CURRENT="$EFFECTIVE_MODEL"
    while NEXT_MODEL=$(get_next_fallback_model "$CURRENT"); do
      echo "[spawn] Immediate failure, trying sync fallback: $NEXT_MODEL"
      log_fallback_event "$TASK_ID" "$CURRENT" "$NEXT_MODEL" "immediate spawn failure"
      SPAWN_MODEL="$NEXT_MODEL"
      echo "$NEXT_MODEL" > "$FALLBACK_INDICATOR"

      nohup bash -c "
        claude --print --permission-mode dontAsk --allowedTools 'Write,Edit,Bash,Read,Glob,Grep' --model '$NEXT_MODEL' -p \"\$(cat '$TASK_PATH')\" \
          > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log';
        echo \"\$?\" > '$LOGS_DIR/${TASK_ID}-exit-code';
      " &>/dev/null &
      AGENT_PID=$!
      sleep 2
      if kill -0 "$AGENT_PID" 2>/dev/null; then
        break  # Success — agent is running
      fi
      CURRENT="$NEXT_MODEL"
    done

    # Final check after all fallback attempts
    if ! kill -0 "$AGENT_PID" 2>/dev/null; then
      echo "ERROR: All model tiers failed for $TASK_ID" >&2
      bash "$LINEAR_LOG" "$TASK_ID" "BLOCKED: All model tiers failed at spawn" blocked 2>/dev/null || true
      exit 1
    fi
  else
    exit 1
  fi
fi

# Register + log
FALLBACK_NOTE=""
[ -f "$FALLBACK_INDICATOR" ] && FALLBACK_NOTE=" [FALLBACK:$(cat "$FALLBACK_INDICATOR")]"
bash "$REGISTRY" register "$TASK_ID" "$AGENT_PID" 0 "$LABEL" "$SOURCE" "$TIMEOUT_MIN"
bash "$LOGGER" "$TASK_ID" spawn "PID=$AGENT_PID timeout=${TIMEOUT_MIN}min src=$SOURCE$FALLBACK_NOTE" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min)$FALLBACK_NOTE" progress 2>/dev/null || true

echo "[spawn] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min$FALLBACK_NOTE"
echo "$AGENT_PID"
