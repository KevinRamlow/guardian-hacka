#!/bin/bash
# Queue Control — Pause/resume the auto-queue
# Usage: queue-control.sh pause    — stop auto-queue from spawning
#        queue-control.sh resume   — re-enable auto-queue
#        queue-control.sh status   — show current state
set -euo pipefail

CONFIG="/Users/fonsecabc/.openclaw/workspace/config/auto-queue.json"

case "${1:-status}" in
  pause|stop|disable)
    python3 -c "import json; d=json.load(open('$CONFIG')); d['enabled']=False; json.dump(d,open('$CONFIG','w'),indent=2)"
    echo "⏸️  Auto-queue PAUSED. No new agents will be spawned."
    ;;
  resume|start|enable)
    python3 -c "import json; d=json.load(open('$CONFIG')); d['enabled']=True; json.dump(d,open('$CONFIG','w'),indent=2)"
    echo "▶️  Auto-queue RESUMED. Agents will spawn from Todo queue."
    ;;
  status)
    ENABLED=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('enabled', True))" 2>/dev/null)
    if [ "$ENABLED" = "True" ]; then
      echo "▶️  Auto-queue is RUNNING"
    else
      echo "⏸️  Auto-queue is PAUSED"
    fi
    ;;
  *)
    echo "Usage: queue-control.sh [pause|resume|status]"
    exit 1
    ;;
esac
