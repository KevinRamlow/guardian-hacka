# File Locations — Quick Reference

## Workspace Root
`~/.openclaw/workspace/`

## Core Scripts (4 + 1 brain)
`~/.openclaw/workspace/scripts/`
- `task-manager.sh` — State CRUD + transitions (flock-protected, single source of truth)
- `dispatcher.sh` — THE only spawn path: Linear + state + spawn + exit-code watcher
- `kill-agent-tree.sh` — Kill PID tree (utility)
- `guardrails.sh` — Invariant checks
- **HEARTBEAT.md** — The brain: Slack reporting, timeouts, orphans, callbacks

## Supporting Scripts
- `review-hook.sh` — Auto-fires adversarial reviewer after agent completion
- `infra-maintenance.sh` — consolidated infra tasks (15min launchd)
- `langfuse-query.sh` — Langfuse trace queries

## State
- Unified state: `~/.openclaw/tasks/state.json`
- Agent logs: `~/.openclaw/tasks/agent-logs/`
- Spawn tasks: `~/.openclaw/tasks/spawn-tasks/`

## Skills
`~/.openclaw/workspace/skills/`
- `guardian-evals/` — eval-related skills
- `guardian-ops/` — guardian operations
- `guardian-database/` — database queries
- `linear/` — Linear integration
- `task-manager/` — task management (linear-log.sh lives here)

## Config
`~/.openclaw/workspace/config/`
- `timeout-rules.json` — agent timeout rules
- `review-config.json` — review hook configuration

## Guardian Repo
`~/.openclaw/workspace/guardian-agents-api-real/`
- Entry: `main.py`
- App: `src/app.py`
- Wiring: `src/wire.py`
- Settings: `src/configs/settings.py`
- Models: `src/models/content_moderation.py`

## Eval Files
- Config: `guardian-agents-api-real/evals/content_moderation/eval.yaml`
- Combined dataset: `guardian-agents-api-real/evals/content_moderation/guidelines_combined_dataset.jsonl`
- Runner: `guardian-agents-api-real/evals/run_eval.py`
- Eval runs output: `guardian-agents-api-real/evals/.runs/content_moderation/run_*/`

## Secrets (NEVER commit)
- `~/.openclaw/.env` — All API keys and secrets (single source)
- `~/.openclaw/workspace/.env.guardian-eval` — eval environment vars
