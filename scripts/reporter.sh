#!/bin/bash
# reporter.sh — Unified reporting from state.json to Linear + Slack + dashboard
# Replaces agent-report.sh + agent-peek.sh + notify-slack.sh
#
# Usage:
#   reporter.sh report <task-id> <status>         Post completion report to Linear + Slack
#   reporter.sh peek [task-id] [follow]            Monitor tasks (overview or single)
#   reporter.sh notify "message"                   Post to #replicants
#   reporter.sh summary                            Daily summary of all tasks
#
set -euo pipefail

TASK_MGR="/Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
DIAGNOSE="$WORKSPACE/scripts/diagnose-failure.sh"
LINEAR_SCRIPT="$WORKSPACE/skills/linear/scripts/linear.sh"
REPLICANTS_CHANNEL="C0AJTTFLN4X"

source "$WORKSPACE/.env.secrets" 2>/dev/null || true
source "$WORKSPACE/.env.linear" 2>/dev/null || true

CMD="${1:-help}"
shift || true

case "$CMD" in

  report)
    TASK_ID="${1:?task-id required}"
    STATUS="${2:?status required: done|failed|timeout|idle_killed}"

    TS=$(date -u +"%H:%M:%S")

    # Read agent logs
    OUTPUT=""
    [ -f "$LOGS_DIR/${TASK_ID}-output.log" ] && OUTPUT=$(head -c 1000 "$LOGS_DIR/${TASK_ID}-output.log" 2>/dev/null || true)
    STDERR=""
    [ -f "$LOGS_DIR/${TASK_ID}-stderr.log" ] && STDERR=$(head -c 500 "$LOGS_DIR/${TASK_ID}-stderr.log" 2>/dev/null || true)

    # Activity summary
    ACTIVITY_SUMMARY=""
    if [ -f "$LOGS_DIR/${TASK_ID}-activity.jsonl" ]; then
      ACTIVITY_SUMMARY=$(python3 -c "
import json, os
f = '$LOGS_DIR/${TASK_ID}-activity.jsonl'
if not os.path.exists(f): exit()
lines = open(f).readlines()
tools = set()
for l in lines[-50:]:
    try:
        e = json.loads(l)
        s = e.get('_summary','')
        if s.startswith('TOOL_START:'): tools.add(s.replace('TOOL_START: ',''))
    except: pass
if tools: print(f'Tools: {\", \".join(sorted(tools))}')
print(f'Events: {len(lines)}')
" 2>/dev/null || true)
    fi

    # Duration
    DURATION=""
    TASK_DATA=$(bash "$TASK_MGR" get "$TASK_ID" 2>/dev/null || echo "{}")
    STARTED_EPOCH=$(echo "$TASK_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('startedEpoch',0))" 2>/dev/null || echo "0")
    if [ "$STARTED_EPOCH" -gt 0 ]; then
      NOW_EPOCH=$(date +%s)
      DURATION_MIN=$(( (NOW_EPOCH - STARTED_EPOCH) / 60 ))
      DURATION="${DURATION_MIN}min"
    fi

    # History context
    HISTORY_COUNT=$(echo "$TASK_DATA" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('history',[])))" 2>/dev/null || echo "0")

    # Diagnosis for failures
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

    # Build report
    case "$STATUS" in
      done)         LINEAR_STATUS="done"; EMOJI=":white_check_mark:"; HEADLINE="Agent completed" ;;
      failed)       LINEAR_STATUS="blocked"; EMOJI=":x:"; HEADLINE="Agent failed" ;;
      timeout)      LINEAR_STATUS="blocked"; EMOJI=":hourglass:"; HEADLINE="Agent timed out" ;;
      idle_killed)  LINEAR_STATUS="blocked"; EMOJI=":skull:"; HEADLINE="Agent killed (idle)" ;;
      *)            LINEAR_STATUS="blocked"; EMOJI=":question:"; HEADLINE="Agent: $STATUS" ;;
    esac

    # Linear comment
    LINEAR_MSG="[$TS] $HEADLINE"
    [ -n "$DURATION" ] && LINEAR_MSG+=" ($DURATION)"
    [ "$HISTORY_COUNT" -gt 0 ] && LINEAR_MSG+=" [cycle $HISTORY_COUNT]"
    [ -n "$ACTIVITY_SUMMARY" ] && LINEAR_MSG+=$'\n'"$ACTIVITY_SUMMARY"
    if [ "$STATUS" = "done" ] && [ -n "$OUTPUT" ]; then
      LINEAR_MSG+=$'\n'"---"$'\n'"${OUTPUT:0:800}"
    fi
    if [ "$STATUS" != "done" ]; then
      [ -n "$DIAGNOSIS" ] && LINEAR_MSG+=$'\n'"$DIAGNOSIS"
      [ -n "$STDERR" ] && LINEAR_MSG+=$'\n'"Stderr: ${STDERR:0:300}"
    fi

    # Slack message
    SLACK_MSG="$EMOJI *$TASK_ID* $HEADLINE"
    [ -n "$DURATION" ] && SLACK_MSG+=" ($DURATION)"
    [ "$HISTORY_COUNT" -gt 0 ] && SLACK_MSG+=" [cycle $HISTORY_COUNT]"
    if [ "$STATUS" = "done" ] && [ -n "$OUTPUT" ]; then
      FIRST_LINE=$(echo "$OUTPUT" | head -1 | head -c 200)
      SLACK_MSG+=$'\n'"$FIRST_LINE"
    fi
    if [ "$STATUS" != "done" ] && [ -n "$DIAGNOSIS" ]; then
      SLACK_MSG+=$'\n'"$DIAGNOSIS"
    fi

    # Post to Linear
    if [ -n "$LINEAR_API_KEY" ] && [ -f "$LINEAR_SCRIPT" ]; then
      bash "$LINEAR_SCRIPT" comment "$TASK_ID" "$LINEAR_MSG" 2>/dev/null || true
      bash "$LINEAR_SCRIPT" status "$TASK_ID" "$LINEAR_STATUS" 2>/dev/null || true
    fi

    # Post to Slack
    if [ -n "$SLACK_BOT_TOKEN" ]; then
      SAFE_MSG=$(echo "$SLACK_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || echo "$SLACK_MSG")
      curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"channel\":\"$REPLICANTS_CHANNEL\",\"text\":\"$SAFE_MSG\",\"mrkdwn\":true}" \
        > /dev/null 2>&1 || true
    fi

    # Disk log
    bash "$WORKSPACE/scripts/agent-logger.sh" "$TASK_ID" "report" "$HEADLINE ($DURATION)" 2>/dev/null || true

    # Cleanup on success
    if [ "$STATUS" = "done" ]; then
      rm -f "/Users/fonsecabc/.openclaw/tasks/timeout-warnings/${TASK_ID}.warn" 2>/dev/null || true
    fi

    echo "[report] $TASK_ID: $HEADLINE ($DURATION) → Linear=$LINEAR_STATUS + Slack"
    ;;

  peek)
    TASK_ID="${1:-}"
    MODE="${2:-}"

    if [ -z "$TASK_ID" ]; then
      # Overview of all tasks
      bash "$TASK_MGR" list
    elif [ "$MODE" = "follow" ]; then
      # Live tail activity
      ACTIVITY="$LOGS_DIR/${TASK_ID}-activity.jsonl"
      if [ ! -f "$ACTIVITY" ]; then
        echo "No activity file for $TASK_ID"
        exit 1
      fi
      echo "Following $TASK_ID activity (Ctrl+C to stop)..."
      tail -f "$ACTIVITY" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        s = e.get('_summary', '')
        ts = e.get('_ts', '')
        if s: print(f'[{ts}] {s}')
    except: pass
