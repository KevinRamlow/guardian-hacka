#!/bin/bash
# dispatcher.sh — Unified task dispatch: Linear + state + spawn + lifecycle watcher
#
# THE ONLY WAY to spawn agents. No exceptions.
#
# Modes:
#   Agent (default): dispatcher.sh --title "Fix X" --desc "Details" [--role developer]
#   Agent existing:  dispatcher.sh --task AUTO-XX [--file prompt.md] "task text"
#   Eval (agentless): dispatcher.sh --eval --title "Eval: post fix" [--parent AUTO-XX]
#                     [--eval-config path] [--eval-dataset file] [--eval-workers N]
#
# What it does (in order):
#   1. Validate inputs + dispatch guard (skipped for --eval)
#   2. Create Linear task (if --title, else verify --task exists)
#   3. Budget + dedup + capacity checks
#   4. Register in state.json via task-manager.sh
#   5. Build prompt file (agent mode) or prepare eval args (eval mode)
#   6. Spawn openclaw agent OR launch eval process directly
#   7. Launch watcher (auto-transitions state on death)
#   8. Log to Linear + disk
#
# Architecture:
#   - State mutations: ONLY through task-manager.sh (flock-protected)
#   - Linear logging: via skills/linear/scripts/linear.sh
#   - Slack reporting: NONE — heartbeat (HEARTBEAT.md) is the sole Slack reporter
#   - Exit-code watcher: transitions state immediately on agent death (no polling)
#
set -euo pipefail

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
TASK_MGR="$OC_HOME/workspace/scripts/task-manager.sh"
LINEAR_SCRIPT="$OC_HOME/workspace/skills/linear/scripts/linear.sh"
KILL_TREE="$OC_HOME/workspace/scripts/kill-agent-tree.sh"
TIMEOUT_RULES="$OC_HOME/workspace/config/timeout-rules.json"
LOGS_DIR="$OC_HOME/tasks/agent-logs"
TASKS_DIR="$OC_HOME/tasks/spawn-tasks"
DEDUP_DIR="$OC_HOME/tasks/dedup"
MASTER_LOG="$LOGS_DIR/master.log"

source "$OC_HOME/.env" 2>/dev/null || true

# ════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ════════════════════════════════════════════════════════

TITLE="" DESCRIPTION="" LABEL="" TASK_ID="" TASK_TEXT="" TASK_FILE=""
TIMEOUT_MIN=25 EXPLICIT_TIMEOUT=false ROLE="" MODE="yolo" FORCE=false
EVAL_MODE=false PARENT_TASK="" EVAL_CONFIG="" EVAL_DATASET="" EVAL_WORKERS=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --desc|--description) DESCRIPTION="$2"; shift 2 ;;
    --label)       LABEL="$2"; shift 2 ;;
    --task)        TASK_ID="$2"; shift 2 ;;
    --timeout)     TIMEOUT_MIN="$2"; EXPLICIT_TIMEOUT=true; shift 2 ;;
    --role)        ROLE="$2"; shift 2 ;;
    --mode)        MODE="$2"; shift 2 ;;
    --file)        TASK_FILE="$2"; shift 2 ;;
    --force)       FORCE=true; shift ;;
    --eval)        EVAL_MODE=true; shift ;;
    --parent)      PARENT_TASK="$2"; shift 2 ;;
    --eval-config) EVAL_CONFIG="$2"; shift 2 ;;
    --eval-dataset) EVAL_DATASET="$2"; shift 2 ;;
    --eval-workers) EVAL_WORKERS="$2"; shift 2 ;;
    -*)            echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *)             TASK_TEXT="$1"; shift ;;
  esac
done

# Validate: must have --title (new task) or --task (existing task)
if [ -z "$TITLE" ] && [ -z "$TASK_ID" ]; then
  echo "ERROR: --title 'X' --desc 'Y' (new task) or --task AUTO-XX (existing task) required" >&2
  exit 1
fi
[ -z "$DESCRIPTION" ] && DESCRIPTION="$TITLE"
[ -n "$TASK_FILE" ] && { [ -f "$TASK_FILE" ] && TASK_TEXT=$(cat "$TASK_FILE") || { echo "ERROR: File not found: $TASK_FILE" >&2; exit 1; }; }
[ -z "$TASK_TEXT" ] && TASK_TEXT="$DESCRIPTION"

