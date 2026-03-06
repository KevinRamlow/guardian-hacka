# HEARTBEAT.md — Productive Heartbeats

## PRIORITY 1: Queue Processing (EVERY heartbeat)

1. **Check spawn queue:** `ls /root/.openclaw/tasks/spawn-queue/*.json 2>/dev/null`
   - If pending tasks exist → spawn agents for them (max 3 concurrent)
   - After spawning → delete the .json file from spawn-queue
   - Move Linear task to "In Progress"

2. **Check running agents:** Read `/root/.openclaw/agents/claude/sessions/sessions.json`
   - Count sessions updated < 15 min ago with "acp" in key
   - If stale (>20 min no update) → mark as done/timeout
   - If completed → notify Caio with results summary

3. **Check if slots available:** If running < 3 AND spawn-queue empty
   - Run auto-queue.sh to fetch more from Linear Todo

## PRIORITY 2: Health Checks (EVERY heartbeat)

4. **Dashboard alive?** `curl -sf http://127.0.0.1:8765/ > /dev/null` → restart if dead
5. **Billy alive?** `ssh -o ConnectTimeout=3 root@89.167.64.183 'curl -sf http://127.0.0.1:18790/'` → restart if dead
6. **Gateway healthy?** Check own gateway status

## PRIORITY 3: Timed Checks (rotate, 2-3x per day)

### 9 AM (São Paulo = 12:00 UTC)
- Calendar events today
- Gmail unread (both accounts)
- Slack unread DMs
- Guardian #guardian-alerts overnight incidents

### 2 PM (17:00 UTC)
- Linear status changes on GUA issues
- PR reviews pending
- Slack threads unresolved

### 6 PM (21:00 UTC)
- Day summary for Caio
- Tomorrow's calendar preview
- Unresolved items

## Rules

- **NEVER return HEARTBEAT_OK without checking queue first**
- Always process spawn queue if items exist
- Always check agent health
- If nothing to do AND no health issues → HEARTBEAT_OK
- Keep responses SHORT (Slack message limit)
- Outside work hours (23:00-08:00 São Paulo) → only check health, no proactive msgs
