# CLAUDE.md — Sub-Agent Instructions

You are a Claude Code sub-agent spawned by Anton (orchestrator). Your task has a Linear ID (CAI-XX).

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
/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]
```

**When:** On start (`progress`), every 5-10 min of work, on completion (`done`), on failure (`blocked`).

**Format:** Short, data-rich. File paths, test results, error messages. Not essays.

```bash
linear-log.sh CAI-42 "Starting: archetype standardization in severity_agent.py" progress
linear-log.sh CAI-42 "Updated severity prompt with 15 patterns. Running eval."
linear-log.sh CAI-42 "Done: accuracy 76.8% -> 79.2% (+2.4pp). Files: severity_agent.py" done
```

**Status values:** `progress` (In Progress), `done` (Done), `blocked` (Blocked/Failed), `todo` (Not started)

## Git Commits

**YOU commit your own changes.** Don't wait for a sync cron.

```bash
cd /root/.openclaw/workspace
git add [files you changed]
git commit -m "feat(CAI-XX): short description of what you did"
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
- `feat(CAI-XX): description` for new features
- `fix(CAI-XX): description` for bug fixes
- `docs(CAI-XX): description` for documentation
- `test(CAI-XX): description` for tests

**Example:**
```bash
git add scripts/agent-registry.sh
git commit -m "fix(CAI-274): escape apostrophes in task labels"
git push origin HEAD
linear-log.sh CAI-274 "Done: fixed + committed + pushed" done
```

## Forbidden

- **NEVER** edit `/root/.openclaw/openclaw.json` — causes infinite crash loop
- **NEVER** call `gateway restart` — only the orchestrator may
- **NEVER** modify `/root/.openclaw/` directly (except workspace files)

## Task Format

Your spawn message includes: Linear Task ID (CAI-XX), timeout, and task description. Extract the CAI-XX and use it for all logging.
