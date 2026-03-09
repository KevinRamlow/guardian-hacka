#!/bin/bash
# notify-slack.sh - Send notification to Slack
# Usage: bash scripts/notify-slack.sh "message text" [channel]

MESSAGE="$1"
CHANNEL="${2:-D0AK1B981QR}"  # Default to Caio's DM

if [[ -z "$MESSAGE" ]]; then
  echo "Usage: $0 \"message\""
  exit 1
fi

# Use message tool via openclaw CLI
openclaw message send \
  --channel slack \
  --target "$CHANNEL" \
  --message "$MESSAGE" \
  2>/dev/null || echo "Failed to send Slack notification"
