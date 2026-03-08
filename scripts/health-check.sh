#!/bin/bash
# health-check.sh — Comprehensive health monitoring for the agent system
# Validates: registry integrity, watchdog status, orphaned tasks, log sizes
# Returns: exit 0 (healthy) or exit 1 (issues found)
# Usage: bash health-check.sh [--json] [--verbose]
set -uo pipefail

REGISTRY_FILE="/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
REGISTRY_CMD="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
WATCHDOG_LOG="$LOGS_DIR/watchdog.log"
MAX_LOG_SIZE_MB=50
WATCHDOG_MAX_AGE_SEC=300  # 5 minutes
STALE_PID_THRESHOLD=0     # any stale PID is a problem

JSON_MODE=false
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --verbose) VERBOSE=true ;;
  esac
done

ISSUES=0
WARNINGS=0
ALERTS=()

alert() {
  local severity="$1" msg="$2"
  ALERTS+=("[$severity] $msg")
  if [ "$severity" = "CRITICAL" ] || [ "$severity" = "ERROR" ]; then
    ((ISSUES++))
  else
    ((WARNINGS++))
  fi
  $VERBOSE && echo "  $severity: $msg" || true
}

# === Check 1: Registry file integrity ===
check_registry_integrity() {
  $VERBOSE && echo "Checking registry integrity..."

  if [ ! -f "$REGISTRY_FILE" ]; then
    alert "ERROR" "Registry file missing: $REGISTRY_FILE"
    return
  fi

  # Validate JSON
  if ! python3 -c "import json; json.load(open('$REGISTRY_FILE'))" 2>/dev/null; then
    alert "CRITICAL" "Registry file is corrupted (invalid JSON)"
    return
  fi

  # Check for stale PIDs (registered but process dead)
  local stale_count
  stale_count=$(python3 -c "
import json, os
d = json.load(open('$REGISTRY_FILE'))
stale = 0
for tid, a in d.get('agents', {}).items():
    try:
        os.kill(a['pid'], 0)
    except (OSError, ProcessLookupError):
        stale += 1
        print(f'  Stale: {tid} PID={a[\"pid\"]}')
print(f'STALE_COUNT={stale}')
" 2>/dev/null)

  local count
  count=$(echo "$stale_count" | grep "STALE_COUNT=" | cut -d= -f2)
  if [ "${count:-0}" -gt "$STALE_PID_THRESHOLD" ]; then
    alert "ERROR" "Registry has $count stale PIDs (dead processes still registered)"
    # Print details in verbose
    $VERBOSE && echo "$stale_count" | grep "Stale:" || true
  fi

  # Check for agents exceeding their timeout
  local overtime
  overtime=$(python3 -c "
import json, os, time
d = json.load(open('$REGISTRY_FILE'))
now = int(time.time())
overtime = 0
for tid, a in d.get('agents', {}).items():
    age_min = (now - a.get('spawnedEpoch', now)) // 60
    timeout = a.get('timeoutMin', 25)
    if age_min > timeout + 5:  # 5min grace
        try:
            os.kill(a['pid'], 0)
            print(f'  Overtime: {tid} running {age_min}min (limit={timeout}min)')
            overtime += 1
        except:
            pass
print(f'OVERTIME_COUNT={overtime}')
" 2>/dev/null)

  local ot_count
  ot_count=$(echo "$overtime" | grep "OVERTIME_COUNT=" | cut -d= -f2)
  if [ "${ot_count:-0}" -gt 0 ]; then
    alert "WARN" "$ot_count agent(s) running past their timeout (watchdog may be stuck)"
    $VERBOSE && echo "$overtime" | grep "Overtime:" || true
  fi
}

# === Check 2: Watchdog last-run timestamp ===
check_watchdog_status() {
  $VERBOSE && echo "Checking watchdog status..."

  if [ ! -f "$WATCHDOG_LOG" ]; then
    alert "ERROR" "Watchdog log missing — watchdog may have never run"
    return
  fi

  local last_mod
  last_mod=$(stat -c %Y "$WATCHDOG_LOG" 2>/dev/null || echo 0)
  local now
  now=$(date +%s)
  local age=$(( now - last_mod ))

  if [ "$age" -gt "$WATCHDOG_MAX_AGE_SEC" ]; then
    local age_min=$(( age / 60 ))
    alert "CRITICAL" "Watchdog last ran ${age_min}min ago (threshold: $((WATCHDOG_MAX_AGE_SEC / 60))min)"
  fi

  # Check if watchdog cron is installed
  if ! crontab -l 2>/dev/null | grep -q "agent-watchdog-v2.sh"; then
    alert "ERROR" "Watchdog cron job not installed"
  fi

  # Check auto-queue cron
  if ! crontab -l 2>/dev/null | grep -q "auto-queue-v2.sh"; then
    alert "WARN" "Auto-queue cron job not installed"
  fi
}

# === Check 3: Orphaned In Progress tasks in Linear ===
check_orphaned_linear_tasks() {
  $VERBOSE && echo "Checking for orphaned Linear tasks..."

  # Only run if linear CLI available
  if ! command -v linear &>/dev/null; then
    $VERBOSE && echo "  Skipped: linear CLI not available"
    return
  fi

  local in_progress
  in_progress=$(linear issue list --status "In Progress" --team CAI --json 2>/dev/null | python3 -c "
import json, sys
try:
    tasks = json.load(sys.stdin)
except:
    sys.exit(0)
if not isinstance(tasks, list):
    sys.exit(0)
for t in tasks:
    tid = t.get('identifier', t.get('id', ''))
    print(tid)
" 2>/dev/null) || true

  if [ -z "$in_progress" ]; then
    return
  fi

  # Cross-reference with registry
  local registry_tasks
  registry_tasks=$(python3 -c "
import json
try:
    d = json.load(open('$REGISTRY_FILE'))
    for tid in d.get('agents', {}):
        print(tid)
except:
    pass
" 2>/dev/null)

  local orphans=0
  while IFS= read -r task; do
    [ -z "$task" ] && continue
    if ! echo "$registry_tasks" | grep -q "^${task}$"; then
      alert "WARN" "Linear task $task is In Progress but not in agent registry (orphaned?)"
      ((orphans++))
    fi
  done <<< "$in_progress"

  if [ "$orphans" -gt 3 ]; then
    alert "ERROR" "$orphans orphaned In Progress tasks — linear-sync may be broken"
  fi
}

# === Check 4: Agent log file sizes ===
check_log_sizes() {
  $VERBOSE && echo "Checking log file sizes..."

  if [ ! -d "$LOGS_DIR" ]; then
    alert "WARN" "Logs directory missing: $LOGS_DIR"
    return
  fi

  local total_size_kb
  total_size_kb=$(du -sk "$LOGS_DIR" 2>/dev/null | awk '{print $1}')
  local total_size_mb=$(( ${total_size_kb:-0} / 1024 ))

  if [ "$total_size_mb" -gt 500 ]; then
    alert "ERROR" "Logs directory is ${total_size_mb}MB — needs cleanup"
  elif [ "$total_size_mb" -gt 200 ]; then
    alert "WARN" "Logs directory is ${total_size_mb}MB — consider cleanup"
  fi

  # Find individual large log files
  local large_files
  large_files=$(find "$LOGS_DIR" -type f -size +${MAX_LOG_SIZE_MB}M 2>/dev/null)
  if [ -n "$large_files" ]; then
    local count
    count=$(echo "$large_files" | wc -l)
    alert "ERROR" "$count log file(s) exceed ${MAX_LOG_SIZE_MB}MB (runaway logs detected)"
    $VERBOSE && while IFS= read -r f; do
      local size_mb=$(( $(stat -c %s "$f" 2>/dev/null || echo 0) / 1048576 ))
      echo "  $(basename "$f"): ${size_mb}MB"
    done <<< "$large_files" || true
  fi

  # Check for rapidly growing logs (modified in last 5min and >10MB)
  local growing
  growing=$(find "$LOGS_DIR" -type f -mmin -5 -size +10M 2>/dev/null)
  if [ -n "$growing" ]; then
    local count
    count=$(echo "$growing" | wc -l)
    alert "WARN" "$count log file(s) >10MB and actively growing"
  fi
}

# === Check 5: Lock file health ===
check_lock_files() {
  $VERBOSE && echo "Checking lock files..."

  for lockfile in /tmp/agent-registry.lock /tmp/agent-watchdog-v2.lock; do
    if [ -f "$lockfile" ]; then
      local lock_age=$(( $(date +%s) - $(stat -c %Y "$lockfile" 2>/dev/null || echo 0) ))
      if [ "$lock_age" -gt 300 ]; then
        alert "WARN" "Lock file $lockfile is ${lock_age}s old — may be stale"
      fi
    fi
  done
}

# === Run all checks ===
$VERBOSE && echo "=== Agent System Health Check ==="
$VERBOSE && echo ""

check_registry_integrity
check_watchdog_status
check_orphaned_linear_tasks
check_log_sizes
check_lock_files

# === Output ===
if $JSON_MODE; then
  _alerts_json="[]"
  if [ ${#ALERTS[@]} -gt 0 ]; then
    _alerts_json=$(printf '%s\n' "${ALERTS[@]}" | python3 -c "
import json, sys
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
")
  fi
  python3 -c "
import json
print(json.dumps({
    'healthy': $ISSUES == 0,
    'issues': $ISSUES,
    'warnings': $WARNINGS,
    'alerts': json.loads('$_alerts_json'),
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}, indent=2))
"
else
  echo ""
  if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "HEALTHY: All checks passed"
  elif [ "$ISSUES" -eq 0 ]; then
    echo "OK: $WARNINGS warning(s), no critical issues"
    for a in "${ALERTS[@]}"; do echo "  $a"; done
  else
    echo "UNHEALTHY: $ISSUES issue(s), $WARNINGS warning(s)"
    for a in "${ALERTS[@]}"; do echo "  $a"; done
  fi
fi

exit $(( ISSUES > 0 ? 1 : 0 ))
