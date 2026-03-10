#!/bin/bash
# agent-report.sh — Unified agent completion reporter
# Reads agent output/activity/stderr logs and posts a summary to BOTH Linear and Slack atomically.
# Called by watchdog on agent completion/failure. Replaces separate Linear + Slack logging.
#
# Usage: agent-report.sh <task-id> <status> [--timeout-min N]
#   status: done | failed | timeout | idle_killed
#
# Sources: reads from agent logs (output, stderr, activity), NOT from hooks.
# Targets: Linear (comment + status update) + Slack DM to Caio
set -euo pipefail

TASK_ID="${1:?Usage: agent-report.sh <task-id> <status>}"
STATUS="${2:?Status required: done|failed|timeout|idle_killed}"
TIMEOUT_MIN="${3:-}"

LOGS_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-logs"
WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"

source "$WORKSPACE/.env.secrets" 2>/dev/null || true
source "$WORKSPACE/.env.linear" 2>/dev/null || true

LINEAR_SCRIPT="$WORKSPACE/skills/linear/scripts/linear.sh"
DIAGNOSE="$WORKSPACE/scripts/diagnose-failure.sh"

REPLICANTS_CHANNEL="D0AK1B981QR"
TS=$(date -u +"%H:%M:%S")

# --- Read agent logs ---
OUTPUT=""
[ -f "$LOGS_DIR/${TASK_ID}-output.log" ] && OUTPUT=$(head -c 1000 "$LOGS_DIR/${TASK_ID}-output.log" 2>/dev/null || true)

STDERR=""
[ -f "$LOGS_DIR/${TASK_ID}-stderr.log" ] && STDERR=$(head -c 500 "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null || true)

# Get activity summary (tools used, event count)
ACTIVITY_SUMMARY=""
if [ -f "$LOGS_DIR/${TASK_ID}-activity.jsonl" ]; then
  ACTIVITY_SUMMARY=$(python3 -c "
import json, os
f = '$LOGS_DIR/${TASK_ID}-activity.jsonl'
if not os.path.exists(f): exit()
lines = open(f).readlines()
tools = set()
event_count = len(lines)
for l in lines[-50:]:
    try:
        e = json.loads(l)
        s = e.get('_summary','')
        if s.startswith('TOOL_START:'): tools.add(s.replace('TOOL_START: ',''))
        if s == 'DONE':
            u = e.get('usage',{})
            if u: print(f'Tokens: input={u.get(\"input\",0)} output={u.get(\"output\",0)}')
    except: pass
if tools: print(f'Tools: {\", \".join(sorted(tools))}')
print(f'Events: {event_count}')
" 2>/dev/null || true)
fi

# Get duration from agent log
DURATION=""
if [ -f "$LOGS_DIR/${TASK_ID}.log" ]; then
  SPAWN_LINE=$(grep '\[spawn\]' "$LOGS_DIR/${TASK_ID}.log" | tail -1)
  if [ -n "$SPAWN_LINE" ]; then
    SPAWN_TS=$(echo "$SPAWN_LINE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
    if [ -n "$SPAWN_TS" ]; then
      SPAWN_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$SPAWN_TS" "+%s" 2>/dev/null || date -d "$SPAWN_TS" "+%s" 2>/dev/null || echo "0")
      NOW_EPOCH=$(date "+%s")
      DURATION_MIN=$(( (NOW_EPOCH - SPAWN_EPOCH) / 60 ))
      DURATION="${DURATION_MIN}min"
    fi
  fi
fi

# Get diagnosis for failures
DIAGNOSIS=""
if [ "$STATUS" != "done" ] && [ -f "$DIAGNOSE" ]; then
  DIAGNOSIS=$(bash "$DIAGNOSE" "$TASK_ID" 2>/dev/null | python3 -c "
import json,sys
try:
  d = json.loads(sys.stdin.read())
  print(f'Error: {d[\"error_class\"]}')
  print(f'Fix: {d[\"fix\"]}')
except: pass
" 2>/dev/null || true)
fi

# --- Build the report ---
case "$STATUS" in
  done)
    LINEAR_STATUS="done"
    EMOJI=":white_check_mark:"
    HEADLINE="Agent completed"
    ;;
  failed)
    LINEAR_STATUS="blocked"
    EMOJI=":x:"
    HEADLINE="Agent failed"
    ;;
  timeout)
    LINEAR_STATUS="blocked"
    EMOJI=":hourglass:"
    HEADLINE="Agent timed out"
    ;;
  idle_killed)
    LINEAR_STATUS="blocked"
    EMOJI=":skull:"
    HEADLINE="Agent killed (idle)"
    ;;
  *)
    LINEAR_STATUS="blocked"
    EMOJI=":question:"
    HEADLINE="Agent status: $STATUS"
    ;;
