# Workflow Orchestration System

A YAML-driven workflow engine for OpenClaw that orchestrates multi-step tasks with sub-agent checkpoints, decision points, and iterative loops.

## Overview

Workflows define a sequence of **checkpoints** — each is either a sub-agent task, shell hook, automatic gate, or human decision point. The engine walks through them, persisting state after each step. For iterative workflows (like Guardian experiments), it loops until a **completion promise** is met or the budget runs out.

```
┌─────────────┐
│ YAML Def    │──→ WorkflowRunner.run()
└─────────────┘         │
                        ▼
              ┌──────────────────┐
              │   next_action()  │◀──────────────┐
              └────────┬─────────┘               │
                       │                         │
            ┌──────────┼──────────┐              │
            ▼          ▼          ▼              │
       SpawnAgent  RunHook  RequestDecision      │
            │          │          │              │
            ▼          ▼          ▼              │
       [execute]   [execute]   [human]           │
            │          │          │              │
            └──────────┼──────────┘              │
                       ▼                         │
              ┌──────────────────┐               │
              │  feed_result()   │───────────────┘
              └──────────────────┘
                       │
                       ▼ (all checkpoints done)
              ┌──────────────────┐
              │ Check promise    │──→ loop or complete
              └──────────────────┘
```

## Quick Start

### Python API

```python
from workflows.engine import WorkflowRunner, SpawnAgent, RequestDecision, WorkflowComplete

runner = WorkflowRunner("guardian-experiment.yaml")
execution = runner.run(
    workflow_id="gua-1100",
    variables={"baseline_accuracy": 76.8, "target_improvement": 5.0}
)

while True:
    action = execution.next_action()
    if isinstance(action, WorkflowComplete):
        break
    # Handle action, then:
    execution.feed_result(action.checkpoint_name, success=True, output="...")
```

### CLI

```bash
python workflows/cli.py run guardian-experiment.yaml --id gua-1100 --var baseline_accuracy=76.8
python workflows/cli.py status gua-1100
python workflows/cli.py list
python workflows/cli.py cancel gua-1100
```

## Workflow YAML Format

```yaml
name: My Workflow
description: What this workflow does
version: "1.0"
loop: true  # false for single-pass

variables:
  my_var:
    type: string
    required: true
    description: "What it is"
  optional_var:
    type: float
    default: 42.0

budget:
  max_iterations: 5       # loop cap
  max_total_minutes: 120   # time cap
  max_agent_spawns: 25     # sub-agent cap

completion_promise:        # only for loop workflows
  description: "Human-readable goal"
  metric: improvement      # variable to check
  operator: ">="           # comparison
  target: 5.0              # threshold

hooks:
  on_start: "echo starting"
  on_complete: "echo done"
  on_fail: "echo failed"

checkpoints:
  - name: step-one
    kind: task             # task | hook | gate | decision
    # ... (see Checkpoint Types below)

metadata:
  team: guardian
  type: experiment
```

## Checkpoint Types

### task — Sub-Agent Work
```yaml
- name: implement
  kind: task
  description: "What this step does"
  agent_task: |
    Instructions for the sub-agent.
    Use {{variable}} for interpolation.
  agent_label: "my-agent"
  timeout_min: 20
  outputs: ["result_var"]
  on_failure: abort       # abort | skip | retry
  max_retries: 1
```

### hook — Shell Command
```yaml
- name: run-tests
  kind: hook
  hook_command: "cd /path && pytest --json-report"
  on_failure: retry
  max_retries: 2
```

### gate — Automatic Pass/Fail
```yaml
- name: regression-check
  kind: gate
  gate_expr: "current_accuracy >= baseline_accuracy - 2.0"
```

The expression is evaluated against workflow variables. If falsy, the checkpoint fails.

