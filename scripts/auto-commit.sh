#!/usr/bin/env bash
# Auto-commit workspace changes to git
# Usage: auto-commit.sh ["message"]
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
cd "$WORKSPACE"

# Initialize git if needed
if [ ! -d .git ]; then
  git init
  git remote add origin git@github.com:fonsecabc/openclaw-workspace.git 2>/dev/null || true
fi

MSG="${1:-auto: workspace update $(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# Stage everything except secrets and temp files
git add -A \
  --ignore-errors \
  -- \
  ':!.env*' \
  ':!auth-profiles.json' \
  ':!*.key' \
  ':!*.pem' \
  ':!node_modules/' \
  ':!__pycache__/' \
  ':!*.log' \
  ':!.my.cnf' \
  2>/dev/null

# Check if there are changes
if git diff --cached --quiet 2>/dev/null; then
  echo "No changes to commit"
  exit 0
fi

git commit -m "$MSG"
echo "✅ Committed: $MSG"

# Push if remote exists
if git remote get-url origin > /dev/null 2>&1; then
  git push origin HEAD 2>/dev/null && echo "✅ Pushed to origin" || echo "⚠️ Push failed (remote may not exist yet)"
fi
