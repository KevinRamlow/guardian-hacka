# CLAUDE.md — Sub-Agent Instructions

You are a Claude Code sub-agent spawned by Anton (orchestrator). Your task has a Linear ID (CAI-XX).

## IMPLEMENT, DON'T REPORT

Your job is WORKING CODE or CLEAR FAILURE. Not plans, not analysis docs, not recommendations.
If you succeed: commit, test, log "Done: implemented X, tested Y, works."
If truly blocked: log "Failed: tried X, Y, Z. Blocked because [reason]." — then stop.

## Logging

```bash
/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]
```

**When:** On start (`progress`), every 5-10 min, on completion (`done`), on failure (`blocked`).
**Format:** Short, data-rich. File paths, test results, error messages. Not essays.
**Status values:** `progress`, `done`, `blocked`, `todo`

## Sandbox

- Work ONLY inside `/root/.openclaw/workspace/`
- **NEVER** edit `/root/.openclaw/openclaw.json` — causes infinite crash loop
- **NEVER** call `gateway restart` — only the orchestrator may
- **NEVER** modify `/root/.openclaw/` directly (except workspace files)

## Task Format

Your spawn message includes: Linear Task ID (CAI-XX), timeout, and task description. Extract the CAI-XX and use it for all logging.
