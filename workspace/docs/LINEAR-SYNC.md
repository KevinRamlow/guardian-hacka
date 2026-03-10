# Linear Task Sync System

**Purpose:** Automatically keep Linear tasks (caio-tests workspace, CAI team) updated with sub-agent status reports.

---

## How It Works

### Architecture

```
┌─────────────────┐
│  Cron Job       │ Every 15 minutes
│  (15min timer)  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│  linear-sync.sh                 │
│  - Query Linear for CAI tasks   │
│  - Check OpenClaw subagents     │
│  - Check ACP (Claude Code)      │
│  - Match sessions to tasks      │
│  - Update descriptions/comments │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Linear GraphQL API             │
│  - Update task descriptions     │
│  - Add status comments          │
│  - Change task states           │
└─────────────────────────────────┘
```

---

## Components

### 1. Sync Script

**Location:** `/Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh`

**Functions:**
- `linear_query()` — Call Linear GraphQL API
- `update_task_description()` — Replace task description with full report
- `add_task_comment()` — Add timestamped status update as comment
- `update_task_status()` — Change task state (In Progress → Done)
- `get_openclaw_subagents()` — List active OpenClaw subagents
- `get_acp_sessions()` — List active Claude Code (ACP) agents
- `generate_subagent_report()` — Create status update text
- `sync_tasks()` — Main loop: query tasks, match agents, update

**Detection Logic:**
1. Fetch all CAI team tasks (exclude Done/Canceled)
2. Extract session ID from task description (`Session: <uuid>`)
3. Check if session is active in OpenClaw subagents
4. Check if session is active in ACP runtime
5. Generate status report with runtime, model, status
6. Update task (description or comment) if stale (not updated today)
7. Mark task Done if sub-agent completed

**Prevents Spam:**
- Only updates once per day (checks "Last updated: YYYY-MM-DD")
- Uses comments for incremental updates (preserves original description)
- No updates if task already Done/Canceled

---

### 2. Cron Job

**Schedule:** Every 15 minutes  
**Command:** `/Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh`  
**Logs:** `/Users/fonsecabc/.openclaw/workspace/logs/linear-sync.log`

**Installation:**
```bash
crontab -e
# Add:
*/15 * * * * /Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh >> /Users/fonsecabc/.openclaw/workspace/logs/linear-sync.log 2>&1
```

**Verify:**
```bash
crontab -l | grep linear-sync
```

---

### 3. State File

**Location:** `/Users/fonsecabc/.openclaw/workspace/.linear-sync-state.json`

**Format:**
```json
{
  "lastSync": 1772720400000,
  "taskAgents": {
    "CAI-35": "a4efdc80-3627-4349-a3b0-08dd5503b7fd",
    "CAI-38": "e76fed24-a8ca-4a9d-8b33-6583c8ffaf41"
  }
}
```

**Purpose:**
- Track last successful sync timestamp
- Map Linear tasks to sub-agent session IDs
- Detect orphaned tasks (session ended but task not updated)

---

## Task Requirements

For a Linear task to be auto-synced, it MUST include:

```markdown
Session: <session-id>
```

**Where to find session ID:**
- OpenClaw subagents: `openclaw agent --agent <role>` → PID tracked in state.json
- All agents spawned via `dispatcher.sh` → `spawn-agent.sh` (NEVER directly)

**Example task description:**
```markdown
# Task Title

**Goal:** Do something useful

**Session:** a4efdc80-3627-4349-a3b0-08dd5503b7fd

---

## Status

Work in progress...
```

---

## Status Updates

### Format

Every 15 minutes (if task not already updated today), adds a comment:

```markdown
**Sub-Agent Status Update** (Auto-generated)

🔄 **Status:** running
⏱️ **Runtime:** 26m
🤖 **Model:** anthropic/claude-opus-4-6
🔑 **Session:** `a4efdc80-3627-4349-a3b0-08dd5503b7fd`

_Last updated: 2026-03-05 14:30 UTC_
```

### Auto-Completion

When a sub-agent finishes (status = "done"), the sync script:
1. Detects completion in `subagents list` recent section
2. Updates Linear task state to "Done"
3. Adds final comment with completion timestamp

---

## Monitoring

### Check Sync Logs

```bash
tail -f /Users/fonsecabc/.openclaw/workspace/logs/linear-sync.log
```

**Expected output:**
```
🔄 Starting Linear task sync...
  📋 Checking CAI-35: GUA-1100 Archetype Eval Loop
    🔄 Found active ACP (Claude Code) agent
    ⏭️  Already updated today
  📋 Checking CAI-38: Billy Slack Deployment
    🔄 Found active OpenClaw subagent
    ✏️  Updating task with latest status
✅ Sync complete
```

