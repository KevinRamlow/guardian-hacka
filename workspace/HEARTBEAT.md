# HEARTBEAT.md

## Alert Routing: All Alerts Go to Caio's DM (D0AK1B981QR)

**Use:** `bash scripts/reporter.sh notify "message"`

---

## What NOT to do
- **DO NOT reply with QUEUE_OK, SKIP, or any status noise.** If nothing needs attention, reply HEARTBEAT_OK silently.
- **DO NOT send messages to Caio's DM unless you have something genuinely useful to say.**
- **DO NOT send health alerts without also fixing the problem.** Investigate + fix FIRST, then report what you FIXED.
- **DO NOT present options and ask Caio to choose.** Pick the best option, do it, report what you did.
- **DO NOT report the same task completion or failure more than once.** Check `reportedAt` in state.json BEFORE posting. If it's set, the task was already reported — skip it. After reporting, ALWAYS set `reportedAt` via `bash scripts/task-manager.sh set-field <TASK_ID> reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"`.

## What you CAN manage autonomously
- **Timeout extension:** If agent near timeout BUT actively working → extend timeout automatically
- **Failure diagnosis:** Check failed tasks in state.json, read stderr, apply fixes autonomously
- **System health:** Fix spawn issues, auth problems, config errors without asking
- **State cleanup:** Supervisor handles dead PIDs + orphans every 30s automatically
- **Auto-queue:** Fetch Linear Todo tasks and spawn agents
- **Eval completion:** Supervisor detects completed evals → spawns callback agents automatically

## CRITICAL: Alert = Investigate + Fix

When you detect ANY problem (health alert, agent failure, error pattern):
1. **Investigate** the root cause immediately (check logs, stderr, activity)
2. **Fix it** in the same response (adjust config, restart, re-queue with fix)
3. **Report what you FIXED** to Caio — not what you found

**NEVER:** Send "health alert: success rate 14%" and wait. That's useless noise.
**ALWAYS:** Send "health alert: success rate 14%. Investigated: agents dying from auth_expired. Fixed: re-ran gcloud auth, re-queued 2 tasks. Success rate recovering."

If you send 3+ alerts about the same problem without fixing it, you failed.

## Escalation Chain (Structured)

1. **Self-heal** → Try to fix it yourself (retry, alternative approach, config change)
2. **Retry with alternative** → If first fix failed, try a different approach (max 2 retries)
3. **Heartbeat detection** → If the issue persists across 2+ heartbeats, escalate
4. **Slack notification with context** → Send Caio: what happened, what you tried, what's still broken, recommendation
5. **Block further damage** → If cascading failures, pause auto-queue and alert immediately

**Format for escalation messages:**
```
Issue: [specific description]
Tried: [what you attempted, in order]
Status: [current state]
Recommend: [your best next step]
```

## What to do

### Every heartbeat (5 minutes via native OpenClaw heartbeat)

**Priority 1 — Task State Check:**
- `bash scripts/task-manager.sh list` — see all tasks + states
- Supervisor (30s launchd) handles: PID checks, eval completions, callback dispatch, timeouts, orphans
- You handle: high-level decisions, re-queuing strategy, error pattern analysis

**Priority 2 — Auto-Queue:**
- Check available slots: `bash scripts/task-manager.sh slots`
- If slots > 0: query Linear API for AUTO team Todo tasks
  ```bash
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"query":"query{issues(filter:{team:{key:{eq:\"AUTO\"}},state:{name:{eq:\"Todo\"}}},first:5,orderBy:updatedAt){nodes{identifier title description labels{nodes{name}}}}}"}'
  ```
- Apply spawn criteria (skip quick-wins, manual tasks, read-only analysis)
- Spawn via `bash scripts/dispatcher.sh --title "X" --desc "Y" --label Bug`
- Budget check: read `self-improvement/loop/budget-status.json` — skip if over_monthly_limit
- **Blocked queue detection (CRITICAL):** If slots > 0 AND todo tasks > 0 AND you spawned 0 agents for 2+ consecutive heartbeats → investigate immediately.

**Priority 3 — Agent Health Monitoring:**
- If Caio sent you a message → respond to it
- **FAILED TASKS:** Check `bash scripts/task-manager.sh list --status failed`
  - **SKIP tasks that already have `reportedAt` set** — supervisor already processed them.
  - Read stderr log, diagnose root cause, apply fix
  - Common fixes: auth refresh, config adjustment, re-queue with different model
  - Report to Caio: what failed, why, what you fixed
  - **After reporting, mark:** `bash scripts/task-manager.sh set-field AUTO-XXX reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"`
- **COMPLETED TASKS:** Check `bash scripts/task-manager.sh list --status done`
  - **SKIP tasks that already have `reportedAt` set** — they've already been reported. Only report NEW completions.
  - For each NEW completion (no `reportedAt`), send Caio detailed report:
    ```
    **AUTO-XXX: [task title]**
    - **Tempo:** [actual time from spawn to completion]
    - **O que fez:**
      - [bullet list of actual changes made]
      - [files created/modified]
      - [commits/tests/validations]
    ```
  - Read output: `cat ~/.openclaw/tasks/agent-logs/AUTO-XXX-output.log`
  - **After reporting, ALWAYS mark as reported:** `bash scripts/task-manager.sh set-field AUTO-XXX reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"`
  - **NEVER report the same completion twice.** If `reportedAt` is set, move on.
  - **Guardian tasks:** agent MUST have run eval + reported accuracy delta
- **System health (proactive):**
  - If success_rate < 70% → investigate + fix autonomously (following escalation chain)
  - If same task failing 3+ times → STOP re-queueing, investigate root cause

**Priority 4 — Proactive Maintenance:**
- **Backlog generation (continuous brainstorming):**
  - Review recent agent outputs: patterns → feature ideas
  - Analyze system health: bottlenecks → improvement PRDs
  - Check Guardian metrics: low accuracy areas → fix candidates
  - Generate 1-2 PRD tasks per day, add to Linear AUTO workspace as Todo

### Timed checks (rotate, 2-3x per day during work hours 08:00-23:00 São Paulo)
- **Morning (12:00 UTC):** Calendar, Gmail unread, Guardian #guardian-alerts overnight
- **Afternoon (17:00 UTC):** Linear GUA status changes, PR reviews pending
- **Evening (21:00 UTC):** Brief day summary if there were notable events

### Self-review (every 3 days, during evening heartbeat)
1. Read last 1d Slack DM for Caio corrections
2. Check memory files for stale data
3. If findings → **apply fixes immediately**, then tell Caio what you improved
4. If no findings → log "Self-review: clean" and move on

### If nothing to do
Reply `HEARTBEAT_OK` — nothing else. No status dumps. No queue checks. No noise.
