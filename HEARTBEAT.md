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

## CRITICAL: Alert = Investigate + Fix

When you detect ANY problem (health alert, agent failure, error pattern):
1. **Investigate** the root cause immediately (check logs, stderr, activity)
2. **Fix it** in the same response (adjust config, restart, re-queue with fix)
3. **Report what you FIXED** to Caio — not what you found

**NEVER:** Send "health alert: success rate 14%" and wait. That's useless noise.
**ALWAYS:** Send "health alert: success rate 14%. Investigated: agents dying from auth_expired. Fixed: re-ran gcloud auth, re-queued 2 tasks. Success rate recovering."

If you send 3+ alerts about the same problem without fixing it, you failed.

## What to do

### Every heartbeat
- **Proactive timeout monitoring:** Run `bash scripts/monitor-extend-timeouts.sh` — auto-extends timeouts for active agents near deadline
- If Caio sent you a message you haven't responded to → respond to it
- If a watchdog alert exists in `/Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log` (last 5 lines) with TIMEOUT or DEAD → investigate root cause → fix → then tell Caio what you fixed
- **Agent completion validation (CRITICAL):**
  - Check for new completions: `grep "DONE:" /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log | tail -5`
  - For each completed agent: READ output, VERIFY claims, TEST if code/fix works
  - **Guardian tasks:** agent MUST have run eval + reported accuracy delta
    - Check output for "Validation: X.XX%" substring
    - If missing → agent completed WITHOUT validation → re-queue as "needs validation"
  - Don't just forward "done" → confirm it ACTUALLY works (for Guardian: confirm eval was run)
  - Report to Caio: task name + validation status + proof
- **System health check (proactive):**
  - Check agent success rate last 30min: if <50% success → investigate + fix autonomously
  - Check auto-queue failures: if same task failing 3+ times → STOP re-queueing, investigate + fix root cause
  - Check spawn-agent.sh, agent-registry.sh health: if pattern of failures → test fix → apply
  - ONLY report to Caio AFTER you've fixed it (don't just report problems)
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