# Eval mode defaults
if $EVAL_MODE; then
  ! $EXPLICIT_TIMEOUT && TIMEOUT_MIN=90
  [ -z "$LABEL" ] && [ -n "$TITLE" ] && LABEL="eval:${TITLE}"
fi

# ════════════════════════════════════════════════════════
# DISPATCH GUARD — Block forbidden patterns (skipped in --eval mode)
# ════════════════════════════════════════════════════════

if $EVAL_MODE; then
  # Eval mode: dispatcher itself launches the eval process — skip guard
  :
else
FORBIDDEN_PATTERNS=(
  "python.*run_eval"
  "python3.*run_eval"
  "nohup.*python"
  "nohup.*eval"
  "sessions_spawn"
)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if echo "$TASK_TEXT" | grep -qiE "$pattern"; then
    echo "BLOCKED: Task text contains forbidden pattern: $pattern" >&2
    echo "  Evals must be launched via --eval flag or via run-guardian-eval.sh inside a sub-agent." >&2
    exit 1
  fi
done
fi # end dispatch guard

# ════════════════════════════════════════════════════════
# ROLE VALIDATION
# ════════════════════════════════════════════════════════

if [ -n "$ROLE" ]; then
  WORKSPACE="$OC_HOME/workspace-${ROLE}"
  if [ ! -d "$WORKSPACE" ] || [ ! -f "$WORKSPACE/SOUL.md" ]; then
    echo "ERROR: Agent workspace not found: $WORKSPACE" >&2
    echo "  Available: $(ls -d "$OC_HOME"/workspace-*/ 2>/dev/null | xargs -I{} basename {} | sed 's/workspace-//' | tr '\n' ' ')" >&2
    exit 1
  fi
fi

# ════════════════════════════════════════════════════════
# ADAPTIVE TIMEOUT (from timeout-rules.json)
# ════════════════════════════════════════════════════════

if ! $EXPLICIT_TIMEOUT && [ -f "$TIMEOUT_RULES" ]; then
  TIMEOUT_MIN=$(python3 -c "
import json, sys
text = '''$TASK_TEXT $LABEL $TITLE'''.lower()
try:
    rules = json.load(open('$TIMEOUT_RULES'))['rules']
    for name in ['guardian_eval', 'code_task', 'analysis', 'image_gen']:
        rule = rules.get(name, {})
        for kw in rule.get('keywords', []):
            if kw.lower() in text:
                print(rule['timeout_min']); sys.exit(0)
    print(rules.get('default', {}).get('timeout_min', 25))
except Exception:
    print(25)
" 2>/dev/null || echo 25)
fi

# ════════════════════════════════════════════════════════
# STEP 1: CREATE LINEAR TASK (or verify existing)
# ════════════════════════════════════════════════════════

if [ -n "$TITLE" ]; then
  # New task — create in Linear
  echo "[dispatch] Creating Linear task: $TITLE"

  # Export for Python to read from env (avoids heredoc escaping issues)
  export _DISP_TITLE="$TITLE"
  export _DISP_DESC="$DESCRIPTION"

  RESULT=$(python3 << 'PYEOF'
import json, sys, subprocess, os

title = os.environ.get("_DISP_TITLE", "")
desc = os.environ.get("_DISP_DESC", "")
api_key = os.environ.get("LINEAR_API_KEY", "")

# Get team ID
r = subprocess.run(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
  "-H", f"Authorization: {api_key}", "-H", "Content-Type: application/json",
  "-d", '{"query":"query{teams(filter:{key:{eq:\\"AUTO\\"}},first:1){nodes{id}}}"}'],
  capture_output=True, text=True)
team_id = json.loads(r.stdout)["data"]["teams"]["nodes"][0]["id"]

# Get Todo state
r2 = subprocess.run(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
  "-H", f"Authorization: {api_key}", "-H", "Content-Type: application/json",
  "-d", '{"query":"query{workflowStates(filter:{name:{eq:\\"Todo\\"},team:{key:{eq:\\"AUTO\\"}}},first:1){nodes{id}}}"}'],
  capture_output=True, text=True)
state_id = json.loads(r2.stdout)["data"]["workflowStates"]["nodes"][0]["id"]

