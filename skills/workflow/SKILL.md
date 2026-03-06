# Workflow Orchestration Skill

Run multi-step workflows with sub-agent checkpoints, decision points, and iterative loops.

## When to Use

- Multi-step tasks that need orchestration (implement → test → review)
- Iterative improvement loops (Guardian experiments)
- Any task that benefits from state persistence and resumability

## Quick Start

### Start a workflow
```
workflow run guardian-experiment.yaml --id gua-1100 --var baseline_accuracy=76.8 --var target_improvement=5.0
```

### Check status
```
workflow status gua-1100
```

### Resume a paused workflow
```
workflow resume gua-1100
```

### List active workflows
```
workflow list
```

## How It Works

1. **Parse** — Engine loads workflow YAML definition
2. **Iterate** — Engine walks through checkpoints sequentially
3. **Execute** — For each checkpoint:
   - `task` → Spawn a sub-agent with interpolated instructions
   - `hook` → Run a shell command
   - `gate` → Evaluate a pass/fail expression
   - `decision` → Pause and ask orchestrator (you) what to do
4. **Loop** — If `loop: true`, repeat until completion promise is met or budget exhausted
5. **Persist** — State saved after every checkpoint to `.openclaw/workflows/<id>-state.md`

## Using from Python (Orchestrator Agent)

```python
from workflows.engine import WorkflowRunner, SpawnAgent, RequestDecision, RunHook, EvaluateGate, WorkflowComplete

runner = WorkflowRunner("guardian-experiment.yaml")
execution = runner.run(
    workflow_id="gua-1100",
    variables={"baseline_accuracy": 76.8, "target_improvement": 5.0}
)

# Drive the loop
while True:
    action = execution.next_action()

    if isinstance(action, WorkflowComplete):
        print(f"Done: {action.message}")
        break

    elif isinstance(action, SpawnAgent):
        # Spawn sub-agent, wait for result
        result = spawn_and_wait(action.label, action.task)
        execution.feed_result(
            action.checkpoint_name,
            success=True,
            output=result,
            variables_update=parse_variables(result),
        )

    elif isinstance(action, RequestDecision):
        # Ask orchestrator
        decision = ask_human(action.prompt, action.options)
        execution.feed_result(
            action.checkpoint_name,
            success=True,
            decision=decision,
        )

    elif isinstance(action, RunHook):
        # Execute shell command
        output = run_shell(action.command)
        execution.feed_result(
            action.checkpoint_name,
            success=True,
            output=output,
        )

    elif isinstance(action, EvaluateGate):
        passed = eval(action.expression, {}, execution.state.variables)
        execution.feed_result(
            action.checkpoint_name,
            success=passed,
            error="" if passed else f"Gate failed: {action.expression}",
        )
```

## Using from CLI (Helper Script)

```bash
# Start
python /root/.openclaw/workspace/workflows/cli.py run guardian-experiment.yaml \
  --id gua-1100 \
  --var baseline_accuracy=76.8 \
  --var target_improvement=5.0

# Status
python /root/.openclaw/workspace/workflows/cli.py status gua-1100

# Resume
python /root/.openclaw/workspace/workflows/cli.py resume gua-1100

# Cancel
python /root/.openclaw/workspace/workflows/cli.py cancel gua-1100

# List
python /root/.openclaw/workspace/workflows/cli.py list
```

## Available Templates

| Template | File | Pattern |
|----------|------|---------|
| Guardian Experiment | `guardian-experiment.yaml` | hypothesis → eval → refine loop |
| Code Change | `templates/code-change.yaml` | implement → test → review |
| Analysis | `templates/analysis.yaml` | query → analyze → report |

## Creating a New Workflow

1. Copy a template from `workflows/templates/`
2. Define variables, checkpoints, and budget
3. Set `loop: true` if iterative, with a `completion_promise`
4. Place in `workflows/` directory
5. Run with `workflow run <file> --id <id> --var key=value`

See `/root/.openclaw/workspace/workflows/README.md` for full documentation.

## Checkpoint Kinds

- **task** — Sub-agent work. Define `agent_task` with `{{variable}}` interpolation.
- **hook** — Shell command. Define `hook_command`.
- **gate** — Auto pass/fail. Define `gate_expr` (Python expression against variables).
- **decision** — Human review. Define `decision_prompt` and `decision_options`.

## Failure Handling

Per-checkpoint `on_failure`:
- `abort` (default) — Stop the workflow
- `skip` — Skip and continue
- `retry` — Retry up to `max_retries` times

## State Files

State is persisted in two formats:
- `.openclaw/workflows/<id>-state.md` — Human-readable markdown
- `.openclaw/workflows/<id>-state.json` — Machine-readable JSON

Read the markdown for quick status; use JSON for programmatic access.
