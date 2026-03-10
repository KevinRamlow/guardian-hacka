---
name: task-manager
description: Task management for Anton's orchestration workflow (integrates with Linear)
metadata: {"clawdis":{"emoji":"✅","requires":{"env":["LINEAR_API_KEY"]}}}
---

# Task Manager - Anton's Orchestration Tracking

Tracks sub-agents, workflows, experiments, and tasks across Anton's work.

## Purpose

This skill gives Caio (and Anton) constant visibility into:
- What sub-agents are running
- What experiments are in progress
- What workflows are active
- What tasks have been requested

All tracked in Linear for easy monitoring and control.

## Setup

Already configured! Linear API key is set in environment.

## Commands

### Track Current Work

```bash
# Show everything Anton is working on right now
{baseDir}/scripts/task-manager.sh status

# Show only active sub-agents
{baseDir}/scripts/task-manager.sh agents

# Show active workflows
{baseDir}/scripts/task-manager.sh workflows

# Show all open Anton tasks in Linear
{baseDir}/scripts/task-manager.sh tasks
```

### Create Tasks

```bash
# Track a new experiment
{baseDir}/scripts/task-manager.sh track-experiment "GUA-1100" "Archetype standardization" "+5pp improvement"

# Track a new sub-agent run
{baseDir}/scripts/task-manager.sh track-agent "<session-key>" "Task description"

# Create a general task
{baseDir}/scripts/task-manager.sh create "Task title" "Description" [priority]
```

### Update Status

```bash
# Update task status
{baseDir}/scripts/task-manager.sh update <TASK-ID> <todo|progress|done|blocked|homolog>

# Add progress note
{baseDir}/scripts/task-manager.sh note <TASK-ID> "Progress update text"

# Mark task complete with results
{baseDir}/scripts/task-manager.sh complete <TASK-ID> "Results summary"
```

### Daily Overview

```bash
# Morning standup - what's active, what's blocked, what finished yesterday
{baseDir}/scripts/task-manager.sh standup

# End of day summary
{baseDir}/scripts/task-manager.sh eod
```

## Integration with Workflows

When Anton spawns a sub-agent with a workflow:
1. Auto-creates Linear task (title = workflow goal)
2. Tracks completion promise and budget
3. Updates status at each checkpoint
4. Auto-completes when workflow finishes

## Labels

Tasks are tagged with:
- `anton-orchestrator` — All Anton's work
- `sub-agent` — Spawned sub-agent tasks
- `workflow` — Workflow-driven tasks
- `experiment` — Research/experiment tasks
- `guardian` — Guardian-related work
- `clawdbots` — ClawdBots platform work

## Tracking Location

**Anton's orchestration work is tracked in LINEAR (caio-tests workspace).**

- **Workspace:** caio-tests (team: CAI)
- **API Key:** $LINEAR_API_KEY from `$OPENCLAW_HOME/.env`
- **Linear URL:** https://linear.app/caio-tests
- **Local backup:** `${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/active.md` (synced from Linear)

This keeps Anton's meta-work separate from Brandlovers product tasks (GUA workspace).

**Linear Usage:**
- **caio-tests (CAI)** → ✅ Full read/write for Anton's orchestration
- **Brandlovers (GUA)** → ✅ Read for context, ❌ Write unless explicitly requested

## Task Statuses

| Status | When to Use |
|--------|-------------|
| **Backlog** | Task created but not started yet |
| **Todo** | Ready to start, queued for work |
| **In Progress** | Sub-agent actively working |
| **Blocked** | Needs Caio's input/decision before continuing |
| **Homolog** | Caio is testing the implementation |
| **Done** | Completed successfully |
| **Canceled** | Abandoned or no longer needed |

## Examples

### Track Billy Improvements Task
```bash
./skills/task-manager/scripts/task-manager.sh track-experiment \
  "billy-improvements" \
  "Research + implement top 3 skills for Billy" \
  "3 new skills working"
```

### Check What's Running
```bash
./skills/task-manager/scripts/task-manager.sh status
# Output:
# Active Tasks (3):
# - GUA-1100: Archetype standardization (In Progress, sub-agent running)
# - Billy improvements: Research phase (In Progress, sub-agent running)
# - Memory system: 10-min updates (Done)
```

### End of Day Summary
```bash
./skills/task-manager/scripts/task-manager.sh eod
# Completed today: 2 tasks
# Still in progress: 2 tasks
# Blocked: 0 tasks
```

## Auto-Tracking

Anton automatically creates tasks when:
- Spawning sub-agents (via `dispatcher.sh` → `spawn-agent.sh`)
- Starting workflows (via workflow engine)
- Caio explicitly asks for something

Tasks auto-update when:
- Sub-agent reports completion
- Workflow reaches checkpoint
- Anton manually updates progress

## State Files

Task state is stored in:
- **Linear** — source of truth for task status
- `.openclaw/tasks/state.json` — Local cache of active tasks
- `memory/YYYY-MM-DD.md` — Daily log of task progress

## Future Enhancements

- Slack notifications for task status changes
- Auto-create tasks from Slack messages ("Anton, can you...")
- Weekly summary reports
- Task time tracking (how long each sub-agent runs)
- Budget alerts (task approaching time/cost limits)

## Agent Monitoring Tools (Phase 2 Infrastructure)

### Agent Dashboard
Quick status view of all running agents:

```bash
{baseDir}/scripts/agent-dashboard.sh
```

Shows:
- Linear task ID
- Agent label
- Runtime
- Last Linear log time
- Status indicator (🟢 normal, 🟡 >15min, 🔴 >25min)

### Agent Watchdog
Automated stuck agent detection (runs every 10 min via cron):

```bash
{baseDir}/scripts/agent-watchdog.sh
```

Writes alerts to: `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/tasks/agent-alerts.json`

Anton picks up alerts during heartbeat sweeps.


