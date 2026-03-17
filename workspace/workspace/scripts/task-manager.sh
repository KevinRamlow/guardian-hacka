#!/bin/bash
# task-manager.sh — Single source of truth for all task state.
# Replaces agent-registry.sh + process-manager.sh with ONE unified state file.
#
# State machine:
#   todo → agent_running → [done | failed | blocked | eval_running]
#   eval_running → callback_pending → agent_running → ...
#   any → blocked (manual)
#
# Commands:
#   create    --task AUTO-XX [--label desc] [--callback dispatch|notify|none] [--context "..."]
#   transition <task-id> <new-status> [--pid N] [--process-pid N] [--process-type eval|pipeline]
#              [--result-path /p] [--metrics-path /p] [--exit-code N] [--context "..."]
#   get       <task-id>                   JSON of single task
#   list      [--status running] [--json] List tasks
#   slots                                 Available spawn slots
#   has       <task-id>                   Check: yes|dead|no
#   add-history <task-id> "JSON entry"    Append to history array
#   add-learning <task-id> "text"         Append to learnings array
#   remove    <task-id>                   Remove from state
#   cleanup   [--max-age 86400]           Remove old done/failed tasks
#   set-max   <n>                         Set maxConcurrent
#
set -euo pipefail

STATE_FILE="${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json"
LOCKFILE="/tmp/task-manager.lock"

# Ensure state file exists
init_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [ -f "$STATE_FILE" ] || echo '{"tasks":{},"maxConcurrent":3,"version":2}' > "$STATE_FILE"
}

# Locking
lock_state() {
  exec 201>"$LOCKFILE"
  flock -w 5 201 || { echo "ERROR: State lock timeout" >&2; return 1; }
}

unlock_state() {
  flock -u 201 2>/dev/null || true
}

# Valid transitions (single line for shell embedding)
VALID_TRANSITIONS='{"todo":["agent_running","eval_running","blocked","failed"],"agent_running":["done","failed","blocked","eval_running","timeout"],"eval_running":["callback_pending","done","failed","timeout","blocked"],"callback_pending":["agent_running","blocked","failed"],"done":["todo","agent_running"],"failed":["todo","agent_running"],"blocked":["todo","agent_running"],"timeout":["todo","agent_running","failed"]}'

CMD="${1:-help}"
shift || true

case "$CMD" in

  create)
    TASK_ID="" LABEL="" CALLBACK="dispatch" CONTEXT="" TIMEOUT_MIN=25 PARENT_TASK=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --task)     TASK_ID="$2"; shift 2 ;;
        --label)    LABEL="$2"; shift 2 ;;
        --callback) CALLBACK="$2"; shift 2 ;;
        --context)  CONTEXT="$2"; shift 2 ;;
        --timeout)  TIMEOUT_MIN="$2"; shift 2 ;;
        --parent)   PARENT_TASK="$2"; shift 2 ;;
        *)          echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    [ -z "$TASK_ID" ] && { echo "ERROR: --task required" >&2; exit 1; }
    [ -z "$LABEL" ] && LABEL="$TASK_ID"

    init_state
    lock_state

    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    NOW_EPOCH=$(date +%s)

    python3 -c "
import json, sys, os

f = '$STATE_FILE'
d = json.load(open(f))

if '$TASK_ID' in d['tasks']:
    print('EXISTS: $TASK_ID already in state', file=sys.stderr)
    sys.exit(1)

