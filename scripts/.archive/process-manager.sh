#!/bin/bash
# Process Manager — Tracks long-running processes (evals, pipelines, builds) independently of agents.
#
# Why: Sub-agents polling long processes waste tokens and hit timeouts.
# Solution: Agent registers process → exits → process-checker detects completion → dispatches fresh agent with results.
#
# Commands:
#   register  --pid <PID> --type <eval|pipeline|build|test> --task <AUTO-XX> [--result-path /path] [--metrics-path /path]
#             [--callback dispatch|notify|none] [--context "prompt for callback agent"] [--timeout 120]
#   status    [--json]                    Show all tracked processes
#   get       <proc-id>                   Get details of one process
#   complete  <proc-id> <exit-code>       Mark process as completed (called by checker)
#   remove    <proc-id>                   Remove from registry
#   list-done                              List completed processes not yet cleaned up
#
set -euo pipefail

REGISTRY_FILE="/Users/fonsecabc/.openclaw/tasks/process-registry.json"
LOCKFILE="/tmp/process-registry.lock"

# Ensure registry exists
[ -f "$REGISTRY_FILE" ] || echo '{"processes":{}}' > "$REGISTRY_FILE"

# Locking helper
locked_read() {
  exec 201>"$LOCKFILE"
  flock -w 5 201 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }
  cat "$REGISTRY_FILE"
}

locked_write() {
  cat > "$REGISTRY_FILE"
  exec 201>&-
}

CMD="${1:-help}"
shift || true

case "$CMD" in
  register)
    PID="" TYPE="" TASK_ID="" RESULT_PATH="" METRICS_PATH="" CALLBACK="dispatch" CONTEXT="" TIMEOUT_MIN=120
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --pid)          PID="$2"; shift 2 ;;
        --type)         TYPE="$2"; shift 2 ;;
        --task)         TASK_ID="$2"; shift 2 ;;
        --result-path)  RESULT_PATH="$2"; shift 2 ;;
        --metrics-path) METRICS_PATH="$2"; shift 2 ;;
        --callback)     CALLBACK="$2"; shift 2 ;;
        --context)      CONTEXT="$2"; shift 2 ;;
        --timeout)      TIMEOUT_MIN="$2"; shift 2 ;;
        *)              echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    [ -z "$PID" ] && { echo "ERROR: --pid required" >&2; exit 1; }
    [ -z "$TYPE" ] && { echo "ERROR: --type required" >&2; exit 1; }
    [ -z "$TASK_ID" ] && { echo "ERROR: --task required" >&2; exit 1; }

    # Verify PID is alive
    kill -0 "$PID" 2>/dev/null || { echo "ERROR: PID $PID is not alive" >&2; exit 1; }

    PROC_ID="proc-${TASK_ID}-$(date +%s)"
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    NOW_EPOCH=$(date +%s)

    DATA=$(locked_read)
    echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['processes']['$PROC_ID'] = {
    'pid': $PID,
    'type': '$TYPE',
    'taskId': '$TASK_ID',
    'command': '',
    'startedAt': '$NOW',
    'startedEpoch': $NOW_EPOCH,
    'timeoutMin': $TIMEOUT_MIN,
    'status': 'running',
    'resultPath': '''$RESULT_PATH''',
    'metricsPath': '''$METRICS_PATH''',
    'callbackType': '$CALLBACK',
    'callbackContext': '''$(echo "$CONTEXT" | sed "s/'/\\\\'/g")''',
    'exitCode': None,
    'completedAt': None,
    'callbackDispatched': False
}
json.dump(d, sys.stdout, indent=2)
" | locked_write

    echo "$PROC_ID"
    echo "[process-manager] Registered $PROC_ID: type=$TYPE task=$TASK_ID pid=$PID callback=$CALLBACK timeout=${TIMEOUT_MIN}min"
    ;;

  status)
    JSON_MODE=false
    [[ "${1:-}" == "--json" ]] && JSON_MODE=true

    DATA=$(locked_read)
    if $JSON_MODE; then
      echo "$DATA" | python3 -m json.tool
    else
      echo "$DATA" | python3 -c "
import json, sys, os, time
d = json.load(sys.stdin)
procs = d.get('processes', {})
if not procs:
    print('No tracked processes.')
    sys.exit(0)

