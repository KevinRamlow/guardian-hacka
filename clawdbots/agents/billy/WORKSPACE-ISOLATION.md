# Billy Workspace Isolation

**Billy's Root:** `/root/.openclaw/workspace/clawdbots/agents/billy/`
**Anton's Root:** `/root/.openclaw/workspace/`

## Isolation Guarantees

### Configuration
- **openclaw.json:** Billy has his own config with Slack allowlist (only Caio U04PHF0L65P)
- **.env:** Separate environment file with Billy's credentials
- **workspace/:** Billy's isolated workspace (skills, memory, SOUL.md, TOOLS.md)

### Skills
- Billy has his own copies of skills in `workspace/skills/`
- Skills reference relative paths (e.g., `{baseDir}/scripts/`) which resolve to Billy's workspace
- Linear skill added for task logging (shared CAI workspace, isolated execution)

### Memory & State
- Billy's memory files: `workspace/memory/`
- Billy's daily logs: `workspace/memory/YYYY-MM-DD.md`
- NO access to Anton's `MEMORY.md` or daily notes

### Slack Access Control
- **allowedUsers:** `["U04PHF0L65P"]` (Caio only)
- **allowedChannels:** `[]` (DMs only for now)
- Billy will ignore messages from anyone except Caio

## Testing Isolation

```bash
# Verify Billy's config
cat /root/.openclaw/workspace/clawdbots/agents/billy/openclaw.json | jq '.channels.slack.allowedUsers'
# Expected: ["U04PHF0L65P"]

# Verify workspace separation
ls /root/.openclaw/workspace/clawdbots/agents/billy/workspace/
# Expected: AGENTS.md, SOUL.md, TOOLS.md, skills/, memory/

# Verify Linear integration
cd /root/.openclaw/workspace/clawdbots/agents/billy
source .env && echo $LINEAR_DEFAULT_TEAM
# Expected: CAI
```

## Access Levels

| Resource | Anton | Billy |
|----------|-------|-------|
| `/root/.openclaw/workspace/` | ✅ Full | ❌ No access |
| `/root/.openclaw/workspace/clawdbots/agents/billy/` | ✅ Read (monitoring) | ✅ Full |
| Linear CAI workspace | ✅ Read/Write | ✅ Read/Write (comments only) |
| Slack (Caio DMs) | ✅ | ✅ |
| Slack (other users) | ✅ | ❌ Blocked |
| MySQL (db-maestro-prod) | ✅ Read | ✅ Read |
| BigQuery | ✅ Read | ✅ Read |

## Linear Task Logging

Both Billy and Anton log to the same Linear workspace (caio-tests / CAI team) for coordination:
- Anton: Orchestration tasks, experiments, workflows
- Billy: Non-tech team support tasks, data queries, presentations

This allows Caio to see all work in one place while keeping agent workspaces isolated.