d['tasks']['$TASK_ID'] = {
    'status': 'todo',
    'linearId': '$TASK_ID',
    'agentPid': None,
    'processPid': None,
    'processType': None,
    'label': '''$(echo "$LABEL" | sed "s/'/\\\\'/g")''',
    'source': 'manual',
    'role': None,
    'model': None,
    'parentTask': '$PARENT_TASK' if '$PARENT_TASK' else None,
    'timeoutMin': $TIMEOUT_MIN,
    'createdAt': '$NOW',
    'createdEpoch': $NOW_EPOCH,
    'startedAt': None,
    'startedEpoch': None,
    'completedAt': None,
    'resultPath': None,
    'metricsPath': None,
    'callbackType': '$CALLBACK',
    'callbackContext': '''$(echo "$CONTEXT" | sed "s/'/\\\\'/g")''',
    'exitCode': None,
    'retries': 0,
    'extensions': 0,
    'warned80pct': False,
    'reportedAt': None,
    'history': [],
    'learnings': []
}
json.dump(d, open(f, 'w'), indent=2)
print('$TASK_ID')
"
    unlock_state
    ;;

  transition)
    TASK_ID="${1:-}"
    NEW_STATUS="${2:-}"
    shift 2 || true
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    [ -z "$NEW_STATUS" ] && { echo "ERROR: new-status required" >&2; exit 1; }

    # Parse optional args
    AGENT_PID="" PROCESS_PID="" PROCESS_TYPE="" RESULT_PATH="" METRICS_PATH="" EXIT_CODE="" CONTEXT="" SOURCE="" MODEL="" TIMEOUT="" SESSION_ID=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --pid)            AGENT_PID="$2"; shift 2 ;;
        --process-pid)    PROCESS_PID="$2"; shift 2 ;;
        --process-type)   PROCESS_TYPE="$2"; shift 2 ;;
        --result-path)    RESULT_PATH="$2"; shift 2 ;;
        --metrics-path)   METRICS_PATH="$2"; shift 2 ;;
        --exit-code)      EXIT_CODE="$2"; shift 2 ;;
        --context)        CONTEXT="$2"; shift 2 ;;
        --source)         SOURCE="$2"; shift 2 ;;
        --model)          MODEL="$2"; shift 2 ;;
        --timeout)        TIMEOUT="$2"; shift 2 ;;
        --session-id)     shift 2 ;; # Accepted but ignored (legacy compat)
        *)                shift ;;
      esac
    done

    init_state
    lock_state

    python3 -c "
import json, sys, time

VALID = $VALID_TRANSITIONS

f = '$STATE_FILE'
d = json.load(open(f))

task_id = '$TASK_ID'
new_status = '$NEW_STATUS'

if task_id not in d['tasks']:
    # Auto-create if transitioning to agent_running (for backward compat with spawn-agent.sh)
    if new_status == 'agent_running':
        now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        now_epoch = int(time.time())
        d['tasks'][task_id] = {
            'status': 'todo',
            'linearId': task_id,
            'agentPid': None,
                    'processPid': None,
            'processType': None,
            'label': task_id,
            'source': 'manual',
            'role': None,
    'model': None,
            'timeoutMin': 25,
            'createdAt': now,
            'createdEpoch': now_epoch,
            'startedAt': None,
            'startedEpoch': None,
            'completedAt': None,
            'resultPath': None,
            'metricsPath': None,
            'callbackType': 'dispatch',
            'callbackContext': '',
            'exitCode': None,
            'retries': 0,
            'extensions': 0,
            'warned80pct': False,
            'history': [],
            'learnings': []
        }
    else:
        print(f'NOT_FOUND: {task_id}', file=sys.stderr)
        sys.exit(1)

t = d['tasks'][task_id]
old_status = t['status']

# Validate transition
allowed = VALID.get(old_status, [])
if new_status not in allowed:
    print(f'INVALID: {old_status} → {new_status} (allowed: {allowed})', file=sys.stderr)
    sys.exit(1)

# Apply transition
t['status'] = new_status
now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
now_epoch = int(time.time())

if new_status == 'agent_running':
    t['startedAt'] = now
    t['startedEpoch'] = now_epoch
    t['agentPid'] = int('$AGENT_PID') if '$AGENT_PID' else t.get('agentPid')
    t['warned80pct'] = False
    if '$SOURCE': t['source'] = '$SOURCE'
    if '$MODEL': t['model'] = '$MODEL'
    if '$TIMEOUT': t['timeoutMin'] = int('$TIMEOUT')

