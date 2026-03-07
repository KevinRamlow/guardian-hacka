#!/bin/bash
# Auto-retry blocked tasks with improved context
# Usage: retry-blocked.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

cd /root/.openclaw/workspace
source .env.linear

MAX_RETRIES=2
RETRY_DELAY_MIN=5

# Get Blocked tasks
BLOCKED_JSON=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query { issues(filter: {team: {key: {eq: \"CAI\"}}, state: {name: {eq: \"Blocked\"}}}, first: 20) { nodes { identifier title description comments(first: 10) { nodes { body createdAt }}}}}"}')

TASK_IDS=$(echo "$BLOCKED_JSON" | jq -r '.data.issues.nodes[].identifier')

if [ -z "$TASK_IDS" ]; then
  echo "No blocked tasks"
  exit 0
fi

echo "$TASK_IDS" | while read -r TASK_ID; do
  echo "Checking $TASK_ID..."
  
  # Get task details
  TASK_DATA=$(echo "$BLOCKED_JSON" | jq -r ".data.issues.nodes[] | select(.identifier == \"$TASK_ID\")")
  LAST_COMMENT=$(echo "$TASK_DATA" | jq -r '.comments.nodes[-1].body // ""')
  
  # Count retries (how many times "Retry" appears in comments)
  RETRY_COUNT=$(echo "$TASK_DATA" | jq -r '.comments.nodes[].body' | grep -c "Retry" 2>/dev/null || echo "0")
  RETRY_COUNT=$(echo "$RETRY_COUNT" | head -1)
  
  if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    echo "  ❌ Max retries ($MAX_RETRIES) reached for $TASK_ID, skipping"
    continue
  fi
  
  # Determine if retry-able
  RETRYABLE=false
  RETRY_REASON=""
  
  if echo "$LAST_COMMENT" | grep -qiE "permission|blocked|need your|approve|auth"; then
    RETRY_REASON="permissions (after 100% autonomy config)"
    RETRYABLE=true
  elif echo "$LAST_COMMENT" | grep -qiE "timeout|time out|timed out"; then
    RETRY_REASON="timeout (increasing timeout to 30min)"
    RETRYABLE=true
  elif echo "$LAST_COMMENT" | grep -qiE "not found|404|missing"; then
    RETRY_REASON="missing resource (check if now available)"
    RETRYABLE=true
  fi
  
  if [ "$RETRYABLE" = true ]; then
    echo "  ✅ Retry-able: $RETRY_REASON"
    
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY-RUN] Would retry $TASK_ID"
    else
      # Move to Todo
      bash skills/task-manager/scripts/linear-log.sh "$TASK_ID" "Retry $((RETRY_COUNT + 1))/$MAX_RETRIES: $RETRY_REASON. Previous error: ${LAST_COMMENT:0:200}" todo
      echo "  ⏳ Moved $TASK_ID to Todo (retry $((RETRY_COUNT + 1)))"
      
      # Wait before next (avoid spam)
      sleep "$RETRY_DELAY_MIN"
    fi
  else
    echo "  ⚠️  Not retry-able: requires manual intervention"
  fi
done

echo ""
echo "Retry check complete"