mutation = f'mutation{{issueCreate(input:{{teamId:"{team_id}",title:{json.dumps(title)},description:{json.dumps(desc)},stateId:"{state_id}"}}){{success issue{{identifier title}}}}}}'

r3 = subprocess.run(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
  "-H", f"Authorization: {api_key}", "-H", "Content-Type: application/json",
  "-d", json.dumps({"query": mutation})],
  capture_output=True, text=True)

# Validate response before printing
try:
    data = json.loads(r3.stdout)
    if "errors" in data:
        print(json.dumps({"error": data["errors"][0].get("message", "Unknown Linear API error")}), file=sys.stderr)
        sys.exit(1)
    # Verify the expected path exists
    _ = data["data"]["issueCreate"]["issue"]["identifier"]
except (KeyError, IndexError, json.JSONDecodeError) as e:
    print(f"Linear API response parse error: {e}", file=sys.stderr)
    print(f"Response: {r3.stdout[:500]}", file=sys.stderr)
    sys.exit(1)

print(r3.stdout)
PYEOF
)

  TASK_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueCreate',{}).get('issue',{}).get('identifier',''))" 2>/dev/null)

  if [ -z "$TASK_ID" ]; then
    echo "ERROR: Failed to create Linear task" >&2
    echo "$RESULT" >&2
    exit 1
  fi
  echo "[dispatch] Created $TASK_ID: $TITLE"
  [ -z "$LABEL" ] && LABEL="$(echo "$TITLE" | tr ' ' '-' | cut -c1-40)"
else
  # Existing task — verify it exists in Linear
  [ -z "$LABEL" ] && LABEL="$TASK_ID"
fi

# ════════════════════════════════════════════════════════
# STEP 2: BUDGET CHECK
# ════════════════════════════════════════════════════════