elif new_status == 'eval_running':
    t['agentPid'] = None  # Agent exits
    t['processPid'] = int('$PROCESS_PID') if '$PROCESS_PID' else t.get('processPid')
    t['processType'] = '$PROCESS_TYPE' if '$PROCESS_TYPE' else t.get('processType')
    if '$RESULT_PATH': t['resultPath'] = '$RESULT_PATH'
    if '$METRICS_PATH': t['metricsPath'] = '$METRICS_PATH'
    if '$CONTEXT':
        t['callbackContext'] = '''$(echo "$CONTEXT" | sed "s/'/\\\\'/g")'''

elif new_status == 'callback_pending':
    t['processPid'] = None
    t['exitCode'] = int('$EXIT_CODE') if '$EXIT_CODE' else 0

elif new_status in ('done', 'failed', 'timeout'):
    t['completedAt'] = now
    t['agentPid'] = None
    t['processPid'] = None
    if '$EXIT_CODE': t['exitCode'] = int('$EXIT_CODE')
    if new_status in ('failed', 'timeout'):
        t['retries'] = t.get('retries', 0) + 1

elif new_status == 'todo':
    # Reset for re-queue
    t['agentPid'] = None
    t['processPid'] = None
    t['startedAt'] = None
    t['startedEpoch'] = None
    t['completedAt'] = None
    t['warned80pct'] = False

elif new_status == 'blocked':
    t['agentPid'] = None

json.dump(d, open(f, 'w'), indent=2)
print(f'{old_status} → {new_status}')
"
    unlock_state
    ;;

  get)
    TASK_ID="${1:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    init_state
    python3 -c "
import json, sys
d = json.load(open('$STATE_FILE'))
t = d['tasks'].get('$TASK_ID')
if not t:
    print('NOT_FOUND')
    sys.exit(1)
json.dump(t, sys.stdout, indent=2)
print()
"
    ;;

  list)
    STATUS_FILTER="" JSON_MODE=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --status) STATUS_FILTER="$2"; shift 2 ;;
        --json)   JSON_MODE=true; shift ;;
        *)        shift ;;
      esac
    done

    init_state

    if $JSON_MODE; then
      python3 -c "
import json, sys
d = json.load(open('$STATE_FILE'))
tasks = d.get('tasks', {})
sf = '$STATUS_FILTER'
if sf:
    tasks = {k: v for k, v in tasks.items() if v.get('status') == sf}
json.dump(tasks, sys.stdout, indent=2)
print()
"
    else
      python3 -c "
import json, os, time, sys
d = json.load(open('$STATE_FILE'))
tasks = d.get('tasks', {})
maxc = d.get('maxConcurrent', 3)
sf = '$STATUS_FILTER'
now = int(time.time())

if sf:
    tasks = {k: v for k, v in tasks.items() if v.get('status') == sf}

# Count alive agents
alive_count = 0
for tid, t in tasks.items():
    pid = t.get('agentPid') or t.get('processPid')
    if pid:
        try:
            os.kill(pid, 0)
            alive_count += 1
        except (OSError, ProcessLookupError):
            pass

print(f'Tasks: {len(tasks)} (slots: {maxc - alive_count}/{maxc})')
print(f'{\"\":-<80}')

status_icons = {
    'todo': '📋', 'agent_running': '🤖', 'eval_running': '🔬',
    'callback_pending': '📨', 'done': '✅', 'failed': '❌',
    'blocked': '🚫', 'timeout': '⏰'
}

# Sort: running first, then by creation time
def sort_key(item):
    status_order = {'agent_running': 0, 'eval_running': 1, 'callback_pending': 2,
                    'todo': 3, 'blocked': 4, 'failed': 5, 'timeout': 6, 'done': 7}
    return (status_order.get(item[1]['status'], 9), -item[1].get('createdEpoch', 0))

