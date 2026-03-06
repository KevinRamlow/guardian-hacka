# Anton-Logs Bidirectional Agent Communication

## Architecture

**Channel:** `#anton-logs` (private)
**Purpose:** Bidirectional communication hub for agent orchestration

### Flow:
```
Agent spawned → Creates thread in #anton-logs
    ↓
Agent posts progress → Thread updates
    ↓
Linear updates → Thread updates (status changes, comments)
    ↓
Caio replies in thread → OpenClaw routes to agent
    ↓
Agent responds → Back to thread
```

## Setup Steps

### 1. Verify Channel Exists
```bash
SLACK_TOKEN="REDACTED_SLACK_USER_TOKEN"

curl -s "https://slack.com/api/conversations.list?types=private_channel&limit=200" \
  -H "Authorization: Bearer $SLACK_TOKEN" | jq '.channels[] | select(.name=="anton-logs")'
```

**Status:** Channel not visible to token yet
**Likely reason:** Bot not invited, or channel not created yet

### 2. Create Channel (if needed)
Via Slack UI:
1. Create private channel `#anton-logs`
2. Invite yourself (Caio)
3. Invite the bot/app that uses this token

### 3. Get Channel ID
Once visible:
```bash
CHANNEL_ID=$(curl -s "https://slack.com/api/conversations.list?types=private_channel&limit=200" \
  -H "Authorization: Bearer $SLACK_TOKEN" | jq -r '.channels[] | select(.name=="anton-logs") | .id')

# Update config
cd /root/.openclaw/workspace
bash scripts/slack-linear-setup-channel.sh "$CHANNEL_ID"
```

### 4. Configure OpenClaw to Listen
Edit `/root/.openclaw/openclaw.json` (or wherever gateway config lives):

```json
{
  "slack": {
    "channels": {
      "#anton-logs": {
        "listen": true,
        "route_threads_to_agents": true,
        "thread_routing": {
          "match_task_id": true,
          "prefix": "CAI-"
        }
      }
    }
  }
}
```

This tells OpenClaw:
- Listen to messages in #anton-logs
- When Caio replies in a thread, extract the task ID from parent message
- Route the reply to the sub-agent handling that task
- Sub-agent can respond back to the same thread

### 5. Test Bidirectional Flow

**A. Agent posts to thread:**
```bash
bash /root/.openclaw/workspace/scripts/slack-linear-post.sh CAI-999 "Test message from agent" progress
```

**B. Caio replies in thread:**
Reply to the thread in Slack → OpenClaw should route to agent

**C. Agent responds:**
Agent uses same script to post back → thread continues

## Current Status

⚠️ **Channel not visible** - needs creation or bot invitation
📝 **Config ready** - will auto-configure once channel found
✅ **Scripts ready** - bidirectional posting infrastructure complete

## Implementation Notes

### Thread-to-Agent Routing (OpenClaw Gateway)
Need to implement or configure:
1. Gateway watches #anton-logs for new messages
2. Extract parent thread metadata (task ID from parent message)
3. Find running sub-agent by task ID
4. Inject Slack message into agent's session
5. Agent's response auto-posts back via slack-linear-post.sh

### Linear Sync to Slack
Current: Manual via linear-log.sh
Needed: Webhook from Linear → posts to thread
- Linear webhook → gateway endpoint
- Extract task ID, comment, status
- Post to corresponding Slack thread via slack-linear-post.sh

Alternative: Poll Linear periodically for updates (less elegant)
