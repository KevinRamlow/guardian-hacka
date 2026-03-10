# Workflow Orchestration — Implementation Guide

## How to Use Workflows as the Orchestrator Agent

This guide explains how CaioBot (main agent) drives workflows using the engine API.

### 1. Starting a Guardian Experiment

When Caio says something like "run a guardian experiment to improve accuracy by 5pp":

```python
import sys
sys.path.insert(0, "/Users/fonsecabc/.openclaw/workspace")
from workflows.engine import (
    WorkflowRunner, SpawnAgent, RequestDecision, RunHook,
    EvaluateGate, WorkflowComplete, BudgetExceeded, WorkflowError
)

runner = WorkflowRunner("guardian-experiment.yaml")
execution = runner.run(
    workflow_id="gua-1100",
    variables={
        "baseline_accuracy": 76.8,
        "target_improvement": 5.0,
        "hypothesis": "Improve system prompt specificity for product claims"
    }
)
```

### 2. Driving the Execution Loop

The orchestrator drives each checkpoint by calling `next_action()`, executing the action, then feeding results back:

```python
action = execution.next_action()

# Handle based on type:
match action:
    case SpawnAgent(label=label, task=task, checkpoint_name=cp):
        # Use OpenClaw subagent spawning
        # spawn_subagent(label=label, task=task)
        # Wait for completion (push-based)
        # Then:
        execution.feed_result(
            cp,
            success=True,
            output="Agent completed: changed prompt template...",
            variables_update={"changes_summary": "Modified system prompt..."}
        )

    case RunHook(command=cmd, checkpoint_name=cp):
        # exec(command=cmd)
        # Capture output
        execution.feed_result(cp, success=True, output="...")

    case RequestDecision(prompt=prompt, options=options, checkpoint_name=cp):
        # Present to Caio in Slack/chat
        # Wait for response
        # decision = "continue"
        execution.feed_result(cp, success=True, decision="continue")

    case EvaluateGate(expression=expr, checkpoint_name=cp):
        result = eval(expr, {}, execution.state.variables)
        execution.feed_result(cp, success=bool(result))

    case WorkflowComplete(success=s, message=msg):
        # Done! Report to Caio
        pass

    case BudgetExceeded(limit=l, current=c, maximum=m):
        # Budget blown — report and stop
        pass
```

### 3. Practical Orchestrator Integration

In practice, the main agent doesn't run a Python loop — it drives the workflow step-by-step across conversation turns:

**Turn 1:** Start workflow, get first action (SpawnAgent for "implement")
→ Spawn sub-agent, save execution state

**Turn 2:** Sub-agent completes, feed result, get next action (RunHook for pipeline)
→ Run hook command

**Turn 3:** Hook completes, feed result, get next action (SpawnAgent for "analyze")
→ Spawn sub-agent

**Turn 4:** Analysis done, feed result, gate passes, get decision action
→ Present to Caio in chat

**Turn 5:** Caio says "continue"
→ Feed decision, start next iteration

This maps naturally to OpenClaw's async sub-agent model.

### 4. State Inspection

At any point, check state:

```python
state = WorkflowRunner.inspect("gua-1100")
print(f"Status: {state.status}")
print(f"Iteration: {state.current_iteration}")
print(f"Variables: {state.variables}")
```

Or read the markdown:
```bash
cat ~/.openclaw/workflows/gua-1100-state.md
```

### 5. Resuming After Interruption

If a session ends mid-workflow:

```python
runner = WorkflowRunner("guardian-experiment.yaml")
execution = runner.resume("gua-1100")
action = execution.next_action()  # picks up at last checkpoint
```

### 6. Variable Extraction from Sub-Agent Output

When a sub-agent completes a "task" checkpoint, the orchestrator should extract variables from the output. Convention:

Sub-agents should output structured results like:
```
## Results
- current_accuracy: 79.2
- improvement: 2.4
- last_analysis: "FP rate dropped on product claims..."
```

The orchestrator parses these and passes as `variables_update`:
```python
execution.feed_result(
    "analyze",
    success=True,
    output=agent_output,
    variables_update={
        "current_accuracy": 79.2,
        "improvement": 2.4,
        "last_analysis": "FP rate dropped on product claims..."
    }
)
```

### 7. Decision Point Handling

When the engine yields `RequestDecision`, the orchestrator should:

1. Format the prompt (already interpolated with variables)
2. Present to Caio via the current channel
3. Wait for response
4. Map response to one of `decision_options`
5. Feed back and handle special decisions:

```python
if decision == "abort":
    execution.cancel()
elif decision == "ship":
    execution.feed_result(cp, success=True, decision="ship")
    # Workflow will complete at end of iteration
elif decision == "pivot":
    # Update hypothesis variable before continuing
    execution.feed_result(
        cp, success=True, decision="pivot",
        variables_update={"hypothesis": "New hypothesis from Caio"}
    )
else:  # continue
    execution.feed_result(cp, success=True, decision="continue")
```

## File Layout

```
workflows/
├── __init__.py              # Package init
├── engine.py                # Core engine (WorkflowRunner, state management)
├── cli.py                   # CLI helper
├── README.md                # Full documentation
├── IMPLEMENTATION.md        # This file
├── guardian-experiment.yaml  # Guardian experiment workflow
└── templates/
    ├── code-change.yaml     # Implement → test → review
    └── analysis.yaml        # Query → analyze → report

skills/workflow/
└── SKILL.md                 # Skill definition for OpenClaw

.openclaw/workflows/         # Runtime state (created automatically)
├── <id>-state.md            # Human-readable state
└── <id>-state.json          # Machine-readable state
```

## Design Decisions

1. **Generator-based engine** — Engine yields actions, doesn't execute them. Keeps it testable and decoupled from OpenClaw internals.

2. **Dual state format** — Markdown for humans (read in chat), JSON for machines (load/resume).

3. **Variable interpolation** — `{{var}}` in any string field. Simple, predictable.

4. **Budget system** — Hard limits prevent runaway loops. Fail loudly when exceeded.

5. **Checkpoint-level failure policy** — Each step can abort, skip, or retry independently.

6. **No async runtime** — The orchestrator drives the loop at its own pace across conversation turns. No event loop or background threads needed.
