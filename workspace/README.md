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
                    │      OpenClaw Sub-Agents            │
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
| `com.anton.infra` | infra-maintenance.sh | 15min | Langfuse query, state cleanup |
| Native heartbeat | HEARTBEAT.md | 5min | Auto-queue, health monitoring, backlog generation |

## Directory Structure

```
├── SOUL.md                 # Anton's identity + behavior rules
├── HEARTBEAT.md            # Heartbeat instructions (5min cycle)
├── MEMORY.md               # Long-term knowledge
├── AGENTS.md               # OpenClaw workspace config
├── TOOLS.md                # Local tool notes
├── USER.md                 # About the user (Caio)
├── IDENTITY.md             # OpenClaw identity template
│
├── scripts/                # All operational scripts (see below)
├── skills/                 # OpenClaw skills
├── knowledge/              # Agent knowledge base (codemaps, patterns, errors)
├── templates/              # Task + validation templates
├── config/                 # Auto-queue, timeout rules, review config
├── memory/                 # Daily memory files (YYYY-MM-DD.md)
├── docs/                   # Architecture docs
├── dashboard/              # Web dashboard (localhost:8765)
├── clawdbots/              # ClawdBots platform (Billy, Neuron agents)
├── agents/                 # Sub-agent role templates (developer, reviewer, etc.)
└── agents/                 # Sub-agent role templates (developer, reviewer, etc.)
```

## Scripts

### Core (5) — The Architecture

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
| `infra-maintenance.sh` | Consolidated 15min job: Langfuse query + state cleanup. |
| `langfuse-query.sh` | Query Langfuse traces (called by infra-maintenance). |

### Agent Lifecycle

| Script | Purpose |
|--------|---------|
| `agent-checkpoint.sh` | Save progress checkpoints (survives agent timeout). |
| `agent-logger.sh` | Log agent output to Linear. |
| `agent-stream-monitor.py` | Parse agent activity stream in real-time. |
| `agent-report.sh` | Generate completion reports for agents. |
| `agent-peek.sh` | Peek at agent activity (overview / detail / follow). |
| `kill-agent-tree.sh` | Kill agent + all child processes. |
| `diagnose-failure.sh` | Diagnose why an agent failed. |
| `validate-agent.sh` | Validate agent session state. |
| `interactive-checkpoint.sh` | Interactive mode checkpoint handling. |

### Queue & Dispatch

| Script | Purpose |
|--------|---------|
| `queue-control.sh` | Pause/resume auto-queue. |
| `classify-task.sh` | Auto-classify task type for timeout/role rules. |
| `dedup-check.sh` | Prevent duplicate agent spawns. |
| `dispatch-guard.sh` | Pre-dispatch validation guards. |
| `backlog-generator.sh` | Generate new tasks from analysis. |

> **Note:** Auto-queue logic is handled by the native heartbeat (HEARTBEAT.md), not a standalone script.

### Guardian Eval

| Script | Purpose |
|--------|---------|
| `run-guardian-eval.sh` | Wrapper for running Guardian evals (sources .env, activates venv). |
| `guardian-eval-status.sh` | Report eval progress/status. |
| `eval-analyze-breakdown.py` | Analyze eval results breakdown by category. |
| `preflight-check.sh` | Validate auth + config before eval run. |

### Setup & Utilities

| Script | Purpose |
|--------|---------|
| `setup-workspaces.sh` | Generate role workspaces from agent templates. |
| `review-hook.sh` | Auto-spawn adversarial reviews post-completion. |
| `alert-dedup.sh` | Prevent duplicate Slack alerts. |
| `link-logs-to-linear.sh` | Attach agent logs to Linear tasks. |
| `guardrails.sh` | Validate architecture invariants. |
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
| `~/.openclaw/.env` | All credentials (never committed) |
| `~/.openclaw/workspace/.env.guardian-eval` | Guardian eval env vars |
| `~/Library/LaunchAgents/com.anton.*.plist` | Launchd job definitions (2 active) |