now = int(time.time())
print(f'Tracked processes: {len(procs)}')
print(f'{\"\":-<80}')
for pid_key, p in sorted(procs.items(), key=lambda x: x[1].get('startedEpoch', 0)):
    proc_pid = p.get('pid', 0)
    status = p.get('status', 'unknown')
    age_min = (now - p.get('startedEpoch', now)) // 60
    timeout = p.get('timeoutMin', 0)

    # Check if PID is still alive
    alive = False
    try:
        os.kill(proc_pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        pass

    icon = {'running': '🔄', 'completed': '✅', 'failed': '❌', 'timeout': '⏰'}.get(status, '❓')
    alive_str = 'alive' if alive else 'DEAD'

    print(f'{icon} {pid_key}')
    print(f'   Task: {p.get(\"taskId\",\"?\")} | Type: {p.get(\"type\",\"?\")} | PID: {proc_pid} ({alive_str})')
    print(f'   Age: {age_min}min / {timeout}min | Status: {status}')
    print(f'   Callback: {p.get(\"callbackType\",\"none\")} | Dispatched: {p.get(\"callbackDispatched\", False)}')
    if p.get('resultPath'):
        exists = '✓' if os.path.exists(p['resultPath']) else '✗'
        print(f'   Result: {p[\"resultPath\"]} ({exists})')
    if p.get('metricsPath'):
        exists = '✓' if os.path.exists(p['metricsPath']) else '✗'
        print(f'   Metrics: {p[\"metricsPath\"]} ({exists})')
    if p.get('exitCode') is not None:
        print(f'   Exit: {p[\"exitCode\"]}')
    print()
"
    fi
    ;;

  get)
    PROC_ID="${1:-}"
    [ -z "$PROC_ID" ] && { echo "ERROR: process id required" >&2; exit 1; }
    DATA=$(locked_read)
    echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = d.get('processes', {}).get('$PROC_ID')
if not p:
    print('NOT_FOUND')
    sys.exit(1)
json.dump(p, sys.stdout, indent=2)
print()
"
    ;;

  complete)
    PROC_ID="${1:-}"
    EXIT_CODE="${2:-0}"
    [ -z "$PROC_ID" ] && { echo "ERROR: process id required" >&2; exit 1; }

    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    DATA=$(locked_read)
    echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = d.get('processes', {}).get('$PROC_ID')
if not p:
    sys.exit(1)
p['status'] = 'completed' if int('$EXIT_CODE') == 0 else 'failed'
p['exitCode'] = int('$EXIT_CODE')
p['completedAt'] = '$NOW'
json.dump(d, sys.stdout, indent=2)
" | locked_write
    echo "[process-manager] $PROC_ID completed (exit=$EXIT_CODE)"
    ;;

  remove)
    PROC_ID="${1:-}"
    [ -z "$PROC_ID" ] && { echo "ERROR: process id required" >&2; exit 1; }
    DATA=$(locked_read)
    echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d.get('processes', {}).pop('$PROC_ID', None)
json.dump(d, sys.stdout, indent=2)
" | locked_write
    echo "[process-manager] Removed $PROC_ID"
    ;;

  list-done)
    DATA=$(locked_read)
    echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
done = [(k, p) for k, p in d.get('processes', {}).items() if p.get('status') in ('completed', 'failed')]
if not done:
    print('No completed processes.')
else:
    for k, p in done:
        print(f'{k} | {p[\"taskId\"]} | {p[\"status\"]} | exit={p.get(\"exitCode\",\"?\")} | callback={p.get(\"callbackType\",\"none\")} dispatched={p.get(\"callbackDispatched\",False)}')
"
    ;;

  help|*)
    echo "Process Manager — Track long-running processes independently of agents"
    echo ""
    echo "Usage: process-manager.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  register  --pid <PID> --type <type> --task <AUTO-XX> [--result-path /path] [--metrics-path /path]"
    echo "            [--callback dispatch|notify|none] [--context 'prompt'] [--timeout 120]"
    echo "  status    [--json]         Show all tracked processes"
    echo "  get       <proc-id>        Get details of one process"
    echo "  complete  <proc-id> <code> Mark as completed"
    echo "  remove    <proc-id>        Remove from registry"
    echo "  list-done                  List completed processes"
    echo ""
    echo "Callback types:"
    echo "  dispatch — Spawn fresh agent with results when process completes (default)"
    echo "  notify   — Post to Linear + Slack only, no agent spawn"
    echo "  none     — Just track, no action on completion"
    ;;
esac
