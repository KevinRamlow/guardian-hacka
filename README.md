# Anton — Autonomous AI Orchestrator

Anton is an autonomous AI agent that coordinates sub-agents to execute tasks, self-improve, and manage a continuous improvement loop for Guardian (content moderation AI).

## Architecture

```
                    ┌──────────────────────────────────┐
                    │        OpenClaw Gateway           │
                    │    (Slack + Heartbeat + Memory)    │
                    └────────────┬─────────────────────┘
                                 │
                    ┌────────────▼─────────────────────┐
                    │           Anton (Main Thread)      │
                    │   Coordinates, doesn't implement   │
                    └────────────┬─────────────────────┘
                                 │ spawns via dispatcher.sh
                    ┌────────────▼─────────────────────┐
                    │     Claude Code Sub-Agents         │
                    │  (5-60 min tasks, auto-tracked)    │
                    └──────────────────────────────────┘
```

### State Machine

Single source of truth: `~/.openclaw/tasks/state.json`

```
todo → agent_running → done
                     → failed
                     → eval_running → callback_pending → agent_running → ...
```

Each task carries `history[]` and `learnings[]` — callback agents get full context from previous cycles.

### Scheduling

| Job | Script | Interval | Purpose |
|-----|--------|----------|---------|
| `com.anton.supervisor` | supervisor.sh | 30s | PID checks, completions, callbacks, timeouts, orphans |
| `com.anton.infra` | infra-maintenance.sh | 15min | Linear sync, GCP tokens, Langfuse, state cleanup |
| `com.anton.gateway-respawn` | gateway-respawn.sh | 60s | Keep OpenClaw gateway alive |
| `com.anton.sync-replicants` | sync-replicants.sh | 4h | Bidirectional sync with Son of Anton VM |
| `com.anton.auto-loop` | anton-auto-loop.sh | 4h | Guardian accuracy improvement loop |
| `com.anton.meta-loop` | anton-meta-loop.sh | 24h | Self-improvement (templates, scripts, codemaps) |
| Native heartbeat | HEARTBEAT.md | 5min | Auto-queue, health monitoring, backlog generation |

## Directory Structure

```
├── SOUL.md                 # Anton's identity + behavior rules
├── HEARTBEAT.md            # Heartbeat instructions (5min cycle)
├── MEMORY.md               # Long-term knowledge
├── CLAUDE.md               # Sub-agent instructions (injected on spawn)
├── AGENTS.md               # OpenClaw workspace config
├── TOOLS.md                # Local tool notes
├── USER.md                 # About the user (Caio)
├── IDENTITY.md             # OpenClaw identity template
│
├── scripts/                # All operational scripts (see below)
├── skills/                 # OpenClaw skills (17 skill dirs)
├── knowledge/              # Agent knowledge base (codemaps, patterns, errors)
├── templates/              # Task templates + claude-md templates
├── config/                 # Auto-queue, timeout rules, sync configs
├── memory/                 # Daily memory files (YYYY-MM-DD.md)
├── docs/                   # Architecture docs, objectives, setup guides
├── workflows/              # YAML workflow definitions
├── dashboard/              # Web cockpit (localhost:8765)
├── clawdbots/              # ClawdBots platform (Billy, Neuron agents)
├── self-improvement/       # Self-improvement system (analyzers, experiments)
└── .shortcuts/             # Quick-access shell scripts
```

## Scripts

### Core (5) — The New Architecture

| Script | Purpose |
|--------|---------|
| `task-manager.sh` | State CRUD + transitions. ALL state reads/writes go through this. |
| `dispatcher.sh` | Create Linear task + register in state.json + spawn agent. |
| `supervisor.sh` | Unified 30s launchd: PID checks, completions, callbacks, timeouts, orphans. |
| `reporter.sh` | Report to Linear + Slack + dashboard. Peek at task status. |
| `spawn-agent.sh` | Low-level agent spawner. Called by dispatcher + supervisor. |

