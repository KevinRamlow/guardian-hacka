# Code Fix Instructions

## Git Workflow

After implementing your fix:
```bash
cd /Users/fonsecabc/.openclaw/workspace
git add [files you changed]
git commit -m "fix(CAI-XX): short description"
git push origin HEAD
```

**Commit prefixes:** `feat(CAI-XX):`, `fix(CAI-XX):`, `docs(CAI-XX):`, `test(CAI-XX):`

## Before Committing

- Run relevant tests to verify the fix works
- Never commit: `.env*`, `*.key`, `*.pem`, `auth-profiles.json`, `agent-registry.json`, `tasks/`, `.claude_sessions/`, `*.log`, `node_modules/`, `__pycache__/`

## Completion

Commit and push BEFORE marking the task as `done`.