### Manual Sync

```bash
/Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh
```

### Check Cron Status

```bash
# Last run
ls -lh /Users/fonsecabc/.openclaw/workspace/logs/linear-sync.log

# Cron schedule
crontab -l | grep linear-sync
```

---

## Configuration

### Environment Variables

**Required in `.env.linear`:**
```bash
export LINEAR_API_KEY="[REDACTED]"
export LINEAR_DEFAULT_TEAM="CAI"
```

### API Permissions

The Linear API key needs:
- ✅ Read issues (team: CAI)
- ✅ Update issue descriptions
- ✅ Create issue comments
- ✅ Update issue states

---

## Supported Runtimes

### 1. OpenClaw Subagents (`runtime="subagent"`)

**Detection:**
```bash
openclaw sessions-list --requester agent:main:main --json
```

**Example:**
```json
{
  "active": [
    {
      "sessionKey": "agent:main:subagent:e76fed24-a8ca-4a9d-8b33-6583c8ffaf41",
      "label": "billy-slack-deploy",
      "status": "running",
      "runtimeMs": 356653,
      "model": "anthropic/claude-sonnet-4-5"
    }
  ]
}
```

### 2. Claude Code (ACP) Agents (`runtime="acp"`)

**Detection:**
```bash
openclaw sessions-list --runtime acp --json
```

**Example:**
```json
{
  "active": [
    {
      "sessionKey": "agent:main:subagent:a4efdc80-3627-4349-a3b0-08dd5503b7fd",
      "label": "gua-1100-resume",
      "status": "running",
      "runtimeMs": 1577539,
      "model": "anthropic/claude-opus-4-6"
    }
  ]
}
```

---

## Troubleshooting

### Task Not Updating

**Possible causes:**
1. ❌ No session ID in task description
2. ❌ Session ID format wrong (must be UUID)
3. ❌ Sub-agent already completed (check recent list)
4. ❌ Already updated today (only 1 update per day to avoid spam)

**Solution:**
```bash
# Check sub-agent status
subagents list

# Check if session ID matches
grep -r "Session: <id>" /Users/fonsecabc/.openclaw/workspace/

# Force manual sync
/Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh
```

### Cron Not Running

**Check cron service:**
```bash
systemctl status cron
```

**Check cron logs:**
```bash
grep CRON /var/log/syslog
```

**Verify crontab:**
```bash
crontab -l
```

### API Errors

**Check Linear API key:**
```bash
source /Users/fonsecabc/.openclaw/workspace/.env.linear
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { id name } }"}' | jq
```

**Expected response:**
```json
{
  "data": {
    "viewer": {
      "id": "...",
      "name": "Caio Fonseca"
    }
  }
}
```

---

## Future Enhancements

1. **Slack Notifications** — Post to #tech-gua-ma-internal when tasks complete
2. **Budget Tracking** — Alert when sub-agent exceeds time/cost limits
3. **Performance Metrics** — Track avg completion time per task type
4. **Auto-Retry** — Re-spawn failed sub-agents automatically
5. **Dependency Chains** — Auto-start task B when task A completes
6. **Weekly Digest** — Summary of all completed tasks

---

## Examples

### Create a Tracked Task

```bash
# Option 1: Via task-manager skill
./skills/task-manager/scripts/task-manager.sh track-agent \
  "a4efdc80-3627-4349-a3b0-08dd5503b7fd" \
  "GUA-1100 Archetype Eval Loop"

# Option 2: Manually in Linear UI
# 1. Create task in CAI team
# 2. Add to description:
#    Session: a4efdc80-3627-4349-a3b0-08dd5503b7fd
# 3. Set status to "In Progress"
```

### Monitor a Task

```bash
# Watch sync logs
tail -f /Users/fonsecabc/.openclaw/workspace/logs/linear-sync.log

# Check task in Linear
open "https://linear.app/caio-tests/issue/CAI-35"
```

### Manual Update

```bash
# Force sync now (doesn't wait for cron)
/Users/fonsecabc/.openclaw/workspace/scripts/linear-sync.sh

# Check what changed
git -C /Users/fonsecabc/.openclaw/workspace diff .linear-sync-state.json
```

---

**Setup Date:** 2026-03-05  
**Maintained By:** Anton (AI Orchestrator)  
**Linear Workspace:** caio-tests (team: CAI)