for tid, t in sorted(tasks.items(), key=sort_key):
    status = t.get('status', '?')
    icon = status_icons.get(status, '❓')
    label = t.get('label', tid)[:50]

    # Check PID
    pid = t.get('agentPid') or t.get('processPid')
    pid_str = ''
    if pid:
        try:
            os.kill(pid, 0)
            pid_str = f' PID={pid}(alive)'
        except (OSError, ProcessLookupError):
            pid_str = f' PID={pid}(DEAD)'

    # Age
    epoch = t.get('startedEpoch') or t.get('createdEpoch', now)
    age_min = (now - epoch) // 60
    timeout = t.get('timeoutMin', 25)

    # History
    hist_count = len(t.get('history', []))
    hist_str = f' cycles={hist_count}' if hist_count > 0 else ''

    print(f'{icon} {tid}: {status} | {label}')
    print(f'   {age_min}min/{timeout}min{pid_str}{hist_str}')
    if t.get('processType'):
        parent = f' parent={t[\"parentTask\"]}' if t.get('parentTask') else ''
        print(f'   process_type={t[\"processType\"]} callback={t.get(\"callbackType\",\"none\")}{parent}')
    elif t.get('parentTask'):
        print(f'   parent={t[\"parentTask\"]}')
    if t.get('history'):
        last = t['history'][-1]
        print(f'   last_result: {json.dumps(last)[:120]}')
    print()
"
    fi
    ;;

  slots)
    init_state
    python3 -c "
import json, os
d = json.load(open('$STATE_FILE'))
maxc = d.get('maxConcurrent', 3)
alive = 0
for tid, t in d.get('tasks', {}).items():
    if t.get('status') not in ('agent_running', 'callback_pending'):
        continue
    pid = t.get('agentPid')
    if pid:
        try:
            os.kill(pid, 0)
            alive += 1
        except (OSError, ProcessLookupError):
            pass
print(max(0, maxc - alive))
"
    ;;

  has)
    TASK_ID="${1:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    init_state
    python3 -c "
import json, os
d = json.load(open('$STATE_FILE'))
t = d['tasks'].get('$TASK_ID')
if not t:
    print('no')
elif t['status'] in ('done', 'failed', 'timeout'):
    print('completed')
elif t.get('agentPid'):
    try:
        os.kill(t['agentPid'], 0)
        print('yes')
    except (OSError, ProcessLookupError):
        print('dead')
elif t['status'] == 'eval_running' and t.get('processPid'):
    try:
        os.kill(t['processPid'], 0)
        print('eval_running')
    except (OSError, ProcessLookupError):
        print('dead')
else:
    print(t['status'])
"
    ;;

  add-history)
    TASK_ID="${1:-}"
    ENTRY="${2:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    [ -z "$ENTRY" ] && { echo "ERROR: JSON entry required" >&2; exit 1; }

    init_state
    lock_state

    python3 -c "
import json, sys
f = '$STATE_FILE'
d = json.load(open(f))
t = d['tasks'].get('$TASK_ID')
if not t:
    print('NOT_FOUND', file=sys.stderr)
    sys.exit(1)
try:
    entry = json.loads('''$ENTRY''')
except Exception:
    entry = {'note': '''$ENTRY'''}
t.setdefault('history', []).append(entry)
# Keep last 20 entries
t['history'] = t['history'][-20:]
json.dump(d, open(f, 'w'), indent=2)
print(f'History: {len(t[\"history\"])} entries')
"
    unlock_state
    ;;

  add-learning)
    TASK_ID="${1:-}"
    LEARNING="${2:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    [ -z "$LEARNING" ] && { echo "ERROR: learning text required" >&2; exit 1; }

    init_state
    lock_state

    python3 -c "
import json, sys
f = '$STATE_FILE'
d = json.load(open(f))
t = d['tasks'].get('$TASK_ID')
if not t:
    print('NOT_FOUND', file=sys.stderr)
    sys.exit(1)
learning = '''$(echo "$LEARNING" | sed "s/'/\\\\'/g")'''
t.setdefault('learnings', []).append(learning)
# Dedup and keep last 10
t['learnings'] = list(dict.fromkeys(t['learnings']))[-10:]
json.dump(d, open(f, 'w'), indent=2)
print(f'Learnings: {len(t[\"learnings\"])} entries')
"
    unlock_state
    ;;

  remove)
    TASK_ID="${1:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    init_state
    lock_state
    python3 -c "
