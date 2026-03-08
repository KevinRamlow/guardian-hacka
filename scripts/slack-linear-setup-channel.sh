#!/bin/bash
# Helper to finalize Slack-Linear sync setup once channel is created
# Usage: ./slack-linear-setup-channel.sh <channel-id>

set -e

CHANNEL_ID="$1"

if [ -z "$CHANNEL_ID" ]; then
  echo "Usage: $0 <channel-id>"
  echo ""
  echo "To get channel ID:"
  echo "1. Right-click #anton-linear-sync in Slack"
  echo "2. Click 'Copy link'"
  echo "3. Channel ID is the last part: C0XXXXXXXXX"
  exit 1
fi

CONFIG_FILE="/Users/fonsecabc/.openclaw/workspace/config/slack-linear-sync.json"

echo "Updating config with channel ID: $CHANNEL_ID"
jq --arg cid "$CHANNEL_ID" '.channel_id = $cid' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "✅ Config updated"
echo ""
echo "Test with:"
echo "bash /Users/fonsecabc/.openclaw/workspace/scripts/slack-linear-post.sh CAI-102 \"🚀 Testing Slack sync\" progress"
