# HEARTBEAT.md

## What NOT to do
- **DO NOT reply with QUEUE_OK, SKIP, or any status noise.** If nothing needs attention, reply HEARTBEAT_OK silently.
- **DO NOT send messages to Caio's DM unless you have something genuinely useful to say.**
- **DO NOT read the old session store** (`sessions.json`). Use `agent-registry.sh list` if you need agent status.
- **DO NOT send health alerts without also fixing the problem.** If you detect an issue, investigate + fix FIRST, then report what you FIXED.
- **DO NOT present options and ask Caio to choose.** Pick the best option, do it, report what you did.

## What you CAN manage autonomously
- **Timeout extension:** If agent near timeout BUT actively working (eval running, output growing, activity recent) → extend timeout automatically
- **Failure diagnosis:** Run `diagnose-failure.sh` on failed agents, apply fixes autonomously
- **System health:** Fix spawn issues, auth problems, config errors without asking
- **Registry cleanup:** Remove dead PIDs, sync Linear status mismatches
- **Auto-queue:** Fetch Linear Todo tasks and spawn agents (replaces old auto-queue-v2.sh cron)
- **Eval completion:** Check for completed evals and trigger next iteration (replaces old eval-completion-check.sh cron)

## CRITICAL: Alert = Investigate + Fix

When you detect ANY problem (health alert, agent failure, error pattern):
1. **Investigate** the root cause immediately (check logs, stderr, activity)
2. **Fix it** in the same response (adjust config, restart, re-queue with fix)
3. **Report what you FIXED** to Caio — not what you found

**NEVER:** Send "health alert: success rate 14%" and wait. That's useless noise.
**ALWAYS:** Send "health alert: success rate 14%. Investigated: agents dying from auth_expired. Fixed: re-ran gcloud auth, re-queued 2 tasks. Success rate recovering."

If you send 3+ alerts about the same problem without fixing it, you failed.

## Escalation Chain (Structured)

When you encounter a problem, follow this chain in order:

1. **Self-heal** → Try to fix it yourself (retry, alternative approach, config change)
2. **Retry with alternative** → If first fix failed, try a different approach (max 2 retries)
3. **Heartbeat detection** → If the issue persists across 2+ heartbeats, escalate
4. **Slack notification with context** → Send Caio a message with: what happened, what you tried, what's still broken, what you recommend
5. **Block further damage** → If an issue is causing cascading failures, pause auto-queue and alert immediately

**Format for escalation messages:**
```
Issue: [specific description]
Tried: [what you attempted, in order]
Status: [current state]
Recommend: [your best next step]
```

## What to do

### Every heartbeat (runs every 5 minutes via native OpenClaw heartbeat)

**Priority 1 — Eval Completion Check (absorbs eval-completion-check.sh):**
- Check for completed Guardian evals:
  ```bash
  ls -t ~/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_*/progress_meta.json 2>/dev/null | head -1
  ```
- If latest run has `status: "completed"` AND no `.reported` flag → analyze results, post to Slack, write trigger file, spawn next iteration
- Read `~/.openclaw/workspace/.eval-completed-trigger` — if it exists, an eval just finished. Read the JSON, analyze the breakdown, spawn next iteration agents, then `rm` the trigger file.

**Priority 2 — Auto-Queue (absorbs auto-queue-v2.sh):**
- Check available agent slots: `bash scripts/agent-registry.sh slots`
- If slots > 0: query Linear API for CAI team Todo tasks
  ```bash
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"query":"query{issues(filter:{team:{key:{eq:\"CAI\"}},state:{name:{eq:\"Todo\"}}},first:5,orderBy:updatedAt){nodes{identifier title description labels{nodes{name}}}}}"}'
  ```
- Apply spawn criteria (skip quick-wins, manual tasks, read-only analysis)
- Spawn via `bash scripts/spawn-agent.sh --task CAI-XX --label "desc" "task text"`
- Budget check: read `self-improvement/loop/budget-status.json` — skip if over_monthly_limit

**Priority 3 — Agent Health Monitoring:**
- If Caio sent you a message you haven't responded to → respond to it
- Check watchdog alerts: `grep "TIMEOUT\|DEAD\|FAIL" ~/.openclaw/tasks/agent-logs/watchdog.log | tail -5`
- For each alert → investigate root cause → fix → then tell Caio what you fixed
- **Agent completion validation (CRITICAL):**
  - Check for new completions: `grep "DONE:" ~/.openclaw/tasks/agent-logs/watchdog.log | tail -5`
  - For each completed agent: READ output, VERIFY claims, TEST if code/fix works
  - **Guardian tasks:** agent MUST have run eval + reported accuracy delta
    - Check output for "Validation: X.XX%" substring
    - If missing → agent completed WITHOUT validation → re-queue as "needs validation"
  - Report to Caio: task name + validation status + proof
- **System health check (proactive):**
  - Check agent success rate: read `~/.openclaw/workspace/metrics/agent-health.json`
  - If success_rate < 70% → investigate + fix autonomously (following escalation chain)
  - Check if same task failing 3+ times → STOP re-queueing, investigate root cause

**Priority 4 — Proactive Maintenance:**
- Run `bash scripts/monitor-extend-timeouts.sh` — auto-extends timeouts for active agents near deadline
- **Backlog generation (continuous brainstorming):**
  - Review recent agent outputs: patterns → feature ideas
  - Analyze system health: bottlenecks → improvement PRDs
  - Check Guardian metrics: low accuracy areas → fix candidates
  - Generate 1-2 PRD tasks per day, add to Linear CAI workspace as Todo

### Timed checks (rotate, 2-3x per day during work hours 08:00-23:00 São Paulo)
- **Morning (12:00 UTC):** Calendar, Gmail unread, Guardian #guardian-alerts overnight
- **Afternoon (17:00 UTC):** Linear GUA status changes, PR reviews pending
- **Evening (21:00 UTC):** Brief day summary if there were notable events

### Self-review (every 3 days, during evening heartbeat)
Run `skills/self-improve/SKILL.md` mini self-review:
1. Read last 1d Slack DM for Caio corrections
2. Check memory files for stale data
3. If findings → **apply fixes immediately**, then tell Caio what you improved
4. If no findings → log "Self-review: clean" and move on

### If nothing to do
Reply `HEARTBEAT_OK` — nothing else. No status dumps. No queue checks. No noise.
