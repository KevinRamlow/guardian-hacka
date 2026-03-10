#!/bin/bash
# guardrails.sh — Runtime invariant checker for Anton's script ecosystem
#
# Called by supervisor.sh and dispatcher.sh before critical operations.
# Returns exit 0 if all invariants hold, exit 1 with violations printed to stderr.
#
# Usage: bash scripts/guardrails.sh [--check all|state|spawn|orphans]
#
# Checks:
#   state   — state.json integrity (valid JSON, no stale agent_running without PID)
#   spawn   — no direct claude/sessions_spawn/nohup python processes running outside state.json
#   orphans — no agent-registry.json reads in active scripts (deprecated)
#   all     — all of the above (default)

set -uo pipefail

STATE_FILE="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/state.json"
WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
CHECK="${1:-all}"
[ "$CHECK" = "--check" ] && CHECK="${2:-all}"

VIOLATION_FILE=$(mktemp)
trap "rm -f $VIOLATION_FILE" EXIT

fail() {
  echo "VIOLATION: $1" >&2
  echo "1" >> "$VIOLATION_FILE"
}

# ── STATE INTEGRITY ──────────────────────────────────────────────────────────
check_state() {
  if ! python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null; then
    fail "state.json is not valid JSON"
    return
  fi

  # Check for bad states via python (single pass, no subshell)
  ISSUES=$(python3 -c "
import json
d = json.load(open('$STATE_FILE'))
issues = []
for tid, t in d.get('tasks', {}).items():
    s = t.get('status')
    if s == 'agent_running' and not t.get('agentPid'):
        issues.append(f'{tid} is agent_running but has no agentPid')
    if s == 'eval_running' and not t.get('processPid'):
        issues.append(f'{tid} is eval_running but has no processPid')
    if s in ('done', 'failed') and not t.get('reportedAt'):
        issues.append(f'{tid} is {s} but has no reportedAt (done-bug indicator)')
for i in issues:
    print(i)
" 2>/dev/null)

  if [ -n "$ISSUES" ]; then
    while IFS= read -r issue; do
      fail "$issue"
    done <<< "$ISSUES"
  fi
}

# ── SPAWN DISCIPLINE ────────────────────────────────────────────────────────
check_spawn() {
  REGISTERED_PIDS=$(python3 -c "
import json
d = json.load(open('$STATE_FILE'))
for t in d.get('tasks', {}).values():
    for k in ('agentPid', 'processPid'):
        p = t.get(k)
        if p: print(p)
" 2>/dev/null)

  # Check for claude processes not in state.json and not children of openclaw-gateway
  for pid in $(pgrep -x claude 2>/dev/null || true); do
    if ! echo "$REGISTERED_PIDS" | grep -q "^${pid}$"; then
      PARENT_PID=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      PARENT_CMD=$(ps -o comm= -p "$PARENT_PID" 2>/dev/null || echo "unknown")
      # Skip if parent is openclaw (managed by gateway) or a shell (interactive session)
      if [[ "$PARENT_CMD" != *openclaw* ]] && [[ "$PARENT_CMD" != *zsh* ]] && [[ "$PARENT_CMD" != *bash* ]] && [[ "$PARENT_CMD" != *sh* ]]; then
        # macOS: etimes not available, use etime (elapsed time as [[dd-]hh:]mm:ss)
        ETIME=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
        # Convert etime to seconds (handles mm:ss, hh:mm:ss, dd-hh:mm:ss)
        AGE=$(python3 -c "
import sys
t = '$ETIME'
if not t: sys.exit(0)
parts = t.replace('-',':').split(':')
parts = [int(p) for p in parts]
if len(parts) == 2: s = parts[0]*60 + parts[1]
elif len(parts) == 3: s = parts[0]*3600 + parts[1]*60 + parts[2]
elif len(parts) == 4: s = parts[0]*86400 + parts[1]*3600 + parts[2]*60 + parts[3]
else: s = 0
print(s)
" 2>/dev/null || echo 0)
        if [ "${AGE:-0}" -gt 120 ]; then
          fail "Untracked claude process PID=$pid (parent=$PARENT_CMD, age=${AGE}s)"
        fi
      fi
    fi
  done

  # No nohup python run_eval processes outside state.json
  for pid in $(pgrep -f "run_eval.py" 2>/dev/null || true); do
    if ! echo "$REGISTERED_PIDS" | grep -q "^${pid}$"; then
      fail "Untracked eval process PID=$pid — run_eval.py outside state.json"
    fi
  done

  # Deprecated agent-registry.json should not be recently written
  if [ -f "${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-registry.json" ]; then
    MOD_AGE=$(( $(date +%s) - $(stat -f%m "${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-registry.json" 2>/dev/null || echo 0) ))
    if [ "$MOD_AGE" -lt 300 ]; then
      fail "agent-registry.json modified ${MOD_AGE}s ago — something still writes to it"
    fi
  fi
}

# ── ORPHAN REFERENCES ────────────────────────────────────────────────────────
check_orphans() {
  # Active scripts referencing deprecated agent-registry.json
  for f in $(grep -rl "agent-registry.json" "$WORKSPACE/scripts/" 2>/dev/null | grep -v '.archive/' || true); do
    # Skip guardrails.sh itself (it checks for the deprecated file, not uses it)
    [[ "$f" == *guardrails.sh ]] && continue
    # Skip task-manager.sh (has backward-compat register shim)
    [[ "$f" == *task-manager.sh ]] && continue
    fail "$(basename "$f") references deprecated agent-registry.json"
  done

  # Active files referencing sessions_spawn (forbidden except in SOUL.md warnings and dispatch-guard)
  for f in $(grep -rl "sessions_spawn" "$WORKSPACE/scripts/" "$WORKSPACE/skills/" 2>/dev/null | grep -v '.archive/' || true); do
    [[ "$f" == *SOUL.md ]] && continue
    [[ "$f" == *dispatch-guard.sh ]] && continue
    [[ "$f" == *guardrails.sh ]] && continue
    [[ "$f" == *spawn-agent.sh ]] && continue  # has it in dispatch-guard call context
    [[ "$f" == *memory/* ]] && continue
    [[ "$f" == *behavioral-anti-patterns* ]] && continue
    fail "$(basename "$f") references sessions_spawn (forbidden)"
  done
}

# ── RUN CHECKS ───────────────────────────────────────────────────────────────
case "$CHECK" in
  state)   check_state ;;
  spawn)   check_spawn ;;
  orphans) check_orphans ;;
  all)     check_state; check_spawn; check_orphans ;;
  *)       echo "Usage: guardrails.sh [--check all|state|spawn|orphans]" >&2; exit 1 ;;
esac

VIOLATION_COUNT=$(wc -l < "$VIOLATION_FILE" | tr -d ' ')

if [ "$VIOLATION_COUNT" -gt 0 ]; then
  echo "GUARDRAILS: $VIOLATION_COUNT violation(s) found" >&2
  exit 1
else
  echo "GUARDRAILS: OK"
  exit 0
fi
