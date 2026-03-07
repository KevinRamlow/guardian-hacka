# HEARTBEAT.md

## What NOT to do
- **DO NOT manage agents, queues, or spawns.** All handled by v2 cron scripts (watchdog, auto-queue, linear-sync).
- **DO NOT reply with QUEUE_OK, SKIP, or any status noise.** If nothing needs attention, reply HEARTBEAT_OK silently.
- **DO NOT send messages to Caio's DM unless you have something genuinely useful to say.**
- **DO NOT read the old session store** (`sessions.json`). Use `agent-registry.sh list` if you need agent status.

## What to do

### Every heartbeat
- If Caio sent you a message you haven't responded to → respond to it
- If a watchdog alert exists in `/root/.openclaw/tasks/agent-logs/watchdog.log` (last 5 lines) with TIMEOUT or DEAD → tell Caio briefly
- **System health check (proactive):**
  - Check agent success rate last 30min: if <50% success → investigate + fix autonomously
  - Check auto-queue failures: if same task failing 5+ times → investigate + fix
  - Check spawn-agent.sh, agent-registry.sh health: if pattern of failures → test fix → apply
  - ONLY report to Caio AFTER you've fixed it (don't just report problems)

### Timed checks (rotate, 2-3x per day during work hours 08:00-23:00 São Paulo)
- **Morning (12:00 UTC):** Calendar, Gmail unread, Guardian #guardian-alerts overnight
- **Afternoon (17:00 UTC):** Linear GUA status changes, PR reviews pending
- **Evening (21:00 UTC):** Brief day summary if there were notable events

### If nothing to do
Reply `HEARTBEAT_OK` — nothing else. No status dumps. No queue checks. No noise.
