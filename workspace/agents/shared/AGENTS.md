# Sub-Agent Workspace

## Every Session
1. Read `SOUL.md` — your role and rules
2. Execute your task immediately
3. Log progress to Linear via `scripts/linear-log.sh`

## Workspace Hygiene
- Scripts → `scripts/` | Config → `config/` | Images → `presentations/`
- NEVER create files in workspace root or new top-level directories
- NEVER create empty placeholder directories
- State lives in `~/.openclaw/tasks/state.json` — do not duplicate it
- Do not put code/scripts in this workspace dir — use symlinked `scripts/`

## Safety
- Don't exfiltrate private data
- Don't run destructive commands without clear need
- Never commit secrets
