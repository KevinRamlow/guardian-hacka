#!/bin/bash
# auto-push.sh — Auto-commit and push workspace changes
# Run manually, via cron, or as a post-task hook

set -euo pipefail
REPO="/Users/fonsecabc/.openclaw/workspace"
cd "$REPO"

# Skip if no changes
if git diff --quiet HEAD 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "[auto-push] No changes to push"
    exit 0
fi

# Stage all tracked + new files
git add -A

# Generate commit message from changed files
CHANGED=$(git diff --cached --name-only | head -10 | tr '\n' ', ' | sed 's/,$//')
COUNT=$(git diff --cached --name-only | wc -l)
if [ "$COUNT" -gt 10 ]; then
    MSG="sync: ${COUNT} files updated (${CHANGED}...)"
else
    MSG="sync: ${CHANGED}"
fi

git commit -m "$MSG" --no-verify 2>/dev/null || { echo "[auto-push] Nothing to commit"; exit 0; }
git push origin main 2>&1 || { echo "[auto-push] Push failed"; exit 1; }

echo "[auto-push] Pushed: $MSG"
