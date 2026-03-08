#!/bin/bash
# Spawn Agent — Unified spawn wrapper for all agent creation
# All spawns go through this script → registry-tracked, PID-captured, Linear-logged
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue] [--model model] [--cwd dir] [--file path] [--force-spawn] [--force] "task text"
#
# --force / --force-spawn: bypass budget check and dedup check (use for critical spawns)
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
    --force)   FORCE_SPAWN=true; shift ;;
    -*)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)         TASK_TEXT="$1"; shift ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task <CAI-XX> required" >&2; exit 1; }
[ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ] && { echo "ERROR: Provide task text or --file <path>" >&2; exit 1; }
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$LABEL" ] && LABEL="$TASK_ID"

# --- Adaptive Timeout Classification ---
# Only auto-classify if --timeout was not explicitly passed
TASK_TYPE="default"
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

# --- Model Selection based on task type (if not explicitly set) ---
if [ -z "$MODEL" ]; then
  case "$TASK_TYPE" in
    guardian_eval) SPAWN_MODEL="claude-haiku-4-5-20251001" ;;
    analysis)     SPAWN_MODEL="claude-haiku-4-5-20251001" ;;
    code_task)    SPAWN_MODEL="claude-sonnet-4-6" ;;
    *)            SPAWN_MODEL="claude-sonnet-4-6" ;;
  esac
else
  SPAWN_MODEL="$MODEL"
fi

# --- Budget Caps per task type ---
case "$TASK_TYPE" in
  guardian_eval) MAX_BUDGET="2.00" ;;
  analysis)     MAX_BUDGET="1.00" ;;
  code_task)    MAX_BUDGET="3.00" ;;
  *)            MAX_BUDGET="2.00" ;;
esac

# --- Tool restrictions per task type ---
# Block polling tools (Task, TaskOutput, TaskStop) to prevent token waste on long-running processes
# Block Agent spawning to prevent recursive sub-agent spawning
DISALLOWED_TOOLS=""
case "$TASK_TYPE" in
  guardian_eval)
    # Evals take 30-40min. Hard-block all polling/waiting tools.
    DISALLOWED_TOOLS="Task,TaskOutput,TaskStop,TaskCreate,TaskUpdate,Agent,EnterPlanMode,WebSearch,WebFetch"
    ;;
  analysis)
    # Analysis should be quick, no sub-agents or background tasks
    DISALLOWED_TOOLS="Task,TaskOutput,TaskStop,TaskCreate,TaskUpdate,Agent,EnterPlanMode"
    ;;
  *)
    # All other types: block recursive agent spawning
    DISALLOWED_TOOLS="Agent,EnterPlanMode"
    ;;
esac

