#!/bin/bash
# Dashboard watchdog — only runs when Caio is active
# Checks main session activity, starts/stops dashboard accordingly
PORT=8765
DASH_DIR="/root/.openclaw/workspace/dashboard"
IDLE_MIN=30  # kill dashboard after 30min idle

# Check if Caio sent a message in last IDLE_MIN minutes
LAST_ACTIVE=$(python3 -c "
import json, time
store = json.load(open('/root/.openclaw/agents/main/sessions/sessions.json'))
main = store.get('agent:main:main', {})
updated = main.get('updatedAt', 0)
age_min = (time.time() * 1000 - updated) / 60000
print(int(age_min))
" 2>/dev/null || echo "999")

if [ "$LAST_ACTIVE" -gt "$IDLE_MIN" ]; then
  # Idle — kill dashboard if running, close port
  if curl -sf "http://127.0.0.1:$PORT/" > /dev/null 2>&1; then
    fuser -k $PORT/tcp 2>/dev/null || true
    echo "[$(date -u +%H:%M)] Dashboard stopped (idle ${LAST_ACTIVE}min)"
  fi
else
  # Active — start dashboard if not running
  if ! curl -sf "http://127.0.0.1:$PORT/" > /dev/null 2>&1; then
    fuser -k $PORT/tcp 2>/dev/null || true
    sleep 1
    cd "$DASH_DIR" && nohup node -e "
      process.on('uncaughtException', e => console.error('ERR:', e.message));
      process.on('unhandledRejection', e => console.error('REJ:', e?.message || e));
      require('./server.js');
    " >> dashboard.log 2>&1 &
    sleep 5
    if curl -sf "http://127.0.0.1:$PORT/" > /dev/null 2>&1; then
      echo "[$(date -u +%H:%M)] Dashboard restarted ✅"
    else
      echo "[$(date -u +%H:%M)] Dashboard restart FAILED ❌"
    fi
  fi
fi
