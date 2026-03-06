#!/bin/bash
# Billy Agent - Quick Start Script
# Run Billy locally in Docker for testing

set -e

BILLY_DIR="/root/.openclaw/workspace/clawdbots/agents/billy"
cd "$BILLY_DIR"

echo "🤖 Billy Agent - Quick Start"
echo "================================"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Missing .env file!"
    echo ""
    echo "Create .env with these variables:"
    echo ""
    cat << 'EOF'
ANTHROPIC_API_KEY=sk-ant-api03-...
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
GEMINI_API_KEY=REDACTED_GEMINI_KEY_2
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=
MYSQL_DATABASE=db-maestro-prod
GCP_PROJECT=brandlovers-prod
EOF
    echo ""
    echo "Then run: bash quick-start.sh"
    exit 1
fi

echo "✅ Found .env file"
echo ""

# Check if container already running
if docker ps | grep -q billy; then
    echo "⚠️  Billy container already running"
    echo "Stop it first: docker stop billy && docker rm billy"
    echo "Or view logs: docker logs -f billy"
    exit 0
fi

# Build image
echo "🔨 Building Docker image..."
docker build -t billy-agent:local . -q

echo "✅ Image built"
echo ""

# Run container
echo "🚀 Starting Billy..."
docker run -d \
  --name billy \
  --env-file .env \
  --network=host \
  -v "$BILLY_DIR/workspace:/workspace" \
  -v /root/.config/gcloud:/root/.config/gcloud:ro \
  billy-agent:local

echo "✅ Billy is running!"
echo ""
echo "📋 Useful commands:"
echo "  View logs:   docker logs -f billy"
echo "  Stop Billy:  docker stop billy && docker rm billy"
echo "  Restart:     docker restart billy"
echo ""
echo "🔍 Checking status..."
sleep 3
docker logs billy --tail 20
echo ""
echo "✅ Billy should be connecting to Slack now."
echo "   Send him a DM: 'Oi Billy!'"
