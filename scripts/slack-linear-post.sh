#!/bin/bash
# Slack-Linear sync: Post task updates to Slack thread
# Usage: slack-linear-post.sh CAI-XX "message" [status]

set -e

TASK_ID="$1"
MESSAGE="$2"
STATUS="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 CAI-XX \"message\" [status]"
  exit 1
fi

SLACK_TOKEN="REDACTED_SLACK_USER_TOKEN"
CONFIG_FILE="/root/.openclaw/workspace/config/slack-linear-sync.json"
THREAD_MAP_FILE="/root/.openclaw/workspace/config/slack-linear-threads.json"

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found at $CONFIG_FILE"
  exit 1
fi

CHANNEL_ID=$(jq -r '.channel_id' "$CONFIG_FILE")

if [ -z "$CHANNEL_ID" ] || [ "$CHANNEL_ID" = "null" ]; then
  echo "Error: channel_id not configured in $CONFIG_FILE"
  exit 1
fi

# Initialize thread map if needed
if [ ! -f "$THREAD_MAP_FILE" ]; then
  echo '{}' > "$THREAD_MAP_FILE"
fi

# Check if thread exists for this task
THREAD_TS=$(jq -r --arg task "$TASK_ID" '.[$task] // empty' "$THREAD_MAP_FILE")

# Status emoji mapping
case "$STATUS" in
  backlog) EMOJI="📋" ;;
  todo) EMOJI="📝" ;;
  in_progress|progress) EMOJI="🔄" ;;
  blocked) EMOJI="🚫" ;;
  homolog) EMOJI="🧪" ;;
  done) EMOJI="✅" ;;
  canceled) EMOJI="❌" ;;
  *) EMOJI="" ;;
esac

if [ -z "$THREAD_TS" ]; then
  # First message: Create parent with task title from Linear
  source /root/.openclaw/workspace/.env.linear 2>/dev/null || true
  
  if [ -n "$LINEAR_API_KEY" ]; then
    # Fetch task title and priority from Linear
    TASK_DATA=$(curl -s -X POST https://api.linear.app/graphql \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"query { issue(id: \\\"$TASK_ID\\\") { title priority } }\"}")
    
    TITLE=$(echo "$TASK_DATA" | jq -r '.data.issue.title // "Unknown"')
    PRIORITY=$(echo "$TASK_DATA" | jq -r '.data.issue.priority // 0')
    
    case "$PRIORITY" in
      1) PRIORITY_LABEL="🔴 Urgent" ;;
      2) PRIORITY_LABEL="🟠 High" ;;
      3) PRIORITY_LABEL="🟡 Medium" ;;
      4) PRIORITY_LABEL="🔵 Low" ;;
      *) PRIORITY_LABEL="⚪ None" ;;
    esac
  else
    TITLE="Task"
    PRIORITY_LABEL="⚪ None"
  fi
  
  STATUS_LABEL="${STATUS:-backlog}"
  case "$STATUS_LABEL" in
    backlog) STATUS_PREFIX="📋 Backlog" ;;
    todo) STATUS_PREFIX="📝 Todo" ;;
    in_progress|progress) STATUS_PREFIX="🔄 In Progress" ;;
    blocked) STATUS_PREFIX="🚫 Blocked" ;;
    homolog) STATUS_PREFIX="🧪 Homolog" ;;
    done) STATUS_PREFIX="✅ Done" ;;
    canceled) STATUS_PREFIX="❌ Canceled" ;;
    *) STATUS_PREFIX="⚪ ${STATUS_LABEL}" ;;
  esac
  
  PARENT_TEXT="${STATUS_PREFIX} — *$TASK_ID: $TITLE*"
  
  RESULT=$(curl -s -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"$CHANNEL_ID\",\"text\":\"$PARENT_TEXT\",\"mrkdwn\":true}")
  
  THREAD_TS=$(echo "$RESULT" | jq -r '.ts')
  
  if [ "$THREAD_TS" != "null" ] && [ -n "$THREAD_TS" ]; then
    # Save thread_ts
    jq --arg task "$TASK_ID" --arg ts "$THREAD_TS" '.[$task] = $ts' "$THREAD_MAP_FILE" > "${THREAD_MAP_FILE}.tmp"
    mv "${THREAD_MAP_FILE}.tmp" "$THREAD_MAP_FILE"
    
    # Add status emoji reaction
    if [ -n "$EMOJI" ]; then
      curl -s -X POST https://slack.com/api/reactions.add \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$THREAD_TS\",\"name\":\"${EMOJI}\"}" > /dev/null
    fi
    
    # Post actual message as first thread reply
    curl -s -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"thread_ts\":\"$THREAD_TS\",\"text\":\"$MESSAGE\"}" > /dev/null
  fi
else
  # Tag Caio on status changes that need attention
  CAIO_TAG=""
  case "$STATUS" in
    done|blocked|homolog) CAIO_TAG=" <@U04PHF0L65P>" ;;
  esac
  
  # Update parent message title with new status
  if [ -n "$STATUS" ]; then
    source /root/.openclaw/workspace/.env.linear 2>/dev/null || true
    if [ -n "$LINEAR_API_KEY" ]; then
      TASK_DATA=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"query { issue(id: \\\"$TASK_ID\\\") { title } }\"}")
      TITLE=$(echo "$TASK_DATA" | jq -r '.data.issue.title // "Unknown"')
    else
      TITLE="Unknown"
    fi
    
    case "$STATUS" in
      backlog) SP="📋 Backlog" ;; todo) SP="📝 Todo" ;;
      in_progress|progress) SP="🔄 In Progress" ;; blocked) SP="🚫 Blocked" ;;
      homolog) SP="🧪 Homolog" ;; done) SP="✅ Done" ;; canceled) SP="❌ Canceled" ;;
      *) SP="⚪ $STATUS" ;;
    esac
    
    curl -s -X POST https://slack.com/api/chat.update \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"ts\":\"$THREAD_TS\",\"text\":\"${SP} — *${TASK_ID}: ${TITLE}*\"}" > /dev/null 2>&1
  fi
  
  # Post as thread reply
  curl -s -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"$CHANNEL_ID\",\"thread_ts\":\"$THREAD_TS\",\"text\":\"${MESSAGE}${CAIO_TAG}\"}" > /dev/null
  
  # Update reaction if status changed
  if [ -n "$EMOJI" ]; then
    # Remove old reactions (best effort, ignore errors)
    for OLD_EMOJI in "📋" "📝" "🔄" "🚫" "🧪" "✅" "❌"; do
      curl -s -X POST https://slack.com/api/reactions.remove \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$THREAD_TS\",\"name\":\"$OLD_EMOJI\"}" > /dev/null 2>&1 || true
    done
    
    # Add new reaction
    curl -s -X POST https://slack.com/api/reactions.add \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$THREAD_TS\",\"name\":\"$EMOJI\"}" > /dev/null
  fi
fi

echo "✓ Posted to Slack: $TASK_ID"