esac

# Build Linear comment (detailed)
LINEAR_MSG="[$TS] $HEADLINE"
[ -n "$DURATION" ] && LINEAR_MSG+=" ($DURATION)"
[ -n "$ACTIVITY_SUMMARY" ] && LINEAR_MSG+=$'\n'"$ACTIVITY_SUMMARY"
if [ "$STATUS" = "done" ] && [ -n "$OUTPUT" ]; then
  LINEAR_MSG+=$'\n'"---"$'\n'"${OUTPUT:0:800}"
fi
if [ "$STATUS" != "done" ]; then
  [ -n "$DIAGNOSIS" ] && LINEAR_MSG+=$'\n'"$DIAGNOSIS"
  [ -n "$STDERR" ] && LINEAR_MSG+=$'\n'"Stderr: ${STDERR:0:300}"
fi

# Build Slack message (concise)
SLACK_MSG="$EMOJI *$TASK_ID* $HEADLINE"
[ -n "$DURATION" ] && SLACK_MSG+=" ($DURATION)"
if [ "$STATUS" = "done" ] && [ -n "$OUTPUT" ]; then
  # First line of output as summary
  FIRST_LINE=$(echo "$OUTPUT" | head -1 | head -c 200)
  SLACK_MSG+=$'\n'"$FIRST_LINE"
fi
if [ "$STATUS" != "done" ] && [ -n "$DIAGNOSIS" ]; then
  SLACK_MSG+=$'\n'"$DIAGNOSIS"
fi

# --- Post atomically to BOTH targets ---

# 1. Linear: comment + status update
if [ -n "$LINEAR_API_KEY" ] && [ -f "$LINEAR_SCRIPT" ]; then
  bash "$LINEAR_SCRIPT" comment "$TASK_ID" "$LINEAR_MSG" 2>/dev/null || true
  bash "$LINEAR_SCRIPT" status "$TASK_ID" "$LINEAR_STATUS" 2>/dev/null || true
fi

# 2. Slack: REMOVED — Anton's main thread (heartbeat) is the sole Slack reporter.
#    Supervisor detects completion → logs to Linear → Anton reads state + logs → reports to Caio.
#    Having agent-report.sh also post to Slack caused duplicate "done" messages.

# 3. Disk log
bash "$WORKSPACE/scripts/agent-logger.sh" "$TASK_ID" "report" "$HEADLINE ($DURATION)" 2>/dev/null || true

# 4. Guardian eval trigger REMOVED — was launching evals directly with & (invisible zombie).
#    Guardian evals must be dispatched through dispatcher.sh by Anton's main thread.

# 5. Clean up timeout warning file and checkpoint on success
if [ "$STATUS" = "done" ]; then
  rm -f "${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/timeout-warnings/${TASK_ID}.warn" 2>/dev/null || true
  rm -rf "${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/checkpoints/${TASK_ID}" 2>/dev/null || true
fi

echo "[report] $TASK_ID: $HEADLINE ($DURATION) → Linear=$LINEAR_STATUS + Slack"