if ! $FORCE; then
  BUDGET_CHECK=$(python3 -c "
import json, os
from pathlib import Path

timeout_min = float($TIMEOUT_MIN)
COST_PER_MIN = 0.08
OC = os.environ.get('OPENCLAW_HOME', os.path.expanduser('~/.openclaw'))

try:
    state = json.loads(Path(f'{OC}/tasks/api-usage-state.json').read_text())
    monthly_spend = float(state.get('monthly_total', 0.0))
except Exception:
    monthly_spend = 0.0

try:
    cfg = json.loads(Path(f'{OC}/workspace/config/budget/budget-status.json').read_text())
    monthly_limit = float(cfg.get('monthly_limit', 500.0))
    block_pct = float(cfg.get('spawn_block_threshold_pct', 90.0))
except Exception:
    monthly_limit = 500.0
    block_pct = 90.0

threshold = monthly_limit * block_pct / 100.0
estimated = COST_PER_MIN * timeout_min

if monthly_spend + estimated > threshold:
    print(f'OVER:{monthly_spend:.2f}/{monthly_limit:.2f} est=+\${estimated:.2f}')
else:
    print(f'OK:{monthly_spend:.2f}/{monthly_limit:.2f}')
" 2>/dev/null || echo "OK:0/500")

  if [[ "$BUDGET_CHECK" == OVER:* ]]; then
    echo "BUDGET BLOCKED: $BUDGET_CHECK" >&2
    echo "  Use --force to bypass" >&2
    exit 2
  fi
fi

# ════════════════════════════════════════════════════════
# STEP 3: DEDUP CHECK
# ════════════════════════════════════════════════════════

if ! $FORCE; then
  mkdir -p "$DEDUP_DIR"
  DEDUP_RESULT=$(_TASK_ID="$TASK_ID" _TASK_TEXT="$TASK_TEXT" _HISTORY_FILE="$DEDUP_DIR/task-history.jsonl" \
    _EVENTS_FILE="$DEDUP_DIR/dedup-events.jsonl" _THRESHOLD="0.55" _LOOKBACK_HOURS="4" \
    python3 << 'PYEOF'
import hashlib, json, time, sys, re, os

task_id = os.environ.get("_TASK_ID", "")
task_text = os.environ.get("_TASK_TEXT", "")
history_file = os.environ.get("_HISTORY_FILE", "")
events_file = os.environ.get("_EVENTS_FILE", "")
threshold = float(os.environ.get("_THRESHOLD", "0.55"))
lookback_hours = int(os.environ.get("_LOOKBACK_HOURS", "4"))

now = int(time.time())
cutoff = now - (lookback_hours * 3600)

def normalize(text):
    text = text.lower()
    text = re.sub(r'[#*_`\-\[\]()>]', ' ', text)
    for p in ['linear task:', 'timeout:', 'task context', 'logging', 'log to:', 'linear-log.sh']:
        text = re.sub(re.escape(p), '', text)
    return re.sub(r'\s+', ' ', text).strip()

def extract_keywords(text):
    stopwords = {'the','a','an','is','are','was','were','be','been','being','have','has','had',
                 'do','does','did','will','would','could','should','may','might','shall','can',
                 'for','and','but','or','not','no','so','if','then','than','that','this','it',
                 'to','of','in','on','at','by','with','from','as','into','about','after','before',
                 'use','using','when','what','how','all','each','every','any','few','more','most',
                 'other','some','such','only','same','cai','minutes','task','minute','agent'}
    words = re.findall(r'[a-z][a-z0-9_]{2,}', normalize(text))
    return [w for w in words if w not in stopwords]

task_hash = hashlib.sha256(normalize(task_text).encode()).hexdigest()[:16]
task_keywords = extract_keywords(task_text)

recent = []
if os.path.exists(history_file):
    with open(history_file) as f:
        for line in f:
            try:
                e = json.loads(line.strip())
                if e.get('ts', 0) >= cutoff:
                    recent.append(e)
            except: continue

# Check 1: Exact hash
for e in recent:
    if e.get('hash') == task_hash and e.get('task_id') != task_id:
        print(f"duplicate:{e['task_id']}:exact_hash"); sys.exit(1)

# Check 2: Same task ID succeeded recently
for e in recent:
    if e.get('task_id') == task_id and e.get('status') not in ('failed','timeout','blocked','unknown'):
        print(f"duplicate:{e['task_id']}:same_id_success"); sys.exit(1)

# Check 3: Semantic similarity
for e in recent:
    kw = e.get('keywords', [])
    if kw and task_keywords:
        sim = len(set(task_keywords) & set(kw)) / len(set(task_keywords) | set(kw))
        if sim >= threshold:
            print(f"duplicate:{e['task_id']}:semantic={sim:.2f}"); sys.exit(1)

# Record
entry = {"task_id": task_id, "hash": task_hash, "keywords": task_keywords,
         "ts": now, "status": "spawned", "text_preview": normalize(task_text)[:200]}
with open(history_file, 'a') as f:
    f.write(json.dumps(entry) + '\n')

# Prune old entries
with open(history_file) as f:
    lines = f.readlines()
kept = [l for l in lines if json.loads(l.strip()).get('ts', 0) >= cutoff]
with open(history_file, 'w') as f:
    f.writelines(kept)

print("ok"); sys.exit(0)
PYEOF
) || true

  if [[ "$DEDUP_RESULT" == duplicate:* ]]; then
    echo "DEDUP BLOCKED: $DEDUP_RESULT" >&2
    exit 1
  fi
fi

# ════════════════════════════════════════════════════════
# STEP 4: CAPACITY CHECK
# ════════════════════════════════════════════════════════

SLOTS=$(bash "$TASK_MGR" slots)
if [ "$SLOTS" -le 0 ]; then
  echo "ERROR: No agent slots available ($(bash "$TASK_MGR" count) running)" >&2
  exit 1
fi

# Check if already running
HAS=$(bash "$TASK_MGR" has "$TASK_ID")
[ "$HAS" = "yes" ] && { echo "ERROR: $TASK_ID already running" >&2; exit 1; }
[ "$HAS" = "dead" ] && bash "$TASK_MGR" remove "$TASK_ID"

# ════════════════════════════════════════════════════════
# STEP 5: REGISTER IN STATE + BUILD PROMPT
# ════════════════════════════════════════════════════════

# Create task in state (idempotent — skips if exists)
CREATE_ARGS=(--task "$TASK_ID" --label "$LABEL" --timeout "$TIMEOUT_MIN")
[ -n "$PARENT_TASK" ] && CREATE_ARGS+=(--parent "$PARENT_TASK")
bash "$TASK_MGR" create "${CREATE_ARGS[@]}" 2>/dev/null || true

mkdir -p "$LOGS_DIR" "$TASKS_DIR"
PROMPT_FILE="$TASKS_DIR/${TASK_ID}-full-prompt.md"

{
  echo "# Task: $TASK_ID"
  echo "Timeout: ${TIMEOUT_MIN}min"
  echo ""
  echo "$TASK_TEXT"
} > "$PROMPT_FILE"

# ════════════════════════════════════════════════════════
# STEP 6: SPAWN (Agent or Eval)
# ════════════════════════════════════════════════════════

if $EVAL_MODE; then
  # ── EVAL MODE: Launch eval process directly, no agent ──
  EVAL_SCRIPT="$OC_HOME/workspace/scripts/run-guardian-eval.sh"
  if [ ! -f "$EVAL_SCRIPT" ]; then
    echo "ERROR: Eval script not found: $EVAL_SCRIPT" >&2
    exit 1
  fi

  # Build eval args
  EVAL_ARGS=()
  [ -n "$EVAL_CONFIG" ] && EVAL_ARGS+=(--config "$EVAL_CONFIG")
  [ -n "$EVAL_DATASET" ] && EVAL_ARGS+=(--dataset "$EVAL_DATASET")
  EVAL_ARGS+=(--workers "$EVAL_WORKERS")

  echo "[dispatch:eval] Launching eval for $TASK_ID (workers=$EVAL_WORKERS)..."

  # Source eval env + run
  nohup bash -c "
    source '${OC_HOME}/.env' 2>/dev/null || true
    source '${OC_HOME}/workspace/.env.guardian-eval' 2>/dev/null || true
    export OPENCLAW_SESSION_TYPE=subagent  # bypass main-thread guard
    bash '$EVAL_SCRIPT' ${EVAL_ARGS[*]} \
      > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log'
  " &>/dev/null &
  EVAL_PID=$!

  sleep 3
  if ! kill -0 "$EVAL_PID" 2>/dev/null; then
    echo "ERROR: Eval process died immediately (PID=$EVAL_PID)" >&2
    cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null >&2
    bash "$TASK_MGR" transition "$TASK_ID" failed --exit-code 1 2>/dev/null || true
    exit 1
  fi

  # Find the actual python eval PID (child of our bash wrapper)
  sleep 2
  PYTHON_PID=$(pgrep -f "run_eval.py.*content_moderation" | head -1 || echo "$EVAL_PID")

  # Build context for callback
  EVAL_CONTEXT="Agentless eval dispatched"
  [ -n "$PARENT_TASK" ] && EVAL_CONTEXT="Eval for $PARENT_TASK improvements"

  # Transition: todo → eval_running
  bash "$TASK_MGR" transition "$TASK_ID" eval_running \
    --process-pid "$PYTHON_PID" \
    --process-type eval \
    --context "$EVAL_CONTEXT" 2>/dev/null
  [ -n "$PARENT_TASK" ] && bash "$TASK_MGR" set-field "$TASK_ID" parentTask "$PARENT_TASK" 2>/dev/null || true

  # ── EVAL WATCHER: Detect eval death → callback_pending ──
  (
    # Wait for eval wrapper to die
    while kill -0 "$EVAL_PID" 2>/dev/null; do sleep 10; done
    wait "$EVAL_PID" 2>/dev/null
    EXIT_CODE=$?
    echo "$EXIT_CODE" > "$LOGS_DIR/${TASK_ID}-exit-code"

    # Also check if the python process is still alive (it may outlive the wrapper)
    if [ -n "$PYTHON_PID" ] && [ "$PYTHON_PID" != "$EVAL_PID" ]; then
      while kill -0 "$PYTHON_PID" 2>/dev/null; do sleep 10; done
      wait "$PYTHON_PID" 2>/dev/null || true
    fi

    # Check current status
    CURRENT_STATUS=$(python3 -c "
import json
try:
    d = json.load(open('$OC_HOME/tasks/state.json'))
    print(d['tasks'].get('$TASK_ID', {}).get('status', 'unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")

    if [ "$CURRENT_STATUS" != "eval_running" ]; then
      exit 0  # Already transitioned manually
    fi

    # Find latest metrics
    RUNS_DIR="$OC_HOME/workspace/guardian-agents-api-real/evals/.runs/content_moderation"
    LATEST_RUN=$(ls -td "$RUNS_DIR"/run_* 2>/dev/null | head -1)
    METRICS_PATH=""
    RESULT_PATH=""
    if [ -n "$LATEST_RUN" ] && [ -f "$LATEST_RUN/metrics.json" ]; then
      METRICS_PATH="$LATEST_RUN/metrics.json"
      RESULT_PATH="$LATEST_RUN"

      # Extract accuracy and store in history
      ACCURACY=$(python3 -c "
import json
m = json.load(open('$METRICS_PATH'))
s = m.get('summary_statistics', m)
print(f'{s.get(\"mean_aggregate_score\", 0) * 100:.1f}')
" 2>/dev/null || echo "0")

      bash "$TASK_MGR" add-history "$TASK_ID" "{\"type\":\"eval_complete\",\"accuracy\":$ACCURACY,\"run\":\"$(basename "$LATEST_RUN")\",\"exit_code\":$EXIT_CODE}" 2>/dev/null || true
    fi

    # Transition to callback_pending (heartbeat will spawn callback agent)
    bash "$TASK_MGR" transition "$TASK_ID" callback_pending --exit-code "$EXIT_CODE" 2>/dev/null
    [ -n "$METRICS_PATH" ] && bash "$TASK_MGR" set-field "$TASK_ID" metricsPath "$METRICS_PATH" 2>/dev/null || true
    [ -n "$RESULT_PATH" ] && bash "$TASK_MGR" set-field "$TASK_ID" resultPath "$RESULT_PATH" 2>/dev/null || true

    # Linear log
    if [ -n "$ACCURACY" ] && [ "$ACCURACY" != "0" ]; then
      bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Eval completed: accuracy=${ACCURACY}% (exit=$EXIT_CODE, run=$(basename "$LATEST_RUN"))" 2>/dev/null || true
    else
      bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Eval completed (exit=$EXIT_CODE)" 2>/dev/null || true
    fi

    TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    echo "[$TS] [eval-watcher] $TASK_ID: eval done (exit=$EXIT_CODE, accuracy=${ACCURACY:-?}%)" >> "$MASTER_LOG" 2>/dev/null || true

  ) &>/dev/null &

  # ── LOG + OUTPUT ──
  TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo "[$TS] [eval-dispatch] $TASK_ID: PID=$EVAL_PID python=$PYTHON_PID timeout=${TIMEOUT_MIN}min parent=${PARENT_TASK:-none}" >> "$MASTER_LOG" 2>/dev/null || true

  bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Eval launched (agentless, timeout=${TIMEOUT_MIN}min, workers=$EVAL_WORKERS$([ -n "$PARENT_TASK" ] && echo ", parent=$PARENT_TASK"))" 2>/dev/null || true
  bash "$LINEAR_SCRIPT" status "$TASK_ID" progress 2>/dev/null || true

  echo "[dispatch:eval] $TASK_ID PID=$EVAL_PID python=$PYTHON_PID timeout=${TIMEOUT_MIN}min${PARENT_TASK:+ parent=$PARENT_TASK}"
  echo "$EVAL_PID"

else
  # ── AGENT MODE: Standard agent spawn ──

AGENT_ID="${ROLE:-main}"
TIMEOUT_SEC=$((TIMEOUT_MIN * 60))

nohup bash -c "
  exec ~/.nvm/versions/node/v22.13.1/bin/openclaw agent \
    --agent '$AGENT_ID' \
    --message \"\$(cat '$PROMPT_FILE')\" \
    --timeout $TIMEOUT_SEC \
    --json \
    > '$LOGS_DIR/${TASK_ID}-output.log' 2> '$LOGS_DIR/${TASK_ID}-stderr.log';
" &>/dev/null &
AGENT_PID=$!

sleep 2
if ! kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "ERROR: Agent died immediately (PID=$AGENT_PID)" >&2
  cat "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null >&2
  bash "$TASK_MGR" transition "$TASK_ID" failed --exit-code 1 2>/dev/null || true
  exit 1
fi

# Register PID in state
bash "$TASK_MGR" register "$TASK_ID" "$AGENT_PID" 0 "$LABEL" "dispatch" "$TIMEOUT_MIN"
[ -n "$ROLE" ] && bash "$TASK_MGR" set-field "$TASK_ID" role "$ROLE" 2>/dev/null || true

# ════════════════════════════════════════════════════════
# STEP 7: EXIT-CODE WATCHER — Auto-transitions state on agent death
# This replaces supervisor.sh for completion detection.
# Heartbeat (HEARTBEAT.md) is the sole Slack reporter.
# ════════════════════════════════════════════════════════

FAILURE_PATTERNS='permission.*denied|not allowed|blocked|I need.*approval|I.m unable to|I cannot|access denied|authentication.*failed|EACCES|API Error|usage limits|rate limit|quota exceeded|invalid_request_error'
MIN_OUTPUT_BYTES=100

(
  # Wait for agent process to die
  while kill -0 "$AGENT_PID" 2>/dev/null; do sleep 5; done
  wait "$AGENT_PID" 2>/dev/null
  EXIT_CODE=$?
  echo "$EXIT_CODE" > "$LOGS_DIR/${TASK_ID}-exit-code"

  # Check current status — only transition if still agent_running
  CURRENT_STATUS=$(python3 -c "
import json
try:
    d = json.load(open('$OC_HOME/tasks/state.json'))
    print(d['tasks'].get('$TASK_ID', {}).get('status', 'unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")

  if [ "$CURRENT_STATUS" != "agent_running" ]; then
    exit 0  # Agent transitioned to eval_running or was manually changed
  fi

  # Check output quality (deterministic — no LLM needed)
  QUALITY=$(python3 -c "
import os, re
output = '$LOGS_DIR/${TASK_ID}-output.log'
stderr = '$LOGS_DIR/${TASK_ID}-stderr.log'
patterns = r'$FAILURE_PATTERNS'
min_bytes = $MIN_OUTPUT_BYTES

out_size = os.path.getsize(output) if os.path.exists(output) else 0
if out_size < 2:
    print('empty')
elif out_size < min_bytes:
    with open(output) as f:
        content = f.read()
    if re.search(patterns, content, re.IGNORECASE):
        print('blocked')
    else:
        print('small')
else:
    with open(output) as f:
        head = f.read(500)
    if re.search(patterns, head, re.IGNORECASE):
        print('blocked')
    else:
        print('success')
" 2>/dev/null || echo "unknown")

  # Transition state
  if [ "$QUALITY" = "success" ] || [ "$QUALITY" = "small" ]; then
    bash "$TASK_MGR" transition "$TASK_ID" done --exit-code "$EXIT_CODE" 2>/dev/null
    bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Agent completed (${QUALITY}, exit=$EXIT_CODE)" 2>/dev/null || true
    bash "$LINEAR_SCRIPT" status "$TASK_ID" done 2>/dev/null || true
  else
    bash "$TASK_MGR" transition "$TASK_ID" failed --exit-code 1 2>/dev/null
    bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Agent failed (${QUALITY}, exit=$EXIT_CODE)" 2>/dev/null || true
    bash "$LINEAR_SCRIPT" status "$TASK_ID" blocked 2>/dev/null || true
  fi

  # Disk log
  TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo "[$TS] [watcher] $TASK_ID: $QUALITY (exit=$EXIT_CODE)" >> "$MASTER_LOG" 2>/dev/null || true

) &>/dev/null &

# ════════════════════════════════════════════════════════
# STEP 8: LOG + OUTPUT
# ════════════════════════════════════════════════════════

TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "[$TS] [spawn] $TASK_ID: PID=$AGENT_PID timeout=${TIMEOUT_MIN}min agent=$AGENT_ID role=${ROLE:-none}" >> "$MASTER_LOG" 2>/dev/null || true

bash "$LINEAR_SCRIPT" comment "$TASK_ID" "Agent spawned (timeout=${TIMEOUT_MIN}min, agent=$AGENT_ID$([ -n "$ROLE" ] && echo ", role=$ROLE"))" 2>/dev/null || true
bash "$LINEAR_SCRIPT" status "$TASK_ID" progress 2>/dev/null || true

echo "[dispatch] $TASK_ID PID=$AGENT_PID timeout=${TIMEOUT_MIN}min agent=$AGENT_ID${ROLE:+ role=$ROLE}"
echo "$AGENT_PID"

fi # end EVAL_MODE vs AGENT_MODE
