#!/bin/bash
# Deploy v2 agent management system
# Run from Anton's server after pulling the repo
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
cd "$WORKSPACE"

echo "=== Deploying Agent Management v2 ==="

# 1. Make all v2 scripts executable
chmod +x scripts/agent-registry.sh
chmod +x scripts/spawn-agent.sh
chmod +x scripts/agent-watchdog-v2.sh
chmod +x scripts/auto-queue-v2.sh
chmod +x scripts/linear-sync-v2.sh
chmod +x scripts/ralph-manager-v2.sh
chmod +x scripts/install-cron-v2.sh

echo "[1/6] Scripts made executable"

# 2. Initialize registry
mkdir -p /root/.openclaw/tasks/agent-logs
mkdir -p /root/.openclaw/tasks/spawn-tasks

if [ ! -f /root/.openclaw/tasks/agent-registry.json ]; then
  echo '{"agents":{},"maxConcurrent":3}' > /root/.openclaw/tasks/agent-registry.json
  echo "[2/6] Registry initialized"
else
  echo "[2/6] Registry already exists"
fi

# 3. Kill any existing zombies before switching
echo "[3/6] Cleaning up existing processes..."
BEFORE=$(pgrep -x claude 2>/dev/null | wc -l || echo 0)
# Kill all existing claude-agent-acp bridges (they're the problem)
pkill -f "claude-agent-acp" 2>/dev/null || true
sleep 1
# Kill orphan claude processes (old system)
for pid in $(pgrep -x claude 2>/dev/null || true); do
  age_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
  if [ "$age_s" -gt 300 ]; then
    kill -9 "$pid" 2>/dev/null || true
  fi
done
AFTER=$(pgrep -x claude 2>/dev/null | wc -l || echo 0)
echo "  Processes: $BEFORE -> $AFTER"

# 4. Clean session store
if [ -f "/root/.openclaw/agents/claude/sessions/sessions.json" ]; then
  echo '{}' > /root/.openclaw/agents/claude/sessions/sessions.json
  echo "[4/6] Session store cleaned"
else
  echo "[4/6] No session store to clean"
fi

# 5. Install new cron
bash scripts/install-cron-v2.sh
echo "[5/6] Cron installed"

# 6. Rename old scripts (keep as backup, don't delete)
for old in agent-monitor.sh completion-checker.sh kill-zombies.sh auto-queue.sh linear-sync.sh ralph-manager.sh; do
  if [ -f "scripts/$old" ] && [ ! -f "scripts/${old}.v1-backup" ]; then
    cp "scripts/$old" "scripts/${old}.v1-backup"
    echo "  Backed up: $old -> ${old}.v1-backup"
  fi
done

echo "[6/6] Old scripts backed up"

echo ""
echo "=== Deploy Complete ==="
echo ""
echo "v2 System:"
echo "  Registry:    /root/.openclaw/tasks/agent-registry.json"
echo "  Spawn:       scripts/spawn-agent.sh --task CAI-XX --label desc [--timeout 25] task-text"
echo "  Watchdog:    scripts/agent-watchdog-v2.sh (cron every 60s)"
echo "  Auto-queue:  scripts/auto-queue-v2.sh (cron every 5min)"
echo "  Linear sync: scripts/linear-sync-v2.sh (cron every 15min)"
echo "  Ralph:       scripts/ralph-manager-v2.sh start <proj> [task]"
echo "  Registry:    scripts/agent-registry.sh list|count|slots|has"
echo ""
echo "Quick test:"
echo "  bash scripts/agent-registry.sh list"
echo "  bash scripts/agent-watchdog-v2.sh"
