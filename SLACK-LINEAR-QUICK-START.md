# Slack-Linear Sync - Quick Start Guide

## For Agents: Post Updates

```bash
# Post to Linear + Slack simultaneously
linear-log.sh CAI-XX "Your message here" [status]

# Example
linear-log.sh CAI-102 "Started work on feature X" progress
linear-log.sh CAI-102 "Feature X complete" done
```

**Status options:** backlog, todo, progress, blocked, homolog, done, canceled

## For Caio: Talk to Agents

1. Go to #anton-logs in Slack
2. Find the task thread (📋 CAI-XX: Title)
3. Reply in the thread
4. Agent receives your message automatically
5. Agent responds back to same thread

## Behind the Scenes

**Channel:** #anton-logs (C0AJQ99GW6P)

**Flow:**
- `linear-log.sh` → posts to Linear → auto-posts to Slack
- Caio's Slack reply → hook routes to agent → agent responds
- Status changes → update emoji reaction on parent message

**Status Emojis:**
- 📋 backlog
- 📝 todo  
- 🔄 in_progress
- 🚫 blocked
- 🧪 homolog
- ✅ done
- ❌ canceled

## Activation

**Required once:**
```bash
openclaw gateway restart
```

This loads the `slack-thread-router` hook that enables Caio → Agent communication.

## Troubleshooting

**Agent not receiving messages?**
- Check gateway is restarted
- Verify hook is loaded: `jq '.hooks.internal.entries["slack-thread-router"]' /root/.openclaw/openclaw.json`
- Check agent is still running: `subagents list`

**Thread not created?**
- Verify channel ID: `cat /root/.openclaw/workspace/config/slack-linear-sync.json`
- Should show: `"channel_id": "C0AJQ99GW6P"`

**Status emoji not updating?**
- Valid statuses: backlog, todo, progress, blocked, homolog, done, canceled
- Case-insensitive, underscores optional (in_progress = progress)

## Files

**For reference:**
- Config: `/root/.openclaw/workspace/config/slack-linear-sync.json`
- Thread map: `/root/.openclaw/workspace/config/slack-linear-threads.json`
- Full docs: `/root/.openclaw/workspace/config/anton-logs-bidirectional.md`
- Report: `/root/.openclaw/workspace/config/CAI-102-FINAL-REPORT.md`
