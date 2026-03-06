#!/usr/bin/env bash
# Sync Anton workspace improvements to Billy VM (89.167.64.183)
# Usage: sync-to-billy.sh [--commit "message"] [--skills-only] [--all]
set -euo pipefail

BILLY_HOST="root@89.167.64.183"
WORKSPACE="/root/.openclaw/workspace"
BILLY_WORKSPACE="$BILLY_HOST:/root/.openclaw/workspace"

COMMIT_MSG=""
SKILLS_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --commit) COMMIT_MSG="$2"; shift 2 ;;
    --skills-only) SKILLS_ONLY=true; shift ;;
    --all) SKILLS_ONLY=false; shift ;;
    *) shift ;;
  esac
done

echo "🔄 Syncing Anton → Billy..."

if $SKILLS_ONLY; then
  # Skills only
  rsync -av --delete \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='.git' \
    "$WORKSPACE/skills/" "$BILLY_WORKSPACE/skills/"
  echo "✅ Skills synced"
else
  # Full architecture sync
  SYNC_PATHS=(
    "skills/"
    "SOUL.md"
    "AGENTS.md"
    "TOOLS.md"
    "HEARTBEAT.md"
    "scripts/"
    "docs/"
  )
  
  for path in "${SYNC_PATHS[@]}"; do
    if [ -e "$WORKSPACE/$path" ]; then
      rsync -av --delete \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.git' \
        --exclude='memory/' \
        --exclude='*.log' \
        "$WORKSPACE/$path" "$BILLY_WORKSPACE/$path"
      echo "  ✅ $path"
    fi
  done
  echo "✅ Full sync complete"
fi

# Restart Billy gateway to pick up changes
ssh "$BILLY_HOST" 'PID=$(pgrep -f openclaw-gateway 2>/dev/null); if [ -n "$PID" ]; then kill $PID; sleep 2; fi; cd /root/.openclaw && nohup openclaw gateway run > /tmp/billy.log 2>&1 &'
sleep 3
ssh "$BILLY_HOST" 'pgrep -f openclaw-gateway > /dev/null && echo "✅ Billy gateway restarted" || echo "❌ Billy gateway failed to start"'

echo "🔄 Sync complete!"