# --- Budget Check ---
# Estimate task cost and verify monthly spend won't exceed configured threshold.
# Bypass with --force or --force-spawn.
if ! $FORCE_SPAWN; then
  BUDGET_CHECK=$(python3 - "$SPAWN_MODEL" "$TIMEOUT_MIN" "$TASK_TYPE" << 'PYEOF'
import json, sys
from pathlib import Path

model = sys.argv[1]
timeout_min = float(sys.argv[2])
task_type = sys.argv[3]

STATE_FILE = Path("/Users/fonsecabc/.openclaw/tasks/api-usage-state.json")
BUDGET_FILE = Path("/Users/fonsecabc/.openclaw/workspace/self-improvement/loop/budget-status.json")

# Estimated cost per minute by model (USD/min, empirical from agent usage patterns)
COST_PER_MIN = {
    "claude-opus-4-6":          0.50,
    "claude-sonnet-4-6":        0.08,
    "claude-sonnet-4-5":        0.08,
    "claude-haiku-4-5-20251001": 0.02,
}
DEFAULT_COST_PER_MIN = 0.08

try:
    state = json.loads(STATE_FILE.read_text())
    monthly_spend = float(state.get("monthly_total", 0.0))
except Exception:
    monthly_spend = 0.0

try:
    budget_cfg = json.loads(BUDGET_FILE.read_text())
    monthly_limit = float(budget_cfg.get("monthly_limit", 500.0))
    # spawn_block_threshold_pct: % of monthly budget at which new spawns are blocked (default 90%)
    block_pct = float(budget_cfg.get("spawn_block_threshold_pct", 90.0))
    spawn_threshold = block_pct / 100.0
except Exception:
    monthly_limit = 500.0
    spawn_threshold = 0.90

cost_per_min = COST_PER_MIN.get(model, DEFAULT_COST_PER_MIN)
estimated_cost = cost_per_min * timeout_min
threshold_usd = monthly_limit * spawn_threshold
budget_after = monthly_spend + estimated_cost

if budget_after > threshold_usd:
    remaining = threshold_usd - monthly_spend
    print(f"over_budget:spend=${monthly_spend:.2f} limit=${monthly_limit:.2f} threshold=${threshold_usd:.2f} ({block_pct:.0f}%) est=+${estimated_cost:.2f} remaining=${max(0, remaining):.2f}")
else:
    pct = (monthly_spend / monthly_limit * 100) if monthly_limit > 0 else 0
    print(f"ok:${monthly_spend:.2f}/${monthly_limit:.2f} ({pct:.1f}%) est=+${estimated_cost:.2f} threshold=${threshold_usd:.2f}")
PYEOF
  )
  if [[ "$BUDGET_CHECK" == over_budget:* ]]; then
    BUDGET_REASON=$(echo "$BUDGET_CHECK" | cut -d: -f2-)
    echo "BUDGET: $TASK_ID blocked — $BUDGET_REASON" >&2
    echo "  → Use --force to bypass budget check" >&2
    bash "$LOGGER" "$TASK_ID" budget_skip "Blocked by budget: $BUDGET_REASON" 2>/dev/null || true
    bash "$LINEAR_LOG" "$TASK_ID" "Spawn blocked: budget limit. $BUDGET_REASON. Use --force to override." progress 2>/dev/null || true
    exit 2
  else
    BUDGET_STATUS=$(echo "$BUDGET_CHECK" | cut -d: -f2-)
    echo "[spawn] budget: $BUDGET_STATUS"
  fi
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

# --- Prepare task file for logging/debugging ---
mkdir -p "$LOGS_DIR" "$TASKS_DIR"
TASK_PATH="$TASKS_DIR/${TASK_ID}.md"
CLAUDE_MD="/Users/fonsecabc/.openclaw/workspace/CLAUDE.md"
echo "$TASK_TEXT" > "$TASK_PATH"

# --- Build stable context for --append-system-prompt (cached by API) ---
STABLE_CONTEXT=""
TEMPLATE_DIR="/Users/fonsecabc/.openclaw/workspace/templates/claude-md"
if [ -f "$TEMPLATE_DIR/base.md" ]; then
  STABLE_CONTEXT="$(cat "$TEMPLATE_DIR/base.md")"
  # Add task-type-specific template
  if [ -f "$TEMPLATE_DIR/${TASK_TYPE}.md" ]; then
    STABLE_CONTEXT+=$'\n'"$(cat "$TEMPLATE_DIR/${TASK_TYPE}.md")"
  fi
  # Add error handling
  if [ -f "$TEMPLATE_DIR/error-handling.md" ]; then
    STABLE_CONTEXT+=$'\n'"$(cat "$TEMPLATE_DIR/error-handling.md")"
  fi
else
  # Fallback to monolithic CLAUDE.md
  [ -f "$CLAUDE_MD" ] && STABLE_CONTEXT="$(cat "$CLAUDE_MD")"
fi

