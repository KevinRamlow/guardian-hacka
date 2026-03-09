#!/bin/bash
# setup-linear-slack-sync.sh - One-time setup for Linear-Slack sync
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$WORKSPACE_DIR/config/linear-slack-sync.json"

echo "📋 Linear-Slack Sync Setup"
echo ""
echo "Since the Slack token doesn't have channels:manage scope,"
echo "you need to manually create the channel first:"
echo ""
echo "1. In Slack, create a private channel named: #anton-linear-sync"
echo "2. Invite Caio (U04PHF0L65P) to the channel"
echo "3. Copy the channel ID (right-click channel → View channel details → scroll down)"
echo ""
read -p "Enter the channel ID (starts with C): " CHANNEL_ID

if [[ ! "$CHANNEL_ID" =~ ^C[A-Z0-9]+$ ]]; then
  echo "❌ Invalid channel ID format"
  exit 1
fi

# Test channel access
SLACK_TOKEN="REDACTED_SLACK_USER_TOKEN"
test_response=$(curl -s -X POST https://slack.com/api/conversations.info \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"$CHANNEL_ID\"}")

if [[ "$(echo "$test_response" | jq -r '.ok')" != "true" ]]; then
  echo "❌ Cannot access channel: $(echo "$test_response" | jq -r '.error')"
  exit 1
fi

channel_name=$(echo "$test_response" | jq -r '.channel.name')
echo "✅ Channel verified: #$channel_name"

# Create config directory if needed
mkdir -p "$WORKSPACE_DIR/config"

# Save config
cat > "$CONFIG_FILE" <<EOF
{
  "channel_id": "$CHANNEL_ID",
  "channel_name": "$channel_name",
  "last_sync_ts": 0,
  "thread_map": {}
}
EOF

echo "✅ Config saved to: $CONFIG_FILE"

# Post intro message
intro_msg="🤖 *Anton Linear Sync Channel*

This channel mirrors Linear task activity from the CAI team. Each task gets its own thread with:
• Parent message shows task title, status, and priority
• Emoji reactions show current status at a glance
• Thread replies show updates, comments, and agent progress

Status reactions:
📋 Backlog | 📝 Todo | 🔄 In Progress | 🚫 Blocked | 🧪 Homolog | ✅ Done | ❌ Canceled

All updates posted here are also logged to Linear."

curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"$CHANNEL_ID\",\"text\":\"$intro_msg\"}" > /dev/null

echo "✅ Intro message posted"
echo ""
echo "Setup complete! Run ./scripts/linear-slack-sync.sh to start syncing."
