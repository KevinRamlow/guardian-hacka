#!/bin/bash
# Agent Registry — Single source of truth for all running agents
# All agent management scripts read/write through this interface
set -euo pipefail

REGISTRY_FILE="/root/.openclaw/tasks/agent-registry.json"
REGISTRY_LOCK="/tmp/agent-registry.lock"

# Initialize registry if missing
init_registry() {
  mkdir -p "$(dirname "$REGISTRY_FILE")"
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{"agents":{},"maxConcurrent":3}' > "$REGISTRY_FILE"
  fi
}

# Acquire lock (with timeout)
lock_registry() {
  exec 201>"$REGISTRY_LOCK"
  flock -w 5 201 || { echo "ERROR: Registry lock timeout" >&2; return 1; }
}

# Release lock
unlock_registry() {
  flock -u 201 2>/dev/null || true
}

# Register a new agent
# Usage: agent-registry.sh register <taskId> <pid> <bridgePid> <label> <source> <timeoutMin>
cmd_register() {
  local TASK_ID="${1:?Task ID required}"
  local PID="${2:?PID required}"
  local BRIDGE_PID="${3:-0}"
  local LABEL="${4:-$TASK_ID}"
  local SOURCE="${5:-manual}"
  local TIMEOUT_MIN="${6:-25}"

  init_registry
  lock_registry

  local NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local NOW_EPOCH=$(date +%s)

  _LABEL="$LABEL" _SOURCE="$SOURCE" _TASK_ID="$TASK_ID" _NOW="$NOW" python3 -c "
import json, os
f = '$REGISTRY_FILE'
d = json.load(open(f))
d['agents'][os.environ['_TASK_ID']] = {
    'pid': $PID,
    'bridgePid': $BRIDGE_PID,
    'label': os.environ['_LABEL'],
    'taskId': os.environ['_TASK_ID'],
    'source': os.environ['_SOURCE'],
    'spawnedAt': os.environ['_NOW'],
    'spawnedEpoch': $NOW_EPOCH,
    'lastHeartbeat': os.environ['_NOW'],
    'lastHeartbeatEpoch': $NOW_EPOCH,
    'timeoutMin': $TIMEOUT_MIN,
    'status': 'running'
}
json.dump(d, open(f, 'w'), indent=2)
print('OK')
"

  unlock_registry
  echo "Registered: $TASK_ID (PID=$PID, timeout=${TIMEOUT_MIN}min)"
}

# Remove an agent from registry
# Usage: agent-registry.sh remove <taskId>
cmd_remove() {
  local TASK_ID="${1:?Task ID required}"

  init_registry
  lock_registry

  python3 -c "
import json
f = '$REGISTRY_FILE'
d = json.load(open(f))
if '$TASK_ID' in d['agents']:
    del d['agents']['$TASK_ID']
    json.dump(d, open(f, 'w'), indent=2)
    print('Removed: $TASK_ID')
else:
    print('Not found: $TASK_ID')
"

  unlock_registry
}

# Update heartbeat for an agent
# Usage: agent-registry.sh heartbeat <taskId>
cmd_heartbeat() {
  local TASK_ID="${1:?Task ID required}"

  init_registry
  lock_registry

  local NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local NOW_EPOCH=$(date +%s)

  python3 -c "
import json
f = '$REGISTRY_FILE'
d = json.load(open(f))
if '$TASK_ID' in d['agents']:
    d['agents']['$TASK_ID']['lastHeartbeat'] = '$NOW'
    d['agents']['$TASK_ID']['lastHeartbeatEpoch'] = $NOW_EPOCH
    json.dump(d, open(f, 'w'), indent=2)
    print('OK')
else:
    print('Not found: $TASK_ID')
"

  unlock_registry
}

# List all registered agents (human-readable)
# Usage: agent-registry.sh list
cmd_list() {
  init_registry

  python3 -c "
import json, os, time
f = '$REGISTRY_FILE'
d = json.load(open(f))
agents = d.get('agents', {})
maxc = d.get('maxConcurrent', 3)
now = int(time.time())

print(f'Agents: {len(agents)}/{maxc} slots')
print()

if not agents:
    print('  (none)')
else:
    for tid, a in sorted(agents.items(), key=lambda x: x[1].get('spawnedEpoch', 0)):
        pid = a['pid']
        age_min = (now - a.get('spawnedEpoch', now)) // 60
        timeout = a.get('timeoutMin', 25)
        source = a.get('source', '?')
        try:
            os.kill(pid, 0)
            alive = True
        except (OSError, ProcessLookupError):
            alive = False
        icon = '🟢' if alive else '💀'
        print(f'  {icon} {tid}: PID={pid} {age_min}/{timeout}min src={source} alive={alive}')
"
}

# JSON output for other scripts to consume
# Usage: agent-registry.sh json
cmd_json() {
  init_registry
  cat "$REGISTRY_FILE"
}

# Get count of running agents (only those with alive PIDs)
# Usage: agent-registry.sh count
cmd_count() {
  init_registry

  python3 -c "
import json, os
f = '$REGISTRY_FILE'
d = json.load(open(f))
count = 0
for tid, a in d.get('agents', {}).items():
    try:
        os.kill(a['pid'], 0)
        count += 1
    except (OSError, ProcessLookupError):
        pass
print(count)
"
}

# Get available slots
# Usage: agent-registry.sh slots
cmd_slots() {
  init_registry

  python3 -c "
import json, os
f = '$REGISTRY_FILE'
d = json.load(open(f))
maxc = d.get('maxConcurrent', 3)
alive = 0
for tid, a in d.get('agents', {}).items():
    try:
        os.kill(a['pid'], 0)
        alive += 1
    except (OSError, ProcessLookupError):
        pass
print(max(0, maxc - alive))
"
}

# Check if a specific task is running
# Usage: agent-registry.sh has <taskId>
cmd_has() {
  local TASK_ID="${1:?Task ID required}"
  init_registry

  python3 -c "
import json, os
f = '$REGISTRY_FILE'
d = json.load(open(f))
a = d.get('agents', {}).get('$TASK_ID')
if a:
    try:
        os.kill(a['pid'], 0)
        print('yes')
    except (OSError, ProcessLookupError):
        print('dead')
else:
    print('no')
"
}

# Set max concurrent
# Usage: agent-registry.sh set-max <n>
cmd_set_max() {
  local N="${1:?Number required}"
  init_registry
  lock_registry

  python3 -c "
import json
f = '$REGISTRY_FILE'
d = json.load(open(f))
d['maxConcurrent'] = $N
json.dump(d, open(f, 'w'), indent=2)
print('maxConcurrent set to $N')
"

  unlock_registry
}

# Dispatch
case "${1:-help}" in
  register)   shift; cmd_register "$@" ;;
  remove)     shift; cmd_remove "$@" ;;
  heartbeat)  shift; cmd_heartbeat "$@" ;;
  list)       cmd_list ;;
  json)       cmd_json ;;
  count)      cmd_count ;;
  slots)      cmd_slots ;;
  has)        shift; cmd_has "$@" ;;
  set-max)    shift; cmd_set_max "$@" ;;
  help|*)
    cat <<EOF
Agent Registry — Single source of truth for running agents

Commands:
  register <taskId> <pid> [bridgePid] [label] [source] [timeoutMin]
  remove <taskId>
  heartbeat <taskId>
  list                  Human-readable status
  json                  Raw JSON output
  count                 Number of alive agents
  slots                 Available spawn slots
  has <taskId>          Check if task is running (yes/dead/no)
  set-max <n>           Set max concurrent agents

Registry file: $REGISTRY_FILE
EOF
    ;;
esac
