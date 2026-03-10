#!/bin/bash
# Auto-restart dashboard on crash
cd /Users/fonsecabc/.openclaw/workspace/dashboard
while true; do
  echo "[$(date)] Starting dashboard..."
  node server.js 2>&1
  EXIT_CODE=$?
  echo "[$(date)] Dashboard exited with code $EXIT_CODE, restarting in 3s..."
  sleep 3
done
