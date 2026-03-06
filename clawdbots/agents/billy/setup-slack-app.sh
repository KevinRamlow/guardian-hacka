#!/bin/bash
# Billy Slack App Setup Helper
# Run this to create Billy's Slack app and get the tokens

set -e

BILLY_DIR="/root/.openclaw/workspace/clawdbots/agents/billy"
ENV_FILE="$BILLY_DIR/.env"

echo "🦞 Billy Slack App Setup"
echo "========================"
echo ""
echo "Step 1: Create Slack App"
echo "------------------------"
echo "1. Go to: https://api.slack.com/apps"
echo "2. Click 'Create New App' → 'From an app manifest'"
echo "3. Select workspace: BrandLovers"
echo "4. Paste the manifest from: $BILLY_DIR/slack-app-manifest.json"
echo "5. Click 'Create'"
echo ""
read -p "Press Enter when app is created..."
echo ""

echo "Step 2: Get Bot Token"
echo "---------------------"
echo "1. In the Slack app settings, go to 'OAuth & Permissions'"
echo "2. Click 'Install to Workspace'"
echo "3. Copy the 'Bot User OAuth Token' (starts with xoxb-)"
echo ""
read -p "Paste Bot Token: " BOT_TOKEN
echo ""

echo "Step 3: Enable Socket Mode & Get App Token"
echo "-------------------------------------------"
echo "1. Go to 'Socket Mode' in left sidebar"
echo "2. Toggle 'Enable Socket Mode' ON"
echo "3. Click 'Generate Token' (name: billy-socket, scope: connections:write)"
echo "4. Copy the token (starts with xapp-)"
echo ""
read -p "Paste App Token: " APP_TOKEN
echo ""

echo "Step 4: Update .env file"
echo "------------------------"

# Update .env file
if grep -q "SLACK_APP_TOKEN" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|SLACK_APP_TOKEN=.*|SLACK_APP_TOKEN=$APP_TOKEN|" "$ENV_FILE"
else
    echo "SLACK_APP_TOKEN=$APP_TOKEN" >> "$ENV_FILE"
fi

if grep -q "SLACK_BOT_TOKEN" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|SLACK_BOT_TOKEN=.*|SLACK_BOT_TOKEN=$BOT_TOKEN|" "$ENV_FILE"
else
    echo "SLACK_BOT_TOKEN=$BOT_TOKEN" >> "$ENV_FILE"
fi

echo "✅ .env updated with Slack tokens"
echo ""

echo "Step 5: Restart Billy"
echo "---------------------"
echo "Running: systemctl restart billy-agent"
sudo systemctl restart billy-agent
sleep 3
sudo systemctl status billy-agent --no-pager -l
echo ""

echo "✅ Billy is running!"
echo ""
echo "Test Billy:"
echo "1. Open Slack and DM @Billy"
echo "2. Send: 'Oi Billy!'"
echo "3. Check logs: journalctl -u billy-agent -f"
echo ""
