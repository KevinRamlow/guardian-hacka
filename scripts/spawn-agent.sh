#!/bin/bash
# Spawn Agent — Unified spawn wrapper for all agent creation
# All spawns go through this script → registry-tracked, PID-captured, Linear-logged
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue] [--model model] [--cwd dir] [--file path] [--force-spawn] "task text"
#
# Default model: claude-sonnet-4-6. Use --model to override.
# All agents stream activity to CAI-XX-activity.jsonl for real-time monitoring.
set -euo pipefail

REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
LOGGER="/Users/fonsecabc/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
TASKS_DIR="/Users/fonsecabc/.openclaw/tasks/spawn-tasks"
MONITOR="/Users/fonsecabc/.openclaw/workspace/scripts/agent-stream-monitor.py"
DEDUP_CHECK="/Users/fonsecabc/.openclaw/workspace/scripts/dedup-check.sh"

DEFAULT_MODEL="claude-sonnet-4-6"
TIMEOUT_RULES="/Users/fonsecabc/.openclaw/workspace/config/timeout-rules.json"

TASK_ID="" LABEL="" TIMEOUT_MIN=25 EXPLICIT_TIMEOUT=false SOURCE="manual" MODEL="" CWD="/Users/fonsecabc/.openclaw/workspace" TASK_TEXT="" TASK_FILE="" FORCE_SPAWN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK_ID="$2"; shift 2 ;;
    --label)   LABEL="$2"; shift 2 ;;
    --timeout) TIMEOUT_MIN="$2"; EXPLICIT_TIMEOUT=true; shift 2 ;;
    --source)  SOURCE="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    --cwd)     CWD="$2"; shift 2 ;;
    --file)    TASK_FILE="$2"; shift 2 ;;
    --force-spawn) FORCE_SPAWN=true; shift ;;
    -*)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)         TASK_TEXT="$1"; shift ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task <CAI-XX> required" >&2; exit 1; }
[ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ] && { echo "ERROR: Provide task text or --file <path>" >&2; exit 1; }
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$LABEL" ] && LABEL="$TASK_ID"

SPAWN_MODEL="${MODEL:-$DEFAULT_MODEL}"

# --- Adaptive Timeout Classification ---
# Only auto-classify if --timeout was not explicitly passed
if ! $EXPLICIT_TIMEOUT && [ -f "$TIMEOUT_RULES" ]; then
  TIMEOUT_MIN=$(python3 - "$TASK_TEXT" "$LABEL" "$TIMEOUT_RULES" << 'PYEOF'
import json, sys
text = (sys.argv[1] + " " + sys.argv[2]).lower()
rules_file = sys.argv[3]
try:
    rules = json.load(open(rules_file))["rules"]
    # Check rules in priority order (guardian_eval first, then code_task, etc.)
    for rule_name in ["guardian_eval", "code_task", "analysis", "image_gen"]:
        rule = rules.get(rule_name, {})
        for kw in rule.get("keywords", []):
            if kw.lower() in text:
                print(rule["timeout_min"])
                sys.exit(0)
    # Default
    print(rules.get("default", {}).get("timeout_min", 25))
except Exception:
    print(25)
PYEOF
)
  TASK_TYPE=$(python3 - "$TASK_TEXT" "$LABEL" "$TIMEOUT_RULES" << 'PYEOF'
import json, sys
text = (sys.argv[1] + " " + sys.argv[2]).lower()
rules_file = sys.argv[3]
try:
    rules = json.load(open(rules_file))["rules"]
    for rule_name in ["guardian_eval", "code_task", "analysis", "image_gen"]:
        rule = rules.get(rule_name, {})
        for kw in rule.get("keywords", []):
            if kw.lower() in text:
                print(rule_name)
                sys.exit(0)
    print("default")
except Exception:
    print("default")
PYEOF
)
  echo "[spawn] auto-timeout: type=$TASK_TYPE → ${TIMEOUT_MIN}min"
fi

# --- Dedup Check ---
if ! $FORCE_SPAWN && [ -f "$DEDUP_CHECK" ]; then
  DEDUP_RESULT=$(bash "$DEDUP_CHECK" "$TASK_ID" "$TASK_TEXT" 2>/dev/null || true)
  if [[ "$DEDUP_RESULT" == duplicate:* ]]; then
    MATCH_TASK=$(echo "$DEDUP_RESULT" | cut -d: -f2)
    MATCH_REASON=$(echo "$DEDUP_RESULT" | cut -d: -f3-)
    echo "DEDUP: $TASK_ID blocked — matches $MATCH_TASK ($MATCH_REASON)" >&2
    bash "$LOGGER" "$TASK_ID" dedup "Blocked: matches $MATCH_TASK ($MATCH_REASON)" 2>/dev/null || true
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
CLAUDE_MD="/Users/fonsecabc/.openclaw/workspace/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  { cat "$CLAUDE_MD"; echo -e "\n---\n"; echo "$TASK_TEXT"; } > "$TASK_PATH"
else
  echo "$TASK_TEXT" > "$TASK_PATH"
fi

# Source credentials for sub-agents
[ -f /Users/fonsecabc/.openclaw/workspace/.env.secrets ] && source /Users/fonsecabc/.openclaw/workspace/.env.secrets
[ -f /Users/fonsecabc/.openclaw/workspace/.env.linear ] && source /Users/fonsecabc/.openclaw/workspace/.env.linear

# Spawn with stream monitoring
cd "$CWD"

nohup bash -c "
  unset CLAUDECODE;
  claude --print --dangerously-skip-permissions --verbose --output-format stream-json --model '$SPAWN_MODEL' -p \"\$(cat '$TASK_PATH')\" 2> '$LOGS_DIR/${TASK_ID}-stderr.log' \
    | LOGS_DIR='$LOGS_DIR' python3 '$MONITOR' '${TASK_ID}';
  echo \"\${PIPESTATUS[0]}\" > '$LOGS_DIR/${TASK_ID}-exit-code';
" &>/dev/null &
AGENT_PID=$!

# Verify process started
sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent died immediately (PID=$AGENT_PID)" >&2
  cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null >&2
  exit 1
fi

# Register + log
bash "$REGISTRY" register "$TASK_ID" "$AGENT_PID" 0 "$LABEL" "$SOURCE" "$TIMEOUT_MIN"
bash "$LOGGER" "$TASK_ID" spawn "PID=$AGENT_PID timeout=${TIMEOUT_MIN}min src=$SOURCE model=$SPAWN_MODEL" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min, model=$SPAWN_MODEL)" progress 2>/dev/null || true

echo "[spawn] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min model=$SPAWN_MODEL"
echo "$AGENT_PID"
