#!/usr/bin/env python3
"""
CLI helper for workflow orchestration.

Usage:
    python cli.py run <workflow.yaml> --id <id> [--var key=value ...]
    python cli.py status <workflow-id>
    python cli.py resume <workflow-id>
    python cli.py cancel <workflow-id>
    python cli.py list
    python cli.py inspect <workflow-id>
"""

import argparse
import json
import sys
from pathlib import Path

# Add workspace to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from workflows.engine import WorkflowRunner, WorkflowState, WorkflowStatus


def cmd_run(args):
    variables = {}
    for var in args.var or []:
        key, _, value = var.partition("=")
        # Try to parse as number
        try:
            value = float(value)
            if value == int(value):
                value = int(value)
        except ValueError:
            pass
        variables[key] = value

    runner = WorkflowRunner(args.workflow)
    execution = runner.run(workflow_id=args.id, variables=variables)
    state = execution.state
    print(f"✅ Workflow '{state.workflow_name}' started")
    print(f"   ID: {state.workflow_id}")
    print(f"   State: {state.state_path()}")
    print(f"   Variables: {json.dumps(state.variables, indent=2)}")
    print()
    print("Next: use the engine API or orchestrator to drive checkpoints.")
    print(f"  python -c \"from workflows.engine import WorkflowRunner; print(WorkflowRunner.inspect('{args.id}').status)\"")


def cmd_status(args):
    try:
        state = WorkflowState.load(args.workflow_id)
    except FileNotFoundError:
        print(f"❌ No workflow found: {args.workflow_id}")
        sys.exit(1)

    print(f"# {state.workflow_name} ({state.workflow_id})")
    print(f"Status: {state.status.value}")
    print(f"Iteration: {state.current_iteration}")
    print(f"Checkpoint: {state.current_checkpoint or '—'}")
    print(f"Agent spawns: {state.total_agent_spawns}")
    print(f"Updated: {state.updated_at}")
    if state.error:
        print(f"Error: {state.error}")
    print(f"\nVariables: {json.dumps(state.variables, indent=2)}")

    for it in state.iterations:
        print(f"\n--- Iteration {it.number} ---")
        for cr in it.checkpoint_results:
            icon = {"completed": "✅", "failed": "❌", "skipped": "⏭️"}.get(cr.status.value, "⏳")
            print(f"  {icon} {cr.name}: {cr.status.value}")
            if cr.decision:
                print(f"     Decision: {cr.decision}")


def cmd_cancel(args):
    try:
        state = WorkflowState.load(args.workflow_id)
    except FileNotFoundError:
        print(f"❌ No workflow found: {args.workflow_id}")
        sys.exit(1)

    state.status = WorkflowStatus.CANCELLED
    state.save()
    print(f"🛑 Workflow {args.workflow_id} cancelled")


def cmd_list(_args):
    active = WorkflowRunner.list_active()
    if not active:
        print("No active workflows.")
        return
    for wid in active:
        try:
            state = WorkflowState.load(wid)
            print(f"  {state.status.value:12s}  {wid:20s}  {state.workflow_name}  (iter {state.current_iteration})")
        except Exception as e:
            print(f"  {'error':12s}  {wid:20s}  {e}")


def cmd_inspect(args):
    try:
        state = WorkflowState.load(args.workflow_id)
    except FileNotFoundError:
        print(f"❌ No workflow found: {args.workflow_id}")
        sys.exit(1)
    # Print the markdown state
    print(state.state_path().read_text())


def main():
    parser = argparse.ArgumentParser(description="Workflow CLI")
    sub = parser.add_subparsers(dest="command")

    p_run = sub.add_parser("run", help="Start a workflow")
    p_run.add_argument("workflow", help="Workflow YAML file")
    p_run.add_argument("--id", required=True, help="Workflow ID")
    p_run.add_argument("--var", action="append", help="Variable (key=value)")

    p_status = sub.add_parser("status", help="Show workflow status")
    p_status.add_argument("workflow_id")

    p_cancel = sub.add_parser("cancel", help="Cancel a workflow")
    p_cancel.add_argument("workflow_id")

    p_list = sub.add_parser("list", help="List active workflows")

    p_inspect = sub.add_parser("inspect", help="Print full state markdown")
    p_inspect.add_argument("workflow_id")

    args = parser.parse_args()

    cmds = {
        "run": cmd_run,
        "status": cmd_status,
        "cancel": cmd_cancel,
        "list": cmd_list,
        "inspect": cmd_inspect,
    }
    fn = cmds.get(args.command)
    if not fn:
        parser.print_help()
        sys.exit(1)
    fn(args)


if __name__ == "__main__":
    main()
