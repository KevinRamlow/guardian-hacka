#!/bin/bash
# Peek at a running agent's activity in real-time
# Usage: agent-peek.sh CAI-XX        — show last 20 events
#        agent-peek.sh CAI-XX follow  — tail -f the activity stream
#        agent-peek.sh                — show all running agents with last event

LOGS_DIR="${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/agent-logs"
STATE_FILE="${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json"

if [ -z "$1" ]; then
  # Show all running agents with their last activity
  echo "=== Running Agents ==="
  python3 -c "
import json, os, time
try:
    d = json.load(open('$STATE_FILE'))
except: d = {'tasks': {}}
now = int(time.time())
found = False
for tid, t in d.get('tasks', {}).items():
    if t.get('status') not in ('agent_running', 'eval_running'):
        continue
    found = True
    pid = t.get('agentPid') or t.get('processPid') or 0
    age = (now - (t.get('startedEpoch') or t.get('createdEpoch', now))) // 60
    alive = True
    try: os.kill(pid, 0)
    except: alive = False
    status = '🟢' if alive else '🔴'

    activity = '$LOGS_DIR/' + tid + '-activity.jsonl'
    last_event = 'no activity log'
    if os.path.exists(activity):
        with open(activity) as f:
            lines = f.readlines()
            for line in reversed(lines):
                try:
                    evt = json.loads(line)
                    if '_summary' in evt:
                        last_event = evt['_summary']
                        break
                except: pass
            last_event = f'{len(lines)} events, last: {last_event}'

    output_size = 0
    out_f = '$LOGS_DIR/' + tid + '-output.log'
    if os.path.exists(out_f):
        output_size = os.path.getsize(out_f)

    role = t.get('role', 'main')
    print(f'{status} {tid} | PID={pid} | {age}min | role={role} | output={output_size}B | {last_event}')

if not found:
    print('No agents running')
" 2>/dev/null
  exit 0
fi

TASK_ID="$1"
MODE="${2:-last}"
ACTIVITY="$LOGS_DIR/${TASK_ID}-activity.jsonl"

if [ ! -f "$ACTIVITY" ]; then
  echo "No activity log for $TASK_ID"
  echo "Available logs:"
  ls "$LOGS_DIR/${TASK_ID}"* 2>/dev/null
  exit 1
fi

if [ "$MODE" = "follow" ] || [ "$MODE" = "f" ]; then
  echo "=== Following $TASK_ID activity (Ctrl+C to stop) ==="
  tail -f "$ACTIVITY" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line)
        ts = e.get('_ts', '??:??')
        summary = e.get('_summary', '')
        if summary:
            print(f'[{ts}] {summary}')
        elif e.get('type') == 'content_block_delta':
            pass  # skip streaming deltas
        else:
            t = e.get('type', '?')
            print(f'[{ts}] {t}')
    except:
        print(line.strip())
"
else
  echo "=== Last 20 events for $TASK_ID ==="
  tail -20 "$ACTIVITY" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line)
        ts = e.get('_ts', '??:??')
        summary = e.get('_summary', '')
        if summary:
            print(f'[{ts}] {summary}')
        else:
            t = e.get('type', '?')
            print(f'[{ts}] {t}')
    except:
        print(line.strip())
"
fi
