#!/bin/bash
# Start Billy gateway (simple approach, no Docker)

cd /root/.openclaw/workspace/clawdbots/agents/billy

# Set config path
export OPENCLAW_CONFIG="$(pwd)/openclaw.json"

echo "🦞 Starting Billy on port 18790..."
echo "Config: $OPENCLAW_CONFIG"
echo ""

# Start in background
nohup openclaw gateway > billy.log 2>&1 &
BILLY_PID=$!

echo "Billy PID: $BILLY_PID"
echo "Log: $(pwd)/billy.log"
echo ""
echo "Check status: tail -f $(pwd)/billy.log"
echo "Stop Billy: kill $BILLY_PID"
