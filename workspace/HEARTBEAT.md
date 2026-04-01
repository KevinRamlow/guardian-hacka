# HEARTBEAT.md — Sentinel

## You are the SOLE monitor, reporter, and orchestrator.

No supervisor script. No reporter script.
Exit-code watcher in dispatcher.sh handles instant state transitions + Linear logging.
You handle: Slack reporting, timeouts, orphans, callbacks, improvement loop.

---

## What NOT to do
- **DO NOT narrate tool calls.** Work silently. Only send the FINAL result.
- **DO NOT send QUEUE_OK, SKIP, or status noise.** If nothing needs attention, reply HEARTBEAT_OK.
- **DO NOT present options and ask to choose.** Pick the best option, do it, report what you did.
- **DO NOT report the same task twice.** Check `reportedAt` before posting. After reporting, ALWAYS set it:
  ```bash
  bash scripts/task-manager.sh set-field <TASK_ID> reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ```
- **ONE message per task. EVER.** Never send 2+ messages about the same task result.

---

## Every heartbeat (5 minutes)

### Priority 0 — Linear Task Intake (two parallel mechanics)

**Mechanic A — Active search (heartbeat-driven):**
Polls the Linear GAS board every heartbeat for Backlog and To Do cards:

```bash
bash scripts/linear-watcher.sh
```

- Queries Linear GAS team for tasks in **Backlog** or **To Do** state only
- Skips tasks already tracked in `state.json` (idempotent)
- Moves each picked-up task to "In Progress" in Linear
- Dispatches a PM agent with the full card context (title, description, priority, labels)
- Stops when no slots are available

Only run if there are available slots. If `task-manager.sh slots` returns 0, skip.

**Mechanic B — Slack mention (event-driven):**
When someone mentions the bot in Slack with a Linear card number (e.g. `GAS-42`), the main agent handles it directly per the **Slack Direct Dispatch** section in `SOUL.md`:
- Validates the card is in **Backlog** or **To Do** via `scripts/linear-fetch-card.sh`
- Deduplicates against `state.json`
- Dispatches PM agent with the fetched card context

Both mechanics are independent and idempotent — a card dispatched via Slack will be skipped by the active search on the next heartbeat.

---

### Priority 1 — Slack Reporting (sole owner)

**COMPLETED TASKS:** `bash scripts/task-manager.sh list --status done`
- Skip tasks where `reportedAt` is set
- For each NEW completion:
  - Read output: `cat ~/.openclaw/tasks/agent-logs/{TASK_ID}-output.log`
  - **Sub-tasks (LOCAL-*):** Brief report as part of parent story
  - **Stories (SENT-*):** Full detailed report:
    ```
    **SENT-XXX: [task title]** ✅
    - **Tempo:** [time from start to completion]
    - **O que fez:**
      - [changes, eval results, accuracy delta]
    ```
  - Set reportedAt immediately after sending

**FAILED TASKS:** `bash scripts/task-manager.sh list --status failed`
- Skip tasks where `reportedAt` is set
- Diagnose root cause, try to fix autonomously
- Report failure and set reportedAt

### Priority 2 — Timeout Detection + Kill

```bash
bash scripts/task-manager.sh list --status agent_running --json
```
For each running agent:
- Calculate age: `(now - startedEpoch) / 60`
- If age >= timeoutMin: kill, transition to timeout, log to Linear

### Priority 3 — Eval Monitoring + Callbacks

**EVAL_RUNNING tasks:** Check if `processPid` is still alive
- If dead → check metrics file → transition to `callback_pending`

**CALLBACK_PENDING tasks:** Spawn callback agent:
```bash
PARENT=$(bash scripts/task-manager.sh get <TASK_ID> | python3 -c "import json,sys; print(json.load(sys.stdin).get('parentTask',''))")
bash scripts/dispatcher.sh --parent "$PARENT" --title "Callback: review eval results" --role guardian-tuner --timeout 30 "Eval completed. Review metrics. Decide: iterate or done."
bash scripts/task-manager.sh transition <TASK_ID> done
```

### Priority 4 — Agreement Rate Improvement Loop

If no active tasks AND slots available:
1. Check latest eval results in `evals/.runs/content_moderation/`
2. If results exist and haven't been analyzed:
   - Spawn PM agent to analyze metrics and create improvement task:
   ```bash
   bash scripts/dispatcher.sh --title "Analyze agreement rate and create improvement plan" --role pm --timeout 20
   ```
3. The PM will trigger the full pipeline: PM → Analyst → Developer → Reviewer

### Priority 5 — Orphan Cleanup

Kill unregistered `claude` processes older than 5 minutes.

---

## If nothing to do
Reply `HEARTBEAT_OK` — nothing else.

---

## Architecture Reference

```
dispatcher.sh        — THE only way to spawn agents
  └→ exit-code watcher  — auto-transitions + Linear logging on agent death
task-manager.sh      — state CRUD (flock-protected)
kill-agent-tree.sh   — kill PID tree
guardrails.sh        — invariant checks
HEARTBEAT.md (you)   — monitoring, Slack, timeouts, callbacks, improvement loop
```