### decision — Human Review
```yaml
- name: review
  kind: decision
  decision_prompt: |
    ## Results
    Accuracy: {{current_accuracy}}%
    What do you want to do?
  decision_options:
    - continue
    - ship
    - abort
```

Decision checkpoints **pause** the workflow. The orchestrator presents the prompt, collects the decision, and feeds it back.

## Variable Interpolation

Use `{{variable_name}}` in any string field. Variables come from:
1. Initial `variables` passed to `run()`
2. Defaults from workflow `variables` schema
3. Updates from `feed_result(variables_update={...})`

## Completion Promise

For `loop: true` workflows, the promise is checked after each full iteration:

```yaml
completion_promise:
  description: "+5pp accuracy improvement"
  metric: improvement          # variable name
  operator: ">="               # >=, <=, >, <, ==
  target: 5.0                  # threshold value
```

Or use a complex expression:
```yaml
completion_promise:
  description: "Accuracy above 85% and F1 above 0.8"
  check_expr: "current_accuracy >= 85.0 and f1_score >= 0.8"
```

## Budget

Prevents runaway workflows:

| Field | Default | Description |
|-------|---------|-------------|
| `max_iterations` | 5 | Max loop iterations |
| `max_total_minutes` | 120 | Total wall-clock time |
| `max_agent_spawns` | 25 | Total sub-agents spawned |

When exceeded, workflow fails with `BudgetExceeded`.

## Failure Handling

Per-checkpoint `on_failure`:
- **abort** (default) — Workflow fails immediately
- **skip** — Mark checkpoint as skipped, continue
- **retry** — Retry up to `max_retries` times, then abort

## Conditional Checkpoints

Skip a checkpoint based on variables:
```yaml
- name: open-pr
  kind: task
  condition: "decision == 'approve'"
  # ...
```

## State Files

State is persisted after every checkpoint in two formats:

### Markdown (human-readable)
`~/.openclaw/workflows/<id>-state.md`

```markdown
# Workflow: Guardian Experiment
**ID:** gua-1100
**Status:** running
**Iteration:** 2
**Checkpoint:** analyze

## Variables
{...}

## Iteration 1
### ✅ implement (completed)
### ✅ run-pipeline (completed)
### ✅ analyze (completed)
### ✅ eval-gate (completed)
### ✅ decide (completed)
- Decision: continue
```

### JSON (machine-readable)
`~/.openclaw/workflows/<id>-state.json`

Same data in JSON format for programmatic access.

## Recovery

### Resume after crash
```python
runner = WorkflowRunner("guardian-experiment.yaml")
execution = runner.resume("gua-1100")
action = execution.next_action()  # picks up where it left off
```

### Cancel
```python
execution.cancel()  # sets status to cancelled
```

### Manual state edit
Edit the JSON state file directly, then resume. Useful for:
- Fixing incorrect variable values
- Skipping a stuck checkpoint (edit `current_checkpoint`)
- Resetting iteration count

## Hook System

Hooks run shell commands at lifecycle events:

| Hook | When |
|------|------|
| `on_start` | Workflow starts |
| `on_complete` | Workflow completes successfully |
| `on_fail` | Workflow fails |

Hooks support `{{variable}}` interpolation.

## Templates

Pre-built workflow patterns in `workflows/templates/`:

- **guardian-experiment.yaml** — Hypothesis → eval → refine iterative loop
- **code-change.yaml** — Implement → test → review single-pass
- **analysis.yaml** — Query → analyze → report single-pass

Copy and customize for your use case.

## Architecture

The engine is **generator-based**: it yields `Action` objects and the orchestrator (main agent) executes them. This keeps the engine pure (no I/O) and testable.

Action types:
- `SpawnAgent` — Create a sub-agent
- `RunHook` — Execute a shell command
- `RequestDecision` — Pause for human input
- `EvaluateGate` — Check a condition
- `WorkflowComplete` — Done
- `WorkflowError` — Error occurred
- `BudgetExceeded` — Limit hit
