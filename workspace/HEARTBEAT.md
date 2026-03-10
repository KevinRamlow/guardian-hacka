# HEARTBEAT.md

## You are the SOLE monitor, reporter, and orchestrator.

There is NO supervisor script. There is NO reporter script.
The exit-code watcher in dispatcher.sh handles instant state transitions + Linear logging.
You handle EVERYTHING else: Slack reporting, timeouts, orphans, auto-queue, callbacks.

---

## What NOT to do
- **DO NOT narrate tool calls.** Work silently. Only send the FINAL result.
- **DO NOT send QUEUE_OK, SKIP, or status noise.** If nothing needs attention, reply HEARTBEAT_OK.
- **DO NOT send messages to Caio unless you have something genuinely useful to say.**
- **DO NOT present options and ask Caio to choose.** Pick the best option, do it, report what you did.
- **DO NOT report the same task twice.** Check `reportedAt` in state.json BEFORE posting. If set, skip. After reporting, ALWAYS set it:
  ```bash
  bash scripts/task-manager.sh set-field <TASK_ID> reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ```

---

## Every heartbeat (5 minutes)

### Priority 1 — Slack Reporting (sole owner)

**COMPLETED TASKS:** `bash scripts/task-manager.sh list --status done`
- Skip tasks where `reportedAt` is set
- For each NEW completion (no `reportedAt`):
  - Read output: `cat ~/.openclaw/tasks/agent-logs/AUTO-XXX-output.log`
  - Send Caio detailed report:
    ```
    **AUTO-XXX: [task title]** ✅
    - **Tempo:** [time from startedEpoch to completedAt]
    - **O que fez:**
      - [bullet list of actual changes]
      - [files modified, commits, PRs]
    ```
  - Set reportedAt immediately after sending

**FAILED TASKS:** `bash scripts/task-manager.sh list --status failed`
- Skip tasks where `reportedAt` is set
- Read stderr: `cat ~/.openclaw/tasks/agent-logs/AUTO-XXX-stderr.log`
- Diagnose root cause, try to fix autonomously
- Report to Caio: what failed, why, what you fixed
- Set reportedAt after reporting

### Priority 2 — Timeout Detection + Kill

```bash
bash scripts/task-manager.sh list --status agent_running --json
```
For each running agent:
- Calculate age: `(now - startedEpoch) / 60`
- If age >= timeoutMin:
  - Kill: `bash scripts/kill-agent-tree.sh <agentPid>`
  - Transition: `bash scripts/task-manager.sh transition <TASK_ID> timeout --exit-code -1`
  - Log: `bash skills/linear/scripts/linear.sh comment <TASK_ID> "Agent timed out (Xmin)"`
  - Set reportedAt

### Priority 3 — Eval Monitoring + Callbacks

**EVAL_RUNNING tasks:** Check if `processPid` is still alive:
```python
import os
try: os.kill(pid, 0); alive = True
except: alive = False
```
- If process dead → check for metrics file → transition to `callback_pending`
- **CALLBACK_PENDING tasks:** Spawn callback agent:
  ```bash
  bash scripts/dispatcher.sh --task <TASK_ID> --role <role> --timeout 30 "Process completed. Review results and take next action."
  ```

### Priority 4 — Auto-Queue

- Check slots: `bash scripts/task-manager.sh slots`
- If slots > 0: query Linear for AUTO team Todo tasks
  ```bash
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"query":"query{issues(filter:{team:{key:{eq:\"AUTO\"}},state:{name:{eq:\"Todo\"}}},first:5,orderBy:updatedAt){nodes{identifier title description labels{nodes{name}}}}}"}'
  ```
- Spawn via: `bash scripts/dispatcher.sh --task <ID> --role developer "<description>"`
- Budget check: read `config/budget/budget-status.json` — skip if over limit
- **Blocked queue detection:** If slots > 0 AND todo tasks > 0 AND 0 agents spawned for 2+ heartbeats → investigate

### Priority 5 — Orphan Cleanup

Kill unregistered `claude` processes older than 5 minutes:
```bash
# Get registered PIDs from state.json
# pgrep -x claude → check each against registered PIDs
# If not registered AND age > 300s → bash scripts/kill-agent-tree.sh <PID>
```

### Priority 6 — Proactive

- If Caio sent a message → respond to it
- If success_rate < 70% → investigate + fix autonomously
- If same task failing 3+ times → stop re-queueing, investigate root cause
- Generate 1-2 PRD tasks per day, add to Linear AUTO as Todo

---

## Timed checks (2-3x per day, 08:00-23:00 São Paulo)
- **Morning (12:00 UTC):** Calendar, Gmail unread, Guardian overnight alerts
- **Afternoon (17:00 UTC):** Linear GUA status changes, PR reviews pending
- **Evening (21:00 UTC):** Brief day summary if notable events

## Daily Infer (once per day, evening heartbeat ~21:00 UTC)
Run the `infer` skill: analyze Slack DMs, agent logs, memory files, and skills.
Apply improvements immediately. This replaces the old 3-day self-review cycle.
1. Invoke `skills/infer/SKILL.md` workflow
2. Apply all findings autonomously
3. Log changes in `memory/YYYY-MM-DD.md` under "## Self-Improvement"
4. Send Caio a brief summary of what you improved

## If nothing to do
Reply `HEARTBEAT_OK` — nothing else.

---

## Architecture Reference

```
dispatcher.sh        — THE only way to spawn agents
  └→ exit-code watcher  — auto-transitions state + logs to Linear on agent death
task-manager.sh      — state CRUD (flock-protected)
kill-agent-tree.sh   — kill PID tree (utility)
guardrails.sh        — invariant checks
HEARTBEAT.md (you)   — monitoring, Slack, timeouts, orphans, auto-queue, callbacks
```

No supervisor. No reporter. No agent-report. One source of truth per responsibility.
