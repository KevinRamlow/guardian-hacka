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

### Step 1: Run Eval BEFORE Marking Done
```bash
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
bash /Users/fonsecabc/.openclaw/workspace/scripts/run-guardian-eval.sh \
  --config evals/content_moderation/eval.yaml \
  --dataset evals/content_moderation/guidelines_combined_dataset.jsonl \
  --workers 10
```

For targeted fixes, use subset datasets:
- CAPTIONS only: create subset with `grep CAPTIONS guidelines_combined_dataset.jsonl > /tmp/captions_only.jsonl`
- TIME_CONSTRAINTS only: similar grep approach
- Then run eval with `--dataset /tmp/subset.jsonl`

### Step 2: Measure Impact vs Baseline
```python
import json

# Load baseline
with open("/tmp/guardian-main-baseline-real.json") as f:
    baseline = json.load(f)
baseline_acc = baseline["accuracy"] * 100  # 76.86%

# Load your eval results
run_dir = "<latest-run-directory>"
with open(f"{run_dir}/metrics.json") as f:
    metrics = json.load(f)
new_acc = metrics["summary_statistics"]["mean_aggregate_score"] * 100

delta = new_acc - baseline_acc
print(f"Baseline: {baseline_acc:.2f}%")
print(f"New:      {new_acc:.2f}%")
print(f"Delta:    {delta:+.2f}pp")
```

### Step 3: Compare vs Expected Impact
- Task description says "Impact: +Xpp"
- Your measured delta should be within ±1pp of expected
- If delta is negative or way off → investigate before claiming done

### Step 4: Log Validation Results
```bash
linear-log.sh AUTO-XX "Validation: ${new_acc}% (${delta:+}pp vs baseline). Expected: +Xpp. VALIDATED ✓" done
```

### What if Validation Fails?

**If delta doesn't match expected:**
1. Check stderr logs for errors during eval
2. Review predictions.json for unexpected regressions
3. Try alternative implementation approach
4. OR mark as blocked: `linear-log.sh AUTO-XX "BLOCKED: validation failed. Expected +Xpp, got ${delta}pp. Investigated: [what you tried]" blocked`

**Rules:**
- ✅ Code committed + eval run + delta reported = complete task
- ❌ Code committed WITHOUT eval = incomplete task (will be re-queued)
- ❌ Eval run but delta way off = blocked task (needs investigation)

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
git add scripts/agent-registry.sh
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

## CRITICAL: Do NOT Poll Long-Running Processes

When you launch a long-running process (evals, tests, builds that take >2 minutes):

1. **Launch it in the background** using `nohup` or `&`
2. **Do NOT loop checking** `progress_meta.json`, `TaskOutput`, `sleep + check`, or `while [ ! -f ... ]`
3. **Do NOT use `callback`** repeatedly to check status
4. **Instead:** Launch the process, log "Eval started, run dir: X", then **exit**. The watchdog will detect completion.

**Why:** Polling wastes tokens. A 30-min eval checked every 30s = 60 polls × ~500 tokens each = 30K wasted tokens.

**Correct pattern for evals:**
```bash
# Launch eval in background
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
nohup python -m evals.run_eval --config evals/content_moderation/eval.yaml --workers 4 > /tmp/eval-output.log 2>&1 &
EVAL_PID=$!
echo "Eval PID=$EVAL_PID, output: /tmp/eval-output.log"

# Log and EXIT — do NOT wait
linear-log.sh AUTO-XX "Eval launched (PID=$EVAL_PID). Results will appear in evals/.runs/content_moderation/. Exiting." done
```

## Task Format

Your spawn message includes: Linear Task ID (AUTO-XX), timeout, and task description. Extract the AUTO-XX and use it for all logging.
