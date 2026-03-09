# File Locations — Quick Reference

## Workspace Root
`~/.openclaw/workspace/`

## Core Scripts (5)
`~/.openclaw/workspace/scripts/`
- `task-manager.sh` — State CRUD + transitions (single source of truth)
- `dispatcher.sh` — Create Linear task + register state + spawn agent
- `supervisor.sh` — Unified launchd (30s): PID checks, completions, callbacks, timeouts
- `reporter.sh` — Report to Linear + Slack + dashboard
- `spawn-agent.sh` — Low-level agent spawner

## Supporting Scripts
- `run-guardian-eval.sh` — wrapper for eval runs
- `linear-sync-v2.sh` — Linear issue sync
- `infra-maintenance.sh` — consolidated infra tasks (15min launchd)

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
- `auto-queue.json` — auto-queue configuration
- `timeout-rules.json` — agent timeout rules
- `cockpit-state.json` — dashboard state

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
- `~/.openclaw/workspace/.env.secrets` — API keys and secrets
- `~/.openclaw/workspace/.env.guardian-eval` — eval environment vars
- `~/.openclaw/workspace/.gcp-credentials.json` — GCP service account key
