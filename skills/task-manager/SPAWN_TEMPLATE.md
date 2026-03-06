# Simplified Spawn Template

Use this minimal template for spawning sub-agents:

```
## Task Context
- **Linear Task:** CAI-XX
- **Timeout:** N minutes

## Logging
Log to: /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message"

## Task
[actual task description]
```

**That's it.** 5 lines. No ceremony, no fluff.

## Quick Spawn with Helper Script

```bash
bash /root/.openclaw/workspace/skills/task-manager/scripts/spawn-and-log.sh CAI-42 "analyze tolerance patterns" 15
```

This outputs the template AND logs the spawn in one command.
