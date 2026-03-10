#!/bin/bash
# reporter.sh — Task monitoring + notifications
#
# Usage:
#   reporter.sh peek [task-id] [follow]   Monitor tasks (overview or single)
#   reporter.sh notify "message"          Post to Caio's DM
#   reporter.sh summary                   Full system summary
#
# NOTE: Completion reporting is handled by supervisor.sh (Linear via linear-log.sh,
#       Slack via heartbeat). No separate report command needed.
#
set -euo pipefail

TASK_MGR="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/task-manager.sh"
LOGS_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-logs"
WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
REPLICANTS_CHANNEL="D0AK1B981QR"

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"; source "$OC_HOME/.env" 2>/dev/null || true

CMD="${1:-help}"
shift || true

case "$CMD" in

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
reporter.sh — Task monitoring + notifications

Commands:
  peek [task-id] [follow]      Monitor tasks (overview, detail, or live)
  notify "message"             Post to Caio's DM
  summary                      Full system summary
EOF
    ;;
esac