import json
f = '$STATE_FILE'
d = json.load(open(f))
d['tasks'].pop('$TASK_ID', None)
json.dump(d, open(f, 'w'), indent=2)
print('Removed: $TASK_ID')
"
    unlock_state
    ;;

  cleanup)
    MAX_AGE=86400
    [[ "${1:-}" == "--max-age" ]] && MAX_AGE="${2:-86400}"
    init_state
    lock_state
    python3 -c "
import json, time
f = '$STATE_FILE'
d = json.load(open(f))
now = int(time.time())
cutoff = now - $MAX_AGE
removed = 0
for tid in list(d['tasks'].keys()):
    t = d['tasks'][tid]
    if t.get('status') in ('done', 'failed', 'timeout'):
        completed_epoch = t.get('startedEpoch', 0) + t.get('timeoutMin', 0) * 60
        if completed_epoch < cutoff:
            del d['tasks'][tid]
            removed += 1
json.dump(d, open(f, 'w'), indent=2)
print(f'Cleaned: {removed} tasks')
"
    unlock_state
    ;;

  set-max)
    N="${1:?Number required}"
    init_state
    lock_state
    python3 -c "
import json
f = '$STATE_FILE'
d = json.load(open(f))
d['maxConcurrent'] = $N
json.dump(d, open(f, 'w'), indent=2)
print('maxConcurrent=$N')
"
    unlock_state
    ;;

  # --- Backward compatibility shims for agent-registry.sh callers ---
  register)
    # register <taskId> <pid> <bridgePid> <label> <source> <timeoutMin>
    TASK_ID="${1:?Task ID required}"
    PID="${2:?PID required}"
    BRIDGE_PID="${3:-0}"
    LABEL="${4:-$TASK_ID}"
    SOURCE="${5:-manual}"
    TIMEOUT_MIN="${6:-25}"
    # Create if needed, then transition to agent_running
    init_state
    lock_state
    python3 -c "
import json, time, os
f = '$STATE_FILE'
d = json.load(open(f))
now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
now_epoch = int(time.time())
tid = '$TASK_ID'
if tid not in d['tasks']:
    d['tasks'][tid] = {
        'status': 'todo',
        'linearId': tid,
        'agentPid': None,
            'processPid': None,
        'processType': None,
        'label': '''$(echo "$LABEL" | sed "s/'/\\\\'/g")''',
        'source': '$SOURCE',
        'role': None,
    'model': None,
        'timeoutMin': $TIMEOUT_MIN,
        'createdAt': now,
        'createdEpoch': now_epoch,
        'startedAt': None,
        'startedEpoch': None,
        'completedAt': None,
        'resultPath': None,
        'metricsPath': None,
        'callbackType': 'dispatch',
        'callbackContext': '',
        'exitCode': None,
        'retries': 0,
        'extensions': 0,
        'warned80pct': False,
        'history': [],
        'learnings': []
    }

t = d['tasks'][tid]
t['status'] = 'agent_running'
t['agentPid'] = $PID
t['startedAt'] = now
t['startedEpoch'] = now_epoch
t['source'] = '$SOURCE'
t['timeoutMin'] = $TIMEOUT_MIN
t['label'] = '''$(echo "$LABEL" | sed "s/'/\\\\'/g")'''
json.dump(d, open(f, 'w'), indent=2)
print(f'Registered: $TASK_ID (PID=$PID, timeout=${TIMEOUT_MIN}min)')
"
    unlock_state
    ;;

  count)
    init_state
    python3 -c "
import json, os
d = json.load(open('$STATE_FILE'))
count = 0
for tid, t in d.get('tasks', {}).items():
    if t.get('status') != 'agent_running': continue
    pid = t.get('agentPid')
    if pid:
        try:
            os.kill(pid, 0)
            count += 1
        except (OSError, ProcessLookupError):
            pass
print(count)
"
    ;;

  set-field)
    # set-field <task-id> <field> <value>
    # Locked single-field write. Used by supervisor for reportedAt, warned80pct, etc.
    TASK_ID="${1:?Task ID required}"
    FIELD="${2:?Field name required}"
    VALUE="${3:?Value required}"
    init_state
    lock_state
    python3 -c "
