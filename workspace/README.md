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
                    └──────────┬───────────────────────┘
                               │ on death
                    ┌──────────▼───────────────────────┐
                    │     Exit-Code Watcher (bg proc)    │
                    │  Auto-transitions state + Linear   │
                    └──────────────────────────────────┘
```

### 4 Scripts + 1 Brain

| Component | Sole Responsibility |
|-----------|---------------------|
| `task-manager.sh` | State CRUD + transitions (flock-protected). ALL state goes through this. |
| `dispatcher.sh` | THE only spawn path: Linear task + state + spawn + exit-code watcher. |
| `kill-agent-tree.sh` | Kill PID tree (utility). |
| `guardrails.sh` | Invariant checks. |
| **HEARTBEAT.md** | The brain: Slack reporting, timeouts, orphans, auto-queue, callbacks. |

No supervisor. No reporter. No spawn-agent.sh. One owner per responsibility.

### State Machine

Single source of truth: `~/.openclaw/tasks/state.json`

```
todo → agent_running → done | failed | blocked
                     → eval_running → callback_pending → agent_running → ...
todo → eval_running (agentless eval via --eval flag)
```

Each task carries `history[]` and `learnings[]` — callback agents get full context from previous cycles.

### How Completions Work

1. `dispatcher.sh` spawns agent + launches exit-code watcher (background process)
2. When agent dies, watcher: checks output quality → transitions state → logs to Linear
3. Heartbeat (5min) reads state.json → reports to Slack → handles timeouts/orphans/callbacks

### Scheduling

| Job | Driver | Interval | Purpose |
|-----|--------|----------|---------|
| Native heartbeat | HEARTBEAT.md | 5min | Slack reporting, timeouts, orphans, auto-queue, callbacks |
| `com.anton.infra` | infra-maintenance.sh | 15min | Langfuse query, state cleanup |

## Sub-Agent Roles

| Role | Use For |
|------|---------|
| `developer` | Code implementation, bug fixes, feature work |
| `reviewer` | Post-completion adversarial code review |
| `architect` | System design, ADRs |
| `guardian-tuner` | Guardian accuracy optimization, eval loops |
| `debugger` | Root cause analysis, incident investigation |

Spawn: `bash scripts/dispatcher.sh --title "Fix X" --desc "Details" --role developer`

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
├── scripts/                # Operational scripts
│   ├── task-manager.sh     # State CRUD (flock-protected)
│   ├── dispatcher.sh       # THE only spawn path
│   ├── kill-agent-tree.sh  # Kill PID tree
│   └── guardrails.sh       # Invariant checks
├── skills/                 # OpenClaw skills
├── knowledge/              # Agent knowledge base (codemaps, patterns, errors)
├── config/                 # Auto-queue, timeout rules, review config
├── memory/                 # Daily memory files (YYYY-MM-DD.md)
├── docs/                   # Architecture docs
├── dashboard/              # Web dashboard (localhost:8765)
└── agents/                 # Sub-agent role templates (developer, reviewer, etc.)
```

## Quick Commands

```bash
# Dispatch agent work (Linear task created automatically)
bash scripts/dispatcher.sh --title "Fix X" --desc "Details" --role developer

# Dispatch agentless eval (no agent tokens wasted)
bash scripts/dispatcher.sh --eval --title "Eval: post fix" --parent AUTO-XX

# Dispatch for existing Linear task
bash scripts/dispatcher.sh --task AUTO-XX --role developer "prompt text"

# Check state
bash scripts/task-manager.sh list
bash scripts/task-manager.sh list --status agent_running
bash scripts/task-manager.sh get AUTO-XX
bash scripts/task-manager.sh slots

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

## Deployment

Runs on GKE via Docker. See `docs/gke-deploy-architecture.md` for details.

- `Dockerfile` — Multi-stage build, non-root user
- `docker-entrypoint.sh` — Validates env vars, sets up git, spawns workspaces, starts gateway
- `.github/workflows/deploy.yml` — CI/CD pipeline
