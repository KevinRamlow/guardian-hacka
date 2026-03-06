# Slack-Linear Sync Setup

## Status: ⚠️ Manual step required

The Slack token lacks `channels:write` scope to create channels programmatically.

## Manual Setup Required

**Option 1: Create via Slack UI**
1. Open Slack
2. Create private channel: `#anton-linear-sync`
3. Invite yourself (Caio)
4. Get channel ID and update config

**Option 2: Create via Slack API with admin token**
```bash
# You'll need a token with channels:write scope
curl -X POST https://slack.com/api/conversations.create \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"anton-linear-sync","is_private":true}'
```

## After Channel Creation

1. Get channel ID (from Slack UI: right-click channel → Copy link, ID is at the end)
2. Update config:
```bash
jq '.channel_id = "C0XXXXXXXXX"' /root/.openclaw/workspace/config/slack-linear-sync.json > /tmp/tmp.json && mv /tmp/tmp.json /root/.openclaw/workspace/config/slack-linear-sync.json
```

3. Test:
```bash
bash /root/.openclaw/workspace/scripts/slack-linear-post.sh CAI-102 "🚀 Testing Slack-Linear sync" progress
```

## Infrastructure Created

✅ `/root/.openclaw/workspace/scripts/slack-linear-post.sh` - Sync script
✅ `/root/.openclaw/workspace/config/slack-linear-sync.json` - Config
✅ `/root/.openclaw/workspace/config/slack-linear-threads.json` - Thread mapping
✅ Updated `linear-log.sh` to dual-post (Linear + Slack)

## How It Works

1. `linear-log.sh CAI-XX "msg" [status]` → posts to Linear
2. Automatically calls `slack-linear-post.sh` with same args → posts to Slack
3. First call creates parent message with task title
4. Subsequent calls post as thread replies
5. Status changes update reaction emoji on parent message