# Add relevant knowledge files
KNOWLEDGE_DIR="/Users/fonsecabc/.openclaw/workspace/knowledge"
if echo "$TASK_TEXT $LABEL" | grep -qiE 'guardian|eval|moderation'; then
  [ -f "$KNOWLEDGE_DIR/guardian-agents-api.map.md" ] && STABLE_CONTEXT+=$'\n'"$(cat "$KNOWLEDGE_DIR/guardian-agents-api.map.md")"
  [ -f "$KNOWLEDGE_DIR/eval-patterns.md" ] && STABLE_CONTEXT+=$'\n'"$(cat "$KNOWLEDGE_DIR/eval-patterns.md")"
fi
[ -f "$KNOWLEDGE_DIR/common-errors.md" ] && STABLE_CONTEXT+=$'\n'"$(cat "$KNOWLEDGE_DIR/common-errors.md")"

# Write stable context to a temp file for nohup (avoids quoting issues)
STABLE_CONTEXT_FILE="$TASKS_DIR/${TASK_ID}-system-prompt.md"
echo "$STABLE_CONTEXT" > "$STABLE_CONTEXT_FILE"

# Source credentials for sub-agents
[ -f /Users/fonsecabc/.openclaw/workspace/.env.secrets ] && source /Users/fonsecabc/.openclaw/workspace/.env.secrets
[ -f /Users/fonsecabc/.openclaw/workspace/.env.linear ] && source /Users/fonsecabc/.openclaw/workspace/.env.linear

# --- Build MCP config for sub-agents (MySQL access) ---
MCP_CONFIG_FILE="$TASKS_DIR/${TASK_ID}-mcp.json"
cat > "$MCP_CONFIG_FILE" << MCPEOF
{
  "mcpServers": {
    "mysql": {
      "command": "npx",
      "args": ["-y", "@berthojoris/mcp-mysql-server"],
      "env": {
        "MYSQL_HOST": "10.12.80.3",
        "MYSQL_PORT": "3306",
        "MYSQL_USER": "caio.fonseca",
        "MYSQL_PASSWORD": "${MYSQL_PASSWORD:-}",
        "MYSQL_DATABASE": "db-maestro-prod"
      }
    }
  }
}
MCPEOF

# Spawn with stream monitoring + MCP servers
cd "$CWD"

# Build disallowed tools flag
DISALLOW_FLAG=""
if [ -n "$DISALLOWED_TOOLS" ]; then
  DISALLOW_FLAG="--disallowedTools $DISALLOWED_TOOLS"
fi

nohup bash -c "
  unset CLAUDECODE;
  claude --print --dangerously-skip-permissions --verbose --output-format stream-json \
    --append-system-prompt \"\$(cat '$STABLE_CONTEXT_FILE')\" \
    --model '$SPAWN_MODEL' \
    --max-budget-usd '$MAX_BUDGET' \
    --mcp-config '$MCP_CONFIG_FILE' \
    $DISALLOW_FLAG \
    -p \"\$(cat '$TASK_PATH')\" 2> '$LOGS_DIR/${TASK_ID}-stderr.log' \
    | LOGS_DIR='$LOGS_DIR' python3 '$MONITOR' '${TASK_ID}';
  echo \"\${PIPESTATUS[0]}\" > '$LOGS_DIR/${TASK_ID}-exit-code';
  rm -f '$MCP_CONFIG_FILE';
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
bash "$LOGGER" "$TASK_ID" spawn "PID=$AGENT_PID timeout=${TIMEOUT_MIN}min src=$SOURCE model=$SPAWN_MODEL budget=$MAX_BUDGET" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min, model=$SPAWN_MODEL, budget=\$$MAX_BUDGET)" progress 2>/dev/null || true

BLOCKED_INFO=""
[ -n "$DISALLOWED_TOOLS" ] && BLOCKED_INFO=" blocked=$DISALLOWED_TOOLS"
echo "[spawn] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min model=$SPAWN_MODEL budget=\$$MAX_BUDGET$BLOCKED_INFO"
echo "$AGENT_PID"
