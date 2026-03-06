#!/usr/bin/env bash
# Commit workspace changes to git AND sync to Billy
# Usage: sync-and-commit.sh "description of changes"
set -euo pipefail

MSG="${1:-auto: workspace update}"
DIR="$(dirname "$0")"

echo "📝 Committing..."
bash "$DIR/auto-commit.sh" "$MSG"

echo ""
echo "🔄 Syncing to Billy..."
bash "$DIR/sync-to-billy.sh" --all

echo ""
echo "✅ All done: committed + synced to Billy"
