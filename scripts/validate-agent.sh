#!/bin/bash
# Validate agent completion by running success criteria tests
# Usage: validate-agent.sh <task-file-or-id>
set -euo pipefail

TASK_INPUT="$1"
TASK_FILE=""

# If CAI-XXX, find task file
if [[ "$TASK_INPUT" =~ ^CAI-[0-9]+$ ]]; then
  TASK_FILE="/root/.openclaw/tasks/agent-logs/${TASK_INPUT}-task.md"
  if [ ! -f "$TASK_FILE" ]; then
    echo "❌ Task file not found: $TASK_FILE"
    exit 1
  fi
else
  TASK_FILE="$TASK_INPUT"
fi

if [ ! -f "$TASK_FILE" ]; then
  echo "❌ File not found: $TASK_FILE"
  exit 1
fi

echo "Validating: $TASK_FILE"
echo ""

# Extract validation commands (all ```bash blocks)
VALIDATION_CMDS=$(awk '
  /^```bash$/ { in_block=1; next }
  /^```$/ { in_block=0; next }
  in_block { print }
' "$TASK_FILE")

if [ -z "$VALIDATION_CMDS" ]; then
  echo "⚠️ No validation commands found in task"
  exit 1
fi

# Run each command
TOTAL=0
PASSED=0
FAILED=0

while IFS= read -r cmd; do
  # Skip empty lines and comments
  [[ -z "$cmd" || "$cmd" =~ ^# ]] && continue
  
  TOTAL=$((TOTAL + 1))
  echo "[$TOTAL] Running: ${cmd:0:60}..."
  
  if eval "$cmd" > /tmp/validate-output.log 2>&1; then
    PASSED=$((PASSED + 1))
    echo "  ✅ PASS"
  else
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL"
    echo "  Output: $(cat /tmp/validate-output.log | head -3)"
  fi
done <<< "$VALIDATION_CMDS"

echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
  echo "✅ VALIDATION PASSED: $PASSED/$TOTAL checks"
  exit 0
else
  echo "❌ VALIDATION FAILED: $PASSED/$TOTAL checks passed, $FAILED failed"
  exit 1
fi
