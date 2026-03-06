#!/bin/bash
# sync-billy.sh — Push from Anton, pull on Billy
# Usage: sync-billy.sh [commit-msg]

set -euo pipefail
REPO="/root/.openclaw/workspace"
BILLY="root@89.167.64.183"

cd "$REPO"

# 1. Auto-push from Anton
bash scripts/auto-push.sh

# 2. Pull on Billy
ssh "$BILLY" "cd /root/.openclaw/workspace && git pull origin main --ff-only 2>&1" || {
    echo "[sync-billy] Pull failed, trying reset..."
    ssh "$BILLY" "cd /root/.openclaw/workspace && git fetch origin && git reset --hard origin/main 2>&1"
}

echo "[sync-billy] Billy synced ✓"
