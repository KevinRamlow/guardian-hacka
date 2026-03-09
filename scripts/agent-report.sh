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

LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
WORKSPACE="/Users/fonsecabc/.openclaw/workspace"

source "$WORKSPACE/.env.secrets" 2>/dev/null || true
source "$WORKSPACE/.env.linear" 2>/dev/null || true

LINEAR_SCRIPT="$WORKSPACE/skills/linear/scripts/linear.sh"
DIAGNOSE="$WORKSPACE/scripts/diagnose-failure.sh"

REPLICANTS_CHANNEL="C0AJTTFLN4X"
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
SLACK_MSG="<@U0AJU1XN3AT> $EMOJI *$TASK_ID* $HEADLINE"
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

# 2. Slack: DM to Caio
if [ -n "$SLACK_BOT_TOKEN" ]; then
  SAFE_MSG=$(echo "$SLACK_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || echo "$SLACK_MSG")
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"$REPLICANTS_CHANNEL\",\"text\":\"$SAFE_MSG\",\"mrkdwn\":true}" \
    > /dev/null 2>&1 || true
fi

# 3. Disk log
bash "$WORKSPACE/scripts/agent-logger.sh" "$TASK_ID" "report" "$HEADLINE ($DURATION)" 2>/dev/null || true

# 4. Trigger Guardian eval if task completed successfully and is guardian-related
if [ "$STATUS" = "done" ]; then
  # Check task label from registry
  LABEL=$(jq -r "select(.task_id == \"$TASK_ID\") | .label // \"\"" \
    "$WORKSPACE/metrics/agent-registry.json" 2>/dev/null || echo "")
  
  # Trigger eval for guardian tasks (but not for eval tasks themselves to avoid recursion)
  if [[ "$LABEL" =~ guardian ]] && [[ ! "$LABEL" =~ guardian_eval ]]; then
    echo "[report] Guardian task completed → triggering validation eval"
    bash "$WORKSPACE/scripts/run-guardian-eval.sh" > /tmp/eval-trigger-$TASK_ID.log 2>&1 &
  fi
fi

# 5. Clean up timeout warning file and checkpoint on success
if [ "$STATUS" = "done" ]; then
  rm -f "/Users/fonsecabc/.openclaw/tasks/timeout-warnings/${TASK_ID}.warn" 2>/dev/null || true
  rm -rf "/Users/fonsecabc/.openclaw/tasks/checkpoints/${TASK_ID}" 2>/dev/null || true
fi

echo "[report] $TASK_ID: $HEADLINE ($DURATION) → Linear=$LINEAR_STATUS + Slack"
