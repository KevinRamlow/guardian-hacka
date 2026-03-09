#!/bin/bash
# Spawn Agent — Spawn OpenClaw native sub-agent for a task
# All spawns go through this script → state-tracked, PID-captured, Linear-logged
#
# Usage: spawn-agent.sh --task CAI-XX [--label desc] [--timeout 25] [--source auto-queue]
#        [--file path] [--force-spawn] [--force]
#        [--role developer|reviewer|architect|guardian-tuner|debugger]
#        [--mode yolo|interactive] "task text"
#
# --force / --force-spawn: bypass budget check and dedup check
# --role: select OpenClaw agent ID (each has dedicated workspace + SOUL.md)
# --mode yolo|interactive: yolo (default) runs autonomously; interactive posts Slack checkpoints
#
# Agents are OpenClaw native sub-agents spawned via `openclaw agent --agent <role>`.
# The gateway manages lifecycle. Context comes from the agent's workspace SOUL.md.
set -euo pipefail

REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh"
LOGGER="/Users/fonsecabc/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
TASKS_DIR="/Users/fonsecabc/.openclaw/tasks/spawn-tasks"
DEDUP_CHECK="/Users/fonsecabc/.openclaw/workspace/scripts/dedup-check.sh"

TIMEOUT_RULES="/Users/fonsecabc/.openclaw/workspace/config/timeout-rules.json"
INTERACTIVE_TEMPLATE="/Users/fonsecabc/.openclaw/workspace/templates/claude-md/interactive-mode.md"

TASK_ID="" LABEL="" TIMEOUT_MIN=25 EXPLICIT_TIMEOUT=false SOURCE="manual" TASK_TEXT="" TASK_FILE="" FORCE_SPAWN=false
ROLE="" AGENT_MODE="yolo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK_ID="$2"; shift 2 ;;
    --label)   LABEL="$2"; shift 2 ;;
    --timeout) TIMEOUT_MIN="$2"; EXPLICIT_TIMEOUT=true; shift 2 ;;
    --source)  SOURCE="$2"; shift 2 ;;
    --file)    TASK_FILE="$2"; shift 2 ;;
    --force-spawn) FORCE_SPAWN=true; shift ;;
    --force)   FORCE_SPAWN=true; shift ;;
    --role)    ROLE="$2"; shift 2 ;;
    --mode)    AGENT_MODE="$2"; shift 2 ;;
    --native)  shift ;;  # Accepted but ignored (always native now)
    --model)   shift 2 ;; # Accepted but ignored (model comes from agent config)
    --cwd)     shift 2 ;; # Accepted but ignored (workspace set per agent)
    -*)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)         TASK_TEXT="$1"; shift ;;
  esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: --task <CAI-XX> required" >&2; exit 1; }
[ -z "$TASK_TEXT" ] && [ -z "$TASK_FILE" ] && { echo "ERROR: Provide task text or --file <path>" >&2; exit 1; }
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$LABEL" ] && LABEL="$TASK_ID"

# --- Validate --role if specified ---
if [ -n "$ROLE" ]; then
  WORKSPACE="/Users/fonsecabc/.openclaw/workspace/workspace-${ROLE}"
  if [ ! -d "$WORKSPACE" ] || [ ! -f "$WORKSPACE/SOUL.md" ]; then
    echo "ERROR: Agent workspace not found: $WORKSPACE" >&2
    echo "  Available roles: $(ls -d /Users/fonsecabc/.openclaw/workspace/workspace-*/ 2>/dev/null | xargs -I{} basename {} | sed 's/workspace-//' | tr '\n' ' ' || echo 'none')" >&2
    exit 1
  fi
fi

