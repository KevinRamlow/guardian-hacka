# File Locations — Quick Reference

## Workspace Root
`~/.openclaw/workspace/`

## Scripts
`~/.openclaw/workspace/scripts/`
- `run-guardian-eval.sh` — wrapper for eval runs
- `spawn-agent.sh` — spawns sub-agents
- `agent-registry.sh` — manages agent registry
- `agent-status.sh` — checks agent status
- `health-check.sh` — system health check
- `deploy-v2.sh` — deployment script
- `linear-sync-v2.sh` — Linear issue sync

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

## Agent System
- Agent logs: `~/.openclaw/tasks/agent-logs/`
- Agent registry: `~/.openclaw/tasks/agent-registry.json`
- Spawn tasks: `~/.openclaw/tasks/spawn-tasks/`

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
- Sample dataset: `guardian-agents-api-real/evals/content_moderation/general_guidelines_sample_dataset.jsonl`
- Runner: `guardian-agents-api-real/evals/run_eval.py`
- Eval runs output: `guardian-agents-api-real/evals/.runs/content_moderation/run_*/`

## Secrets (NEVER commit)
- `~/.openclaw/workspace/.env.secrets` — API keys and secrets
- `~/.openclaw/workspace/.env.guardian-eval` — eval environment vars (GOOGLE_CLOUD_PROJECT etc)
- `~/.openclaw/workspace/.gcp-credentials.json` — GCP service account key
