#!/bin/bash
# dispatch-guard.sh — Block direct eval/agent launches outside dispatcher
#
# This script is called as a pre-check before agent spawns.
# It scans a command string for forbidden patterns and blocks execution.
#
# Usage as pre-check:
#   bash scripts/dispatch-guard.sh "nohup python run_eval.py --config foo"
#   Exit 0 = safe, Exit 1 = blocked
#
# Usage as audit (scan log files):
#   bash scripts/dispatch-guard.sh --audit /path/to/agent-output.log
#
set -euo pipefail

# Forbidden patterns: direct eval/agent launches that bypass dispatcher
FORBIDDEN_PATTERNS=(
  "python.*run_eval"
  "python3.*run_eval"
  "nohup.*python"
  "nohup.*run_eval"
  "nohup.*eval"
  "sessions_spawn"
  "openclaw agent"       # only spawn-agent.sh should call this
)

# Allowed callers (these scripts ARE the dispatch system)
ALLOWED_CALLERS=(
  "spawn-agent.sh"
  "dispatcher.sh"
  "supervisor.sh"
  "run-guardian-eval.sh"
)

check_command() {
  local CMD="$1"

  # Check if caller is an allowed script
  for allowed in "${ALLOWED_CALLERS[@]}"; do
    if [[ "$CMD" == *"$allowed"* ]]; then
      return 0
    fi
  done

  # Check against forbidden patterns
  for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if echo "$CMD" | grep -qiE "$pattern"; then
      echo ""
      echo "============================================================"
      echo "  BLOCKED: Direct launch detected!"
      echo "  Command: $CMD"
      echo "  Pattern: $pattern"
      echo ""
      echo "  Use dispatcher.sh instead:"
      echo "    bash scripts/dispatcher.sh --title 'Run eval' --desc '$CMD' --role guardian-tuner"
      echo ""
      echo "  NEVER run evals or agents directly. This rule was corrected 4+ times."
      echo "============================================================"
      echo ""
      return 1
    fi
  done

  return 0
}

audit_log() {
  local LOG_FILE="$1"
  local VIOLATIONS=0

  if [ ! -f "$LOG_FILE" ]; then
    echo "File not found: $LOG_FILE"
    exit 1
  fi

  echo "Auditing $LOG_FILE for dispatch violations..."
  while IFS= read -r line; do
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
      if echo "$line" | grep -qiE "$pattern"; then
        # Skip if line is from an allowed caller
        local ALLOWED=false
        for caller in "${ALLOWED_CALLERS[@]}"; do
          if echo "$line" | grep -q "$caller"; then
            ALLOWED=true
            break
          fi
        done
        if ! $ALLOWED; then
          echo "VIOLATION: $line"
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      fi
    done
  done < "$LOG_FILE"

  echo "Total violations: $VIOLATIONS"
  [ "$VIOLATIONS" -gt 0 ] && exit 1 || exit 0
}

# Main
if [ "${1:-}" = "--audit" ]; then
  audit_log "${2:?Log file required}"
elif [ $# -gt 0 ]; then
  check_command "$*"
else
  echo "Usage: dispatch-guard.sh <command-to-check>"
  echo "       dispatch-guard.sh --audit <log-file>"
  exit 0
fi
