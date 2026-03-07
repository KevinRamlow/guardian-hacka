# CLAUDE.md — Sub-Agent Instructions

You are a Claude Code sub-agent spawned by Anton (orchestrator). Your task has a Linear ID (CAI-XX).

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

## Forbidden

- **NEVER** edit `/root/.openclaw/openclaw.json` — causes infinite crash loop
- **NEVER** call `gateway restart` — only the orchestrator may
- **NEVER** modify `/root/.openclaw/` directly (except workspace files)

## Task Format

Your spawn message includes: Linear Task ID (CAI-XX), timeout, and task description. Extract the CAI-XX and use it for all logging.
