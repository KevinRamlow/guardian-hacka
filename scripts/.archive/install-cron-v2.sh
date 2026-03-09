#!/bin/bash
# Install v2 cron jobs — replaces old fragmented monitoring with unified system
# Run this ONCE after deploying v2 scripts
set -euo pipefail

echo "=== Installing v2 cron jobs ==="

# Backup current crontab
crontab -l > /tmp/crontab-backup-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null || true

# Install new crontab
cat <<'CRON' | crontab -
# === Agent Management v2 ===
# Watchdog: check registered agents, kill zombies, detect completions (every 60s)
* * * * * /bin/bash /Users/fonsecabc/.openclaw/workspace/scripts/agent-watchdog-v2.sh >> /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log 2>&1

# Auto-queue: fetch Linear Todo tasks and spawn agents (every 5 min)
*/5 * * * * /bin/bash /Users/fonsecabc/.openclaw/workspace/scripts/auto-queue-v2.sh >> /Users/fonsecabc/.openclaw/tasks/agent-logs/auto-queue.log 2>&1

# Linear sync: match In Progress tasks to registry, move orphans to Todo (every 15 min)
*/15 * * * * /bin/bash /Users/fonsecabc/.openclaw/workspace/scripts/linear-sync-v2.sh >> /Users/fonsecabc/.openclaw/tasks/agent-logs/linear-sync.log 2>&1

# Health check: validate registry, watchdog, logs (every 5 min)
*/5 * * * * /bin/bash /Users/fonsecabc/.openclaw/workspace/scripts/health-check.sh >> /Users/fonsecabc/.openclaw/tasks/agent-logs/health-check.log 2>&1

# === Workspace Management (unchanged) ===
# Auto-push workspace changes to git (every 15 min)
*/15 * * * * cd /Users/fonsecabc/.openclaw/workspace && bash scripts/auto-push.sh >> /tmp/auto-push.log 2>&1
CRON

echo "New crontab installed:"
crontab -l
echo ""
echo "Old jobs removed:"
echo "  - linear-sync.js (replaced by linear-sync-v2.sh)"
echo "  - pipeline-manager.sh (removed — redundant with auto-queue-v2)"
echo ""
echo "New jobs:"
echo "  - agent-watchdog-v2.sh (every 60s) — replaces agent-monitor + completion-checker + kill-zombies"
echo "  - auto-queue-v2.sh (every 5min) — replaces auto-queue + pipeline spawner"
echo "  - linear-sync-v2.sh (every 15min) — replaces linear-sync.sh"
echo "  - auto-push.sh (every 15min) — unchanged"
