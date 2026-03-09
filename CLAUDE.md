# CLAUDE.md — Sub-Agent Instructions

You are a Claude Code sub-agent spawned by Anton (orchestrator). Your task has a Linear ID (AUTO-XX).

## CRITICAL: IMPLEMENT, DON'T REPORT

**Your job:** IMPLEMENT the solution. Write code, fix bugs, create tools.

**NOT your job:** Write reports, plans, or analysis documents.

**If you succeed:**
- Commit code changes
- Test it works
- Log "Done: implemented X, tested Y, works"

**If you fail:**
- Try alternatives
- If truly blocked: log "Failed: tried X, Y, Z. Blocked because [specific reason]. Did NOT implement."
- NEVER write a markdown report saying "here's what SHOULD be done"

**Examples:**

✅ GOOD:
- "Done: fixed apostrophe escaping in spawn-agent.sh. Tested with 5 edge cases, all pass. Committed."
- "Failed: tried MySQL query, got permission denied. Tried Cloud SQL Proxy, not running. Cannot complete without DB access."

❌ BAD:
- "Analysis complete. Recommendations: 1) Fix X, 2) Update Y, 3) Test Z. See report.md"
- "Created plan.md with 5 proposed solutions. Ready for review."

**Rule:** Every task ends with WORKING CODE or CLEAR FAILURE. No plans, no analysis-only docs.

## Logging

```bash
/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh AUTO-XX "message" [status]
```

**When:** On start (`progress`), every 5-10 min of work, on completion (`done`), on failure (`blocked`).

**Format:** Short, data-rich. File paths, test results, error messages. Not essays.

```bash
linear-log.sh AUTO-42 "Starting: archetype standardization in severity_agent.py" progress
linear-log.sh AUTO-42 "Updated severity prompt with 15 patterns. Running eval."
linear-log.sh AUTO-42 "Done: accuracy 76.8% -> 79.2% (+2.4pp). Files: severity_agent.py" done
```

**Status values:** `progress` (In Progress), `done` (Done), `blocked` (Blocked/Failed), `todo` (Not started)


## Validation — MANDATORY for Guardian Changes

**If your task changes Guardian code** (prompts, agents, archetypes, severity logic):

### Step 1: Make Your Code Changes and Commit
```bash
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real
git add [files you changed]
git commit -m "feat(AUTO-XX): description of changes"
```

### Step 2: Launch Eval and Register with Process Manager
```bash
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
bash /Users/fonsecabc/.openclaw/workspace/scripts/run-guardian-eval.sh \
  --config evals/content_moderation/eval.yaml \
  --dataset evals/content_moderation/guidelines_combined_dataset.jsonl \
  --workers 10

# Get the eval PID
EVAL_PID=$(cat /tmp/guardian-eval.pid)

# Register with process manager — THIS IS THE KEY STEP
bash /Users/fonsecabc/.openclaw/workspace/scripts/register-eval-process.sh \
  --task AUTO-XX \
  --pid $EVAL_PID \
  --context "Changed [describe what you changed]. Expected impact: [+Xpp]. Files: [list files]. Commit: [hash]"
```

### Step 3: Log and EXIT
```bash
linear-log.sh AUTO-XX "Code committed. Eval launched (PID=$EVAL_PID). Registered with process manager. Exiting — callback agent will process results." progress
exit 0
```

**What happens next (automatically):**
1. Process-completion-checker runs every 30s, detects eval finish
2. Reads metrics.json, computes accuracy delta vs baseline
3. Spawns a fresh callback agent with your task ID + full results
4. Callback agent reviews results and takes next action (mark done, refine, or block)

For targeted fixes, use subset datasets:
- CAPTIONS only: `grep CAPTIONS guidelines_combined_dataset.jsonl > /tmp/captions_only.jsonl`
- Then run eval with `--dataset /tmp/subset.jsonl`

**Rules:**
- ✅ Code committed + eval registered with process manager = you're done, exit cleanly
- ❌ Code committed WITHOUT eval = incomplete task (will be re-queued)
- ❌ Polling eval in a loop = FORBIDDEN (wastes tokens, hits timeouts)

**Why this matters:** Shipping unvalidated Guardian changes breaks production accuracy. Every change MUST be measured.

## Git Commits

**YOU commit your own changes.** Don't wait for a sync cron.

```bash
cd /Users/fonsecabc/.openclaw/workspace
git add [files you changed]
git commit -m "feat(AUTO-XX): short description of what you did"
git push origin HEAD
```

**When to commit:**
- After completing a bug fix (commit the fix)
- After implementing a feature (commit the code)
- After creating analysis/docs (commit the files)
- Before marking task as `done`

**What to exclude:** Don't commit secrets, temp files, logs, or stats
- `auth-profiles.json`, `.env*`, `*.key`, `*.pem`
- `agent-registry.json`, `tasks/`, `.claude_sessions/`
- `*.log`, `node_modules/`, `__pycache__/`

