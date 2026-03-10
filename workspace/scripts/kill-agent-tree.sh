#!/bin/bash
# Kill agent and ALL its child processes
# Usage: kill-agent-tree.sh <PID>
set -euo pipefail

PID=$1

if [ -z "$PID" ]; then
  echo "Usage: kill-agent-tree.sh <PID>"
  exit 1
fi

# Verify process exists
if ! kill -0 "$PID" 2>/dev/null; then
  echo "Process $PID not found"
  exit 1
fi

echo "Killing PID $PID and all children..."

# Method 1: Kill all descendants recursively
pkill -9 -P "$PID" 2>/dev/null || true

# Method 2: Kill the process group (if leader)
PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
if [ -n "$PGID" ] && [ "$PGID" != "0" ]; then
  kill -9 -- -"$PGID" 2>/dev/null || true
fi

# Method 3: Kill the main process
kill -9 "$PID" 2>/dev/null || true

sleep 1

# Verify all dead
SURVIVORS=$(pgrep -P "$PID" 2>/dev/null || true)
if [ -n "$SURVIVORS" ]; then
  echo "WARNING: Some child processes survived: $SURVIVORS"
  echo "$SURVIVORS" | xargs kill -9 2>/dev/null || true
else
  echo "✓ PID $PID and all children killed"
fi