"
    else
      # Show single task detail
      echo "=== $TASK_ID ==="
      bash "$TASK_MGR" get "$TASK_ID"
      echo ""
      echo "--- Last Activity ---"
      [ -f "$LOGS_DIR/${TASK_ID}-activity.jsonl" ] && tail -5 "$LOGS_DIR/${TASK_ID}-activity.jsonl" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        s = e.get('_summary', '')
        ts = e.get('_ts', '')
        if s: print(f'[{ts}] {s}')
    except: pass
" || echo "(no activity)"
      echo ""
      echo "--- Output (last 10 lines) ---"
      [ -f "$LOGS_DIR/${TASK_ID}-output.log" ] && tail -10 "$LOGS_DIR/${TASK_ID}-output.log" || echo "(no output)"
    fi
    ;;

  notify)
    MESSAGE="${1:?message required}"
    if [ -n "$SLACK_BOT_TOKEN" ]; then
      SAFE_MSG=$(echo "$MESSAGE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || echo "$MESSAGE")
      curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"channel\":\"$REPLICANTS_CHANNEL\",\"text\":\"$SAFE_MSG\",\"mrkdwn\":true}" \
        > /dev/null 2>&1 || true
      echo "Notified #replicants"
    else
      echo "No SLACK_BOT_TOKEN" >&2
    fi
    ;;

  summary)
    bash "$TASK_MGR" list
    echo ""
    echo "--- Health Metrics ---"
    [ -f "$WORKSPACE/metrics/agent-health.json" ] && python3 -c "
import json
m = json.load(open('$WORKSPACE/metrics/agent-health.json'))
s = m.get('summary', {})
print(f'Success rate: {s.get(\"success_rate_pct\", 0)}%')
print(f'Total agents (7d): {s.get(\"total_agents\", 0)}')
print(f'Completed: {s.get(\"completed\", 0)} | Failed: {s.get(\"failed\", 0)} | Timeout: {s.get(\"timeouts\", 0)}')
print(f'Avg duration: {s.get(\"avg_duration_min\", 0)}min')
print(f'Monthly cost: \${s.get(\"total_cost_usd\", 0)}')
" || echo "(no metrics file)"
    ;;

  help|*)
    cat <<'EOF'
reporter.sh — Unified reporting

Commands:
  report <task-id> <status>    Post completion report to Linear + Slack
  peek [task-id] [follow]      Monitor tasks (overview, detail, or live)
  notify "message"             Post to #replicants
  summary                      Full system summary
EOF
    ;;
esac
