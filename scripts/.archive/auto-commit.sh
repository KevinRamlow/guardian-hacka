#!/usr/bin/env bash
# Auto-commit workspace changes to git
# Usage: auto-commit.sh ["message"]
set -euo pipefail

WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
cd "$WORKSPACE"

# Initialize git if needed
if [ ! -d .git ]; then
  git init
  git remote add origin git@github.com:fonsecabc/openclaw-workspace.git 2>/dev/null || true
fi

MSG="${1:-auto: workspace update $(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# Stage everything except secrets, temp files, and stats
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
  ':!scripts/agent-registry.json' \
  ':!tasks/' \
  ':!.claude_sessions/' \
  2>/dev/null

# Check if there are changes
if git diff --cached --quiet 2>/dev/null; then
  echo "No changes to commit"
  exit 0
fi

# Check if changes are ONLY in stats/tracking files (filtered out above)
# If all staged changes are meaningful, proceed
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED_FILES" -eq 0 ]; then
  echo "No meaningful changes (only stats/logs)"
  exit 0
fi

git commit -m "$MSG"
echo "✅ Committed: $MSG"

# Push if remote exists
if git remote get-url origin > /dev/null 2>&1; then
  git push origin HEAD 2>/dev/null && echo "✅ Pushed to origin" || echo "⚠️ Push failed (remote may not exist yet)"
fi
