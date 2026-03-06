# Anton-Logs: Bidirectional Agent Communication System

## Status: ✅ CONFIGURED

**Channel:** `#anton-logs` (C0AJQ99GW6P)
**Purpose:** Real-time bidirectional communication between Caio and sub-agents

## Architecture

### Thread Structure
Each task/agent gets ONE thread:
- **Parent message:** `📋 CAI-XX: Task Title | Status | Priority`
- **Thread replies:** Progress updates, Linear sync, Caio's messages to agent

### Message Flow

```
┌─────────────────────────────────────────────────────┐
│  #anton-logs Channel (C0AJQ99GW6P)                  │
│                                                     │
│  📋 CAI-102: Slack-Linear Sync (🔄 in_progress)    │
│      └─ 🚀 Agent: "Starting work..."               │
│      └─ 📍 Agent: "Built script X"                 │
│      └─ 💬 Caio: "Change this to Y"               │ ← OpenClaw routes to agent
│      └─ ✅ Agent: "Done, updated to Y"             │
│      └─ 📊 Linear: "Status → Done"                 │
└─────────────────────────────────────────────────────┘
```

## How It Works

### 1. Agent → Slack (WORKING NOW)
```bash
# Agent posts update
bash /root/.openclaw/workspace/scripts/slack-linear-post.sh CAI-XX "message" [status]

# Creates/updates thread in #anton-logs
# Updates status emoji on parent message
```

### 2. Linear → Slack (WORKING NOW)
```bash
# When logging to Linear, also posts to Slack
bash /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]

# Dual-posts to both Linear + Slack thread
```

### 3. Caio → Agent (CONFIGURED, needs routing logic)

**OpenClaw Config:** ✅ Listening enabled
**Location:** `/root/.openclaw/openclaw.json`

```json
{
  "channels": {
    "slack": {
      "channels": {
        "C0AJQ99GW6P": {
          "allow": true,
          "listen": true,
          "route_threads": true
        }
      }
    }
  }
}
```

**Routing Logic Needed:**

When Caio replies in a thread:
1. OpenClaw receives message from #anton-logs
2. Extract `thread_ts` → lookup task ID in `/root/.openclaw/workspace/config/slack-linear-threads.json`
3. Find running sub-agent by task ID (via subagents list)
4. Inject message into agent's session context
5. Agent processes and responds via slack-linear-post.sh

**Implementation:**

Option A: **OpenClaw Hook** (recommended)
- Hook: `/root/.openclaw/hooks/slack-thread-router.js`
- Triggers on: message in #anton-logs with `thread_ts`
- Action: Lookup task, find agent, inject message

Option B: **Gateway Plugin** (if hooks insufficient)
- Custom plugin that watches Slack events
- Routes based on thread_ts mapping

Option C: **Polling Script** (fallback, less elegant)
- Cron job checks Slack threads every 30s
- Compares to last-seen message
- Injects new messages to agents

### 4. Status Reactions (WORKING NOW)
Status changes update parent message emoji:
- 📋 backlog
- 📝 todo
- 🔄 in_progress
- 🚫 blocked
- 🧪 homolog
- ✅ done
- ❌ canceled

## Configuration Files

1. `/root/.openclaw/workspace/config/slack-linear-sync.json`
   - Channel ID: C0AJQ99GW6P
   
2. `/root/.openclaw/workspace/config/slack-linear-threads.json`
   - Maps: `{"CAI-XX": "thread_ts"}`
   
3. `/root/.openclaw/openclaw.json`
   - Slack channel listening config

## Testing

### Test Agent → Slack
```bash
bash /root/.openclaw/workspace/scripts/slack-linear-post.sh CAI-999 "Test from agent" progress
```

### Test Linear → Slack (dual-post)
```bash
bash /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-999 "Test sync" done
```

### Test Caio → Agent
1. Go to #anton-logs in Slack
2. Find task thread (e.g., CAI-102)
3. Reply in thread: "Hello agent, can you hear me?"
4. **Expected:** Agent receives message and can respond
   **Current:** Needs routing hook implementation

## Next Steps

### For Full Bidirectional (Caio → Agent):
1. Implement Slack thread router hook
2. Test message injection to sub-agent
3. Verify agent can respond back

### Alternative: Manual Message Relay
Until routing hook is ready, Caio can manually pass messages:
```bash
# In main thread
subagents steer CAI-102 "Caio says: update X to Y"
```

## Current Capabilities

✅ Agent posts to Slack threads
✅ Linear syncs to Slack threads  
✅ Status reactions on parent messages
✅ Thread mapping persisted
✅ OpenClaw listening to channel
⏳ Caio → Agent routing (needs hook implementation)

## Production Use

**Ready to use NOW for:**
- Viewing agent progress in Slack
- Tracking task status via reactions
- Seeing Linear updates in Slack
- Monitoring multiple agents in parallel

**Coming soon:**
- Direct conversation with agents via Slack threads
- Agent receives Caio's messages automatically
- True bidirectional collaboration