# --- Adaptive Timeout Classification ---
TASK_TYPE="default"
if ! $EXPLICIT_TIMEOUT && [ -f "$TIMEOUT_RULES" ]; then
  TIMEOUT_MIN=$(python3 - "$TASK_TEXT" "$LABEL" "$TIMEOUT_RULES" << 'PYEOF'
import json, sys
text = (sys.argv[1] + " " + sys.argv[2]).lower()
rules_file = sys.argv[3]
try:
    rules = json.load(open(rules_file))["rules"]
    for rule_name in ["guardian_eval", "code_task", "analysis", "image_gen"]:
        rule = rules.get(rule_name, {})
        for kw in rule.get("keywords", []):
            if kw.lower() in text:
                print(rule["timeout_min"])
                sys.exit(0)
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

# --- Budget Check ---
if ! $FORCE_SPAWN; then
  BUDGET_CHECK=$(python3 - "$TIMEOUT_MIN" << 'PYEOF'
import json, sys
from pathlib import Path

timeout_min = float(sys.argv[1])
COST_PER_MIN = 0.08  # sonnet rate (all native agents use sonnet)

STATE_FILE = Path("/Users/fonsecabc/.openclaw/tasks/api-usage-state.json")
BUDGET_FILE = Path("/Users/fonsecabc/.openclaw/workspace/self-improvement/loop/budget-status.json")

try:
    state = json.loads(STATE_FILE.read_text())
    monthly_spend = float(state.get("monthly_total", 0.0))
except Exception:
    monthly_spend = 0.0

try:
    budget_cfg = json.loads(BUDGET_FILE.read_text())
    monthly_limit = float(budget_cfg.get("monthly_limit", 500.0))
    block_pct = float(budget_cfg.get("spawn_block_threshold_pct", 90.0))
    spawn_threshold = block_pct / 100.0
except Exception:
    monthly_limit = 500.0
    spawn_threshold = 0.90

estimated_cost = COST_PER_MIN * timeout_min
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

# --- Build task prompt ---
mkdir -p "$LOGS_DIR" "$TASKS_DIR"
FULL_PROMPT_FILE="$TASKS_DIR/${TASK_ID}-full-prompt.md"

{
  echo "# Task: $TASK_ID"
  echo "Timeout: ${TIMEOUT_MIN}min"
  echo ""
  echo "$TASK_TEXT"

  # Append interactive mode instructions if needed
  if [ "$AGENT_MODE" = "interactive" ] && [ -f "$INTERACTIVE_TEMPLATE" ]; then
    echo ""
    echo "---"
    cat "$INTERACTIVE_TEMPLATE"
  fi
} > "$FULL_PROMPT_FILE"

if [ "$AGENT_MODE" = "interactive" ]; then
  echo "[spawn] mode: interactive (checkpoints enabled)"
fi

# --- Spawn native OpenClaw agent ---
AGENT_ID="${ROLE:-main}"
TIMEOUT_SEC=$((TIMEOUT_MIN * 60))

nohup bash -c "
  ~/.nvm/versions/node/v22.13.1/bin/openclaw agent \
    --agent '$AGENT_ID' \
    --message \"\$(cat '$FULL_PROMPT_FILE')\" \
    --timeout $TIMEOUT_SEC \
    --json \
    > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log';
  EXIT_CODE=\$?;
  echo \"\$EXIT_CODE\" > '$LOGS_DIR/${TASK_ID}-exit-code';
" &>/dev/null &
AGENT_PID=$!

# Verify process started
sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent died immediately (PID=$AGENT_PID, agent=$AGENT_ID)" >&2
  cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null >&2
  exit 1
fi

# Register + store role in state
bash "$REGISTRY" register "$TASK_ID" "$AGENT_PID" 0 "$LABEL" "$SOURCE" "$TIMEOUT_MIN"
# Set role field in state (register doesn't support it positionally)
if [ -n "$ROLE" ]; then
  python3 -c "
import json
f = '/Users/fonsecabc/.openclaw/tasks/state.json'
d = json.load(open(f))
t = d['tasks'].get('$TASK_ID')
if t: t['role'] = '$ROLE'
json.dump(d, open(f, 'w'), indent=2)
" 2>/dev/null || true
fi
bash "$LOGGER" "$TASK_ID" spawn "PID=$AGENT_PID timeout=${TIMEOUT_MIN}min src=$SOURCE agent=$AGENT_ID$([ -n "$ROLE" ] && echo " role=$ROLE")" 2>/dev/null || true
bash "$LINEAR_LOG" "$TASK_ID" "Agent spawned: $LABEL (timeout=${TIMEOUT_MIN}min, agent=$AGENT_ID$([ -n "$ROLE" ] && echo ", role=$ROLE"))" progress 2>/dev/null || true

ROLE_INFO=""
[ -n "$ROLE" ] && ROLE_INFO=" role=$ROLE"
MODE_INFO=""
[ "$AGENT_MODE" = "interactive" ] && MODE_INFO=" mode=interactive"
echo "[spawn] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min agent=$AGENT_ID$ROLE_INFO$MODE_INFO"
echo "$AGENT_PID"
