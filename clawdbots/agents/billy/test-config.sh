#!/bin/bash
# Billy Configuration Test Script

set -e

BILLY_ROOT="/root/.openclaw/workspace/clawdbots/agents/billy"
cd "$BILLY_ROOT"

echo "🧪 Testing Billy's Configuration..."
echo ""

# Test 1: Slack allowlist
echo "1️⃣ Checking Slack access control..."
ALLOWED_USERS=$(cat openclaw.json | jq -r '.channels.slack.allowedUsers[]')
if [ "$ALLOWED_USERS" = "U04PHF0L65P" ]; then
    echo "   ✅ Slack allowlist correct: Only Caio (U04PHF0L65P)"
else
    echo "   ❌ FAIL: Expected U04PHF0L65P, got: $ALLOWED_USERS"
    exit 1
fi

# Test 2: Linear environment
echo "2️⃣ Checking Linear integration..."
source .env
if [ "$LINEAR_DEFAULT_TEAM" = "CAI" ]; then
    echo "   ✅ Linear team: CAI"
else
    echo "   ❌ FAIL: LINEAR_DEFAULT_TEAM not set to CAI"
    exit 1
fi

if [ -n "$LINEAR_API_KEY" ]; then
    echo "   ✅ Linear API key configured"
else
    echo "   ❌ FAIL: LINEAR_API_KEY not set"
    exit 1
fi

# Test 3: Workspace isolation
echo "3️⃣ Checking workspace isolation..."
if [ -d "workspace/skills/linear" ]; then
    echo "   ✅ Linear skill present in Billy's workspace"
else
    echo "   ❌ FAIL: Linear skill not found"
    exit 1
fi

if [ -f "workspace/TOOLS.md" ]; then
    echo "   ✅ TOOLS.md exists in Billy's workspace"
else
    echo "   ❌ FAIL: TOOLS.md not found"
    exit 1
fi

# Test 4: Skills isolation
echo "4️⃣ Checking skills..."
SKILL_COUNT=$(ls -1 workspace/skills/ | wc -l)
if [ "$SKILL_COUNT" -ge 8 ]; then
    echo "   ✅ Billy has $SKILL_COUNT skills"
else
    echo "   ⚠️  WARNING: Only $SKILL_COUNT skills found (expected 8+)"
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📋 Summary:"
echo "   - Slack: Only responds to Caio (U04PHF0L65P)"
echo "   - Linear: Configured for CAI team task logging"
echo "   - Workspace: Isolated at $BILLY_ROOT/workspace/"
echo "   - Skills: $SKILL_COUNT total (including Linear)"