import json
f = '$STATE_FILE'
d = json.load(open(f))
tid = '$TASK_ID'
if tid not in d.get('tasks', {}):
    print(f'NOT_FOUND: {tid}')
    exit(1)
field = '$FIELD'
raw = '''$VALUE'''
# Auto-detect type
if raw == 'True' or raw == 'true':
    val = True
elif raw == 'False' or raw == 'false':
    val = False
elif raw == 'None' or raw == 'null':
    val = None
else:
    try:
        val = int(raw)
    except ValueError:
        try:
            val = float(raw)
        except ValueError:
            val = raw
d['tasks'][tid][field] = val
json.dump(d, open(f, 'w'), indent=2)
print(f'{tid}.{field} = {val}')
"
    unlock_state
    ;;

  reopen)
    # Reopen a done/failed task for further work (same Linear task, same story)
    TASK_ID="${1:-}"
    [ -z "$TASK_ID" ] && { echo "ERROR: task-id required" >&2; exit 1; }
    init_state
    lock_state
    python3 -c "
import json, sys
f = '$STATE_FILE'
d = json.load(open(f))
tid = '$TASK_ID'
if tid not in d['tasks']:
    print(f'NOT_FOUND: {tid}', file=sys.stderr)
    sys.exit(1)
t = d['tasks'][tid]
old_status = t['status']
if old_status not in ('done', 'failed', 'timeout', 'blocked'):
    print(f'SKIP: {tid} is {old_status}, not reopenable', file=sys.stderr)
    sys.exit(1)
t['status'] = 'todo'
t['agentPid'] = None
t['processPid'] = None
t['startedAt'] = None
t['startedEpoch'] = None
t['completedAt'] = None
t['reportedAt'] = None
t['warned80pct'] = False
t['exitCode'] = None
# Keep history, learnings, storyId, label — those are the work trail
json.dump(d, open(f, 'w'), indent=2)
print(f'{old_status} → todo (reopened)')
"
    unlock_state
    ;;

  next-local-id)
    # Generate next local task ID (for tasks that don't need a Linear issue)
    init_state
    python3 -c "
import json, re
d = json.load(open('$STATE_FILE'))
max_n = 0
for tid in d.get('tasks', {}):
    m = re.match(r'AUTO-(\d+)', tid)
    if m: max_n = max(max_n, int(m.group(1)))
    m = re.match(r'LOCAL-(\d+)', tid)
    if m: max_n = max(max_n, int(m.group(1)))
print(f'LOCAL-{max_n + 1}')
"
    ;;

  json)
    init_state
    cat "$STATE_FILE"
    ;;

  help|*)
    cat <<'EOF'
task-manager.sh — Unified task state management

State machine:
  todo → agent_running → [done | failed | blocked | eval_running]
  todo → eval_running (agentless eval dispatch)
  eval_running → [callback_pending | done | failed | timeout | blocked]
  callback_pending → agent_running → ...

Commands:
  create     --task ID [--label desc] [--callback type] [--context "..."] [--parent TASK_ID]
  transition <task-id> <new-status> [--pid N] [--process-pid N] ...
  reopen     <task-id>              Reopen done/failed task (clears completedAt/reportedAt, keeps history)
  get        <task-id>              JSON of single task
  list       [--status X] [--json]  List all tasks
  slots                             Available spawn slots
  has        <task-id>              Check status: yes|dead|no|eval_running|completed
  add-history  <task-id> "JSON"     Append to history
  add-learning <task-id> "text"     Append to learnings
  remove     <task-id>              Remove task
  cleanup    [--max-age 86400]      Remove old completed tasks
  set-field  <task-id> <field> <val> Set single field (locked)
  set-max    <n>                    Set max concurrent
  next-local-id                     Generate next LOCAL-N ID (no Linear task)
  register   <taskId> <pid> <bridgePid> <label> <source> <timeoutMin>
  count                             Alive agent count
  json                              Raw state file
EOF
    ;;
esac