### Infrastructure

| Script | Purpose |
|--------|---------|
| `infra-maintenance.sh` | Consolidated 15min job: Linear sync + GCP tokens + Langfuse + cleanup. |
| `gateway-respawn.sh` | Auto-restart OpenClaw gateway if down (60s launchd). |
| `sync-replicants.sh` | Bidirectional sync with Son of Anton VM (4h launchd). |
| `linear-sync-v2.sh` | Sync Linear task statuses (called by infra-maintenance). |
| `langfuse-query.sh` | Query Langfuse traces (called by infra-maintenance). |
| `langfuse-scraper.py` | Scrape Langfuse data. |
| `health-check.sh` | System health check. |
| `notify-slack.sh` | Send Slack notifications to #replicants. |

### Agent Lifecycle

| Script | Purpose |
|--------|---------|
| `agent-checkpoint.sh` | Save progress checkpoints (survives agent timeout). |
| `agent-logger.sh` | Log agent output to Linear. |
| `agent-stream-monitor.py` | Parse agent activity stream in real-time. |
| `agent-report.sh` | Generate completion reports for agents. |
| `agent-peek.sh` | Peek at agent activity (overview / detail / follow). |
| `kill-agent-tree.sh` | Kill agent + all child processes. |
| `detect-agent-idle.sh` | Detect hung/idle agents. |
| `diagnose-failure.sh` | Diagnose why an agent failed. |
| `validate-agent.sh` | Validate agent session state. |

### Queue & Dispatch

| Script | Purpose |
|--------|---------|
| `auto-queue-v2.sh` | Auto-queue Linear Todo tasks for spawning. |
| `queue-control.sh` | Pause/resume auto-queue. |
| `classify-task.sh` | Auto-classify task type for timeout rules. |
| `dedup-check.sh` | Prevent duplicate agent spawns. |
| `backlog-generator.sh` | Generate new tasks from analysis. |

### Guardian Eval

| Script | Purpose |
|--------|---------|
| `run-guardian-eval.sh` | Wrapper for running Guardian evals (sources .env, activates venv). |
| `fast-eval.sh` | Quick 5-min eval on 10% of dataset. |
| `guardian-eval-status.sh` | Report eval progress/status. |
| `eval-analyze-breakdown.py` | Analyze eval results breakdown by category. |
| `preflight-check.sh` | Validate auth + config before eval run. |

### Loops

| Script | Purpose |
|--------|---------|
| `anton-auto-loop.sh` | Guardian improvement loop (4h): hypotheses → eval → iterate. |
| `anton-meta-loop.sh` | Self-improvement loop (24h): improve templates, scripts, codemaps. |

### Utilities

| Script | Purpose |
|--------|---------|
| `generate-codemap.sh` | Generate knowledge codemaps from repos. |
| `slack_upload_image.py` | Upload images to Slack. |

## Quick Commands

```bash
# Dispatch work
bash scripts/dispatcher.sh --title "Fix X" --desc "Details" --label Bug

# Check state
bash scripts/task-manager.sh list
bash scripts/task-manager.sh get AUTO-XX
bash scripts/task-manager.sh slots

# Monitor
bash scripts/reporter.sh peek
bash scripts/reporter.sh peek AUTO-XX follow

# Feedback loop
bash scripts/task-manager.sh add-history AUTO-XX '{"cycle":1,"accuracy":78.5}'
bash scripts/task-manager.sh add-learning AUTO-XX "what worked"
```

## Key Paths

| Path | Purpose |
|------|---------|
| `~/.openclaw/tasks/state.json` | Unified task state (single source of truth) |
| `~/.openclaw/tasks/agent-logs/` | Per-agent output, stderr, activity logs |
| `~/.openclaw/workspace/.env.secrets` | All credentials (never committed) |
| `~/.openclaw/workspace/.env.guardian-eval` | Guardian eval env vars |
| `~/Library/LaunchAgents/com.anton.*.plist` | Launchd job definitions |
