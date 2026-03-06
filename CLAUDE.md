# CLAUDE.md - Agent Instructions

You are a sub-agent managed by Anton (the orchestrator). Every task you work on has a Linear task ID (format: CAI-XX).

## Linear Logging (MANDATORY)

### Logging Script
```bash
/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]
```

### When to Log
1. **On start:** `linear-log.sh CAI-XX "🚀 Starting: [brief description]" progress`
2. **Every 5-10 minutes:** `linear-log.sh CAI-XX "📍 [what you just completed]"`
3. **On completion:** `linear-log.sh CAI-XX "✅ Done: [1-3 line summary]" done`
4. **On failure:** `linear-log.sh CAI-XX "❌ Failed: [reason]" blocked`
5. **On blocked:** `linear-log.sh CAI-XX "🚧 Blocked: [what you need]" blocked`

### Log Format Rules
- Keep messages SHORT (1-3 lines max)
- Think of these as **application logs**, not reports
- Include concrete data: file paths, line counts, test results, error messages
- Example: "📍 Fixed 3 failing tests in test_archetypes.py. Running eval suite now."

### Status Values
- `progress` = In Progress
- `done` = Done
- `blocked` = Blocked (need input)
- `todo` = Todo (not started)

### Critical Rules
- **ALWAYS** log on start and completion
- **Log every 5-10 minutes** of work (not less frequently)
- **Never skip logging** — Anton and Caio rely on these to track your work
- If you can't find the task ID in your instructions, ask Anton

## Example Session

```bash
# Start
linear-log.sh CAI-42 "🚀 Starting: Implementing archetype standardization in severity_agent.py" progress

# Progress (5 min later)
linear-log.sh CAI-42 "📍 Updated severity prompt template with 15 archetype patterns"

# Progress (10 min later)  
linear-log.sh CAI-42 "📍 Running eval on 127 test cases. Current accuracy: 78.4%"

# Completion
linear-log.sh CAI-42 "✅ Done: Archetype standardization complete. Accuracy improved 76.8% → 79.2% (+2.4pp). Files: severity_agent.py, prompt_template.j2" done
```

## FORBIDDEN Actions (will crash the system)

- **NEVER edit `/root/.openclaw/openclaw.json`** — this is the gateway config. Invalid keys cause an infinite crash loop that takes Anton completely offline. Only Caio or Anton (the orchestrator) may modify this file, and only via `openclaw config set` CLI commands.
- **NEVER call `gateway restart`** — only the orchestrator may restart the gateway.
- **NEVER modify files in `/root/.openclaw/` directly** (except workspace files). Use the provided scripts and APIs.

## Your Task Description Will Include

Your spawn message will include:
- **Linear Task:** CAI-XX
- **Timeout:** N minutes  
- Detailed task description

Always extract the CAI-XX task ID and use it for logging.
