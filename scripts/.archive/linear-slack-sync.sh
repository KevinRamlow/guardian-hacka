#!/bin/bash
# linear-slack-sync.sh - Sync Linear task activity to Slack channel with threaded updates
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$WORKSPACE_DIR/config/linear-slack-sync.json"

# Load Linear API key
source "$WORKSPACE_DIR/.env.linear" 2>/dev/null || {
  echo "❌ Failed to load Linear API key"
  exit 1
}

# Slack token from TOOLS.md
SLACK_TOKEN="REDACTED_SLACK_USER_TOKEN"

# Load config (channel ID, last sync, thread map)
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ Config file not found: $CONFIG_FILE"
  echo "Run setup first to create channel and config"
  exit 1
fi

CHANNEL_ID=$(jq -r '.channel_id' "$CONFIG_FILE")
LAST_SYNC=$(jq -r '.last_sync_ts // 0' "$CONFIG_FILE")
THREAD_MAP=$(jq -r '.thread_map // {}' "$CONFIG_FILE")

# Status emoji mapping
declare -A STATUS_EMOJI=(
  ["backlog"]="📋"
  ["todo"]="📝"
  ["in progress"]="🔄"
  ["blocked"]="🚫"
  ["homolog"]="🧪"
  ["done"]="✅"
  ["canceled"]="❌"
)

# Get parent message TS for a task (from thread_map)
get_thread_ts() {
  local task_id="$1"
  echo "$THREAD_MAP" | jq -r --arg id "$task_id" '.[$id] // empty'
}

# Save thread TS for a task
save_thread_ts() {
  local task_id="$1"
  local ts="$2"
  THREAD_MAP=$(echo "$THREAD_MAP" | jq --arg id "$task_id" --arg ts "$ts" '.[$id] = $ts')
  jq --arg map "$THREAD_MAP" '.thread_map = ($map | fromjson)' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

# Update status reaction on parent message
update_status_reaction() {
  local task_id="$1"
  local old_status="$2"
  local new_status="$3"
  local thread_ts=$(get_thread_ts "$task_id")
  
  if [[ -z "$thread_ts" ]]; then
    return
  fi
  
  # Normalize status strings to lowercase
  old_status=$(echo "$old_status" | tr '[:upper:]' '[:lower:]')
  new_status=$(echo "$new_status" | tr '[:upper:]' '[:lower:]')
  
  local old_emoji="${STATUS_EMOJI[$old_status]}"
  local new_emoji="${STATUS_EMOJI[$new_status]}"
  
  # Remove old reaction if exists
  if [[ -n "$old_emoji" ]]; then
    curl -s -X POST https://slack.com/api/reactions.remove \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$thread_ts\",\"name\":\"${old_emoji}\"}" > /dev/null 2>&1 || true
  fi
  
  # Add new reaction
  if [[ -n "$new_emoji" ]]; then
    curl -s -X POST https://slack.com/api/reactions.add \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$thread_ts\",\"name\":\"${new_emoji}\"}" > /dev/null 2>&1 || true
  fi
}

# Post or update thread for a task
post_task_update() {
  local task_id="$1"
  local title="$2"
  local status="$3"
  local priority="$4"
  local message="$5"
  local thread_ts=$(get_thread_ts "$task_id")
  
  # Normalize status for emoji lookup
  local status_lower=$(echo "$status" | tr '[:upper:]' '[:lower:]')
  local status_emoji="${STATUS_EMOJI[$status_lower]}"
  
  if [[ -z "$thread_ts" ]]; then
    # Create new parent thread
    local parent_text="📋 *$task_id: $title* | Status: $status | Priority: $priority"
    local response=$(curl -s -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"text\":\"$parent_text\"}")
    
    thread_ts=$(echo "$response" | jq -r '.ts // empty')
    if [[ -n "$thread_ts" ]]; then
      save_thread_ts "$task_id" "$thread_ts"
      
      # Add initial status reaction
      if [[ -n "$status_emoji" ]]; then
        curl -s -X POST https://slack.com/api/reactions.add \
          -H "Authorization: Bearer $SLACK_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"channel\":\"$CHANNEL_ID\",\"timestamp\":\"$thread_ts\",\"name\":\"${status_emoji}\"}" > /dev/null 2>&1 || true
      fi
    fi
  fi
  
  # Post update as thread reply
  if [[ -n "$thread_ts" && -n "$message" ]]; then
    curl -s -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer $SLACK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\":\"$CHANNEL_ID\",\"thread_ts\":\"$thread_ts\",\"text\":\"$message\"}" > /dev/null
  fi
}

# Fetch recent Linear activity for CAI team
fetch_linear_updates() {
  local since_date=$(date -d "@$LAST_SYNC" -Iseconds 2>/dev/null || date -r "$LAST_SYNC" -Iseconds 2>/dev/null || echo "2026-03-01T00:00:00Z")
  
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY_RW" \
    -H "Content-Type: application/json" \
    -d "{
      \"query\": \"query { team(id: \\\"d8e12cf6-deff-4e80-bdbe-2f0c7c1a09ec\\\") { issues(filter: { updatedAt: { gte: \\\"$since_date\\\" } }, orderBy: updatedAt) { nodes { id identifier title state { name } priority priorityLabel updatedAt comments { nodes { body createdAt user { name } } } history(first: 50) { nodes { createdAt fromState { name } toState { name } } } } } } }\"
    }"
}

# Process updates and post to Slack
process_updates() {
  local data="$1"
  local issues=$(echo "$data" | jq -r '.data.team.issues.nodes[]' 2>/dev/null)
  
  if [[ -z "$issues" ]]; then
    return
  fi
  
  echo "$data" | jq -c '.data.team.issues.nodes[]' | while read -r issue; do
    local task_id=$(echo "$issue" | jq -r '.identifier')
    local title=$(echo "$issue" | jq -r '.title')
    local status=$(echo "$issue" | jq -r '.state.name')
    local priority=$(echo "$issue" | jq -r '.priorityLabel // "None"')
    
    # Check for status changes in history
    local history=$(echo "$issue" | jq -c '.history.nodes[] | select(.fromState != null and .toState != null)')
    if [[ -n "$history" ]]; then
      echo "$history" | while read -r change; do
        local from_status=$(echo "$change" | jq -r '.fromState.name')
        local to_status=$(echo "$change" | jq -r '.toState.name')
        local change_time=$(echo "$change" | jq -r '.createdAt')
        
        # Post status change and update reaction
        post_task_update "$task_id" "$title" "$to_status" "$priority" "🔄 Status changed: $from_status → $to_status"
        update_status_reaction "$task_id" "$from_status" "$to_status"
      done
    fi
    
    # Check for new comments
    local comments=$(echo "$issue" | jq -c '.comments.nodes[]')
    if [[ -n "$comments" ]]; then
      echo "$comments" | while read -r comment; do
        local comment_text=$(echo "$comment" | jq -r '.body')
        local author=$(echo "$comment" | jq -r '.user.name // "Unknown"')
        
        post_task_update "$task_id" "$title" "$status" "$priority" "💬 $author: $comment_text"
      done
    fi
  done
}

# Main sync loop
echo "🔄 Syncing Linear → Slack (channel: $CHANNEL_ID, since: $LAST_SYNC)"
linear_data=$(fetch_linear_updates)
process_updates "$linear_data"

# Update last sync timestamp
NEW_SYNC=$(date +%s)
jq --arg ts "$NEW_SYNC" '.last_sync_ts = ($ts | tonumber)' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "✅ Sync complete (new timestamp: $NEW_SYNC)"