**Commit message format:**
- `feat(AUTO-XX): description` for new features
- `fix(AUTO-XX): description` for bug fixes
- `docs(AUTO-XX): description` for documentation
- `test(AUTO-XX): description` for tests

**Example:**
```bash
git add scripts/task-manager.sh
git commit -m "fix(AUTO-274): escape apostrophes in task labels"
git push origin HEAD
linear-log.sh AUTO-274 "Done: fixed + committed + pushed" done
```

## Forbidden

- **NEVER** edit `/Users/fonsecabc/.openclaw/openclaw.json` — causes infinite crash loop
- **NEVER** call `gateway restart` — only the orchestrator may
- **NEVER** modify `/Users/fonsecabc/.openclaw/` directly (except workspace files)

## Database Access

You have MySQL MCP access to `db-maestro-prod` (the Guardian/CreatorAds platform database).
Use `mcp__mcp_server_mysql__run_select_query` for direct SQL queries. Load it via ToolSearch first.
Key tables: `proofread_medias`, `proofread_guidelines`, `media_content`, `campaign`, `actions`.

## GCP Project IDs

- Production: `brandlovers-prod` (NOT `brandlovrs-production`)
- Homolog: `brandlovrs-homolog` (note: missing 'e' is correct in GCP)

## Timeout Warning & Checkpoints

**Save progress checkpoints** periodically so work survives if you're killed:

```bash
bash /Users/fonsecabc/.openclaw/workspace/scripts/agent-checkpoint.sh \
  AUTO-XX "step_name" "What was done so far and what remains"
```

**When to checkpoint:**
- After each major phase of work (e.g., after analysis, after implementing first file, after launching eval)
- Before any long-running background operation (eval, build, test)

**Check for timeout warning** — the watchdog writes a file at 80% of your timeout:

```bash
WARN_FILE="/Users/fonsecabc/.openclaw/tasks/timeout-warnings/AUTO-XX.warn"
if [ -f "$WARN_FILE" ]; then
  # Save final checkpoint and exit gracefully
  bash /Users/fonsecabc/.openclaw/workspace/scripts/agent-checkpoint.sh \
    AUTO-XX "interrupted_at_80pct" "Summarize what was done and what remains"
  linear-log.sh AUTO-XX "Timeout warning received. Checkpoint saved. Exiting for resume." progress
  exit 0
fi
```

**Why this matters:** When a task times out with no output (like EVAL-001), work is lost. Checkpoints let the next agent resume instead of restarting.

## CRITICAL: Long-Running Processes — Use the Task Manager

**NEVER poll long-running processes.** Use the Task Manager instead.

When you need to run something that takes >2 minutes (evals, builds, pipelines, tests):

### Pattern: Launch → Transition to eval_running → Exit → Callback
```bash
# 1. Launch the process in background
nohup <your-command> > /tmp/my-process.log 2>&1 &
PROCESS_PID=$!

# 2. Transition task to eval_running (supervisor will handle completion + callback)
bash /Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh transition AUTO-XX eval_running \
  --process-pid $PROCESS_PID \
  --process-type eval \
  --result-path /tmp/my-process.log \
  --metrics-path /path/to/expected/metrics.json \
  --context "Description of what was done and what the callback agent should do with results"

# 3. Log and EXIT immediately
linear-log.sh AUTO-XX "Process launched (PID=$PROCESS_PID). Registered in state. Exiting." progress
exit 0
```

**For evals specifically, use the convenience wrapper:**
```bash
bash /Users/fonsecabc/.openclaw/workspace/scripts/register-eval-process.sh \
  --task AUTO-XX \
  --pid $EVAL_PID \
  --context "Changed severity_agent.py to fix CAPTIONS patterns. Expected +2pp."
```

**After your callback processes results, update the feedback loop:**
```bash
# Record what happened this cycle
bash scripts/task-manager.sh add-history AUTO-XX '{"cycle":1,"accuracy":78.5,"delta":"+2.5pp","action":"what you did"}'
# Record what you learned
bash scripts/task-manager.sh add-learning AUTO-XX "what worked or didn't work"
```

**What you MUST NOT do:**
- `while [ ! -f metrics.json ]; do sleep 30; done` — FORBIDDEN
- `TaskOutput` polling — FORBIDDEN
- `sleep 60 && check` loops — FORBIDDEN
- Staying alive waiting for a process — FORBIDDEN

**Why:** Polling wastes tokens and hits timeouts. The supervisor checks every 30s via launchd (zero token cost) and spawns a fresh callback agent with full results + history when done.

**Check task status:** `bash scripts/task-manager.sh list`

## Task Format

Your spawn message includes: Linear Task ID (AUTO-XX), timeout, and task description. Extract the AUTO-XX and use it for all logging.
