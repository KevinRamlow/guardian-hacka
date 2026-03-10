"""
Workflow Orchestration Engine for OpenClaw.

Parses workflow YAML definitions, manages state, spawns sub-agents for
checkpoints, and drives iterative loops with orchestrator decision points.

Usage:
    from workflows.engine import WorkflowRunner

    runner = WorkflowRunner("guardian-experiment.yaml")
    runner.run(
        workflow_id="gua-1100",
        variables={"baseline_accuracy": 76.8, "target_improvement": 5.0}
    )
"""

from __future__ import annotations

import copy
import datetime as _dt
import json
import os
import re
import textwrap
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

import yaml

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

WORKSPACE = Path(os.environ.get("OPENCLAW_WORKSPACE", "/Users/fonsecabc/.openclaw/workspace"))
WORKFLOWS_DIR = WORKSPACE / "workflows"
STATE_DIR = WORKSPACE / ".openclaw" / "workflows"
TEMPLATES_DIR = WORKFLOWS_DIR / "templates"

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class CheckpointKind(str, Enum):
    TASK = "task"  # sub-agent work
    DECISION = "decision"  # orchestrator reviews & decides
    HOOK = "hook"  # run a shell/python hook
    GATE = "gate"  # automatic pass/fail gate (expression)


class WorkflowStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    PAUSED = "paused"  # waiting at decision point
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class CheckpointStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class Checkpoint:
    """A single step in a workflow."""

    name: str
    kind: CheckpointKind
    description: str = ""
    agent_task: str = ""  # prompt/instructions for sub-agent (kind=task)
    agent_label: str = ""  # sub-agent label
    timeout_min: int = 20  # max minutes for sub-agent
    hook_command: str = ""  # shell command (kind=hook)
    gate_expr: str = ""  # Python expression for gate evaluation
    decision_prompt: str = ""  # what to ask orchestrator (kind=decision)
    decision_options: List[str] = field(default_factory=list)
    outputs: List[str] = field(default_factory=list)  # variable names this produces
    on_failure: str = "abort"  # abort | skip | retry
    max_retries: int = 1
    condition: str = ""  # skip if expression evaluates falsy

    @classmethod
    def from_dict(cls, d: dict) -> "Checkpoint":
        kind = CheckpointKind(d.get("kind", "task"))
        return cls(
            name=d["name"],
            kind=kind,
            description=d.get("description", ""),
            agent_task=d.get("agent_task", ""),
            agent_label=d.get("agent_label", d["name"]),
            timeout_min=d.get("timeout_min", 20),
            hook_command=d.get("hook_command", ""),
            gate_expr=d.get("gate_expr", ""),
            decision_prompt=d.get("decision_prompt", ""),
            decision_options=d.get("decision_options", []),
            outputs=d.get("outputs", []),
            on_failure=d.get("on_failure", "abort"),
            max_retries=d.get("max_retries", 1),
            condition=d.get("condition", ""),
        )


@dataclass
class CompletionPromise:
    """Ralph-loop style completion criteria."""

    description: str
    metric: str  # variable name to check
    operator: str  # >=, <=, ==, >, <
    target: float
    check_expr: str = ""  # optional complex expression (overrides metric/op/target)

    @classmethod
    def from_dict(cls, d: dict) -> "CompletionPromise":
        return cls(
            description=d.get("description", ""),
            metric=d.get("metric", ""),
            operator=d.get("operator", ">="),
            target=d.get("target", 0),
            check_expr=d.get("check_expr", ""),
        )

    def evaluate(self, variables: Dict[str, Any]) -> bool:
        if self.check_expr:
            return bool(eval(self.check_expr, {"__builtins__": {}}, variables))
        val = variables.get(self.metric)
        if val is None:
            return False
        ops = {
            ">=": lambda a, b: a >= b,
            "<=": lambda a, b: a <= b,
            ">": lambda a, b: a > b,
            "<": lambda a, b: a < b,
            "==": lambda a, b: a == b,
        }
        return ops.get(self.operator, lambda a, b: False)(float(val), self.target)


@dataclass
class BudgetConfig:
    """Resource budget for a workflow run."""

    max_iterations: int = 5
    max_total_minutes: int = 120
    max_agent_spawns: int = 25

    @classmethod
    def from_dict(cls, d: dict) -> "BudgetConfig":
        return cls(
            max_iterations=d.get("max_iterations", 5),
            max_total_minutes=d.get("max_total_minutes", 120),
            max_agent_spawns=d.get("max_agent_spawns", 25),
        )


# ---------------------------------------------------------------------------
# Workflow Definition (parsed from YAML)
# ---------------------------------------------------------------------------


@dataclass
class WorkflowDef:
    name: str
    description: str
    version: str
    checkpoints: List[Checkpoint]
    completion_promise: Optional[CompletionPromise]
    budget: BudgetConfig
    variables_schema: Dict[str, Any]  # name -> {type, default, required}
    hooks: Dict[str, str]  # event -> command (on_start, on_complete, on_fail, etc.)
    loop: bool  # whether checkpoints repeat until promise met
    metadata: Dict[str, Any]

    @classmethod
    def from_yaml(cls, path: str | Path) -> "WorkflowDef":
        path = Path(path)
        if not path.is_absolute():
            # Try workflows dir, then templates dir
            for base in [WORKFLOWS_DIR, TEMPLATES_DIR]:
                candidate = base / path
                if candidate.exists():
                    path = candidate
                    break
        with open(path) as f:
            raw = yaml.safe_load(f)

        return cls(
            name=raw["name"],
            description=raw.get("description", ""),
            version=raw.get("version", "1.0"),
            checkpoints=[Checkpoint.from_dict(c) for c in raw["checkpoints"]],
            completion_promise=(
                CompletionPromise.from_dict(raw["completion_promise"])
                if raw.get("completion_promise")
                else None
            ),
            budget=BudgetConfig.from_dict(raw.get("budget", {})),
            variables_schema=raw.get("variables", {}),
            hooks=raw.get("hooks", {}),
            loop=raw.get("loop", False),
            metadata=raw.get("metadata", {}),
        )


# ---------------------------------------------------------------------------
# Workflow State (persisted to markdown)
# ---------------------------------------------------------------------------


@dataclass
class CheckpointResult:
    name: str
    status: CheckpointStatus
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    output: str = ""
    error: str = ""
    agent_session: str = ""
    attempt: int = 1
    decision: str = ""  # for decision checkpoints

    def to_dict(self) -> dict:
        return {k: v for k, v in self.__dict__.items() if v}


@dataclass
class IterationRecord:
    number: int
    started_at: str
    completed_at: Optional[str] = None
    checkpoint_results: List[CheckpointResult] = field(default_factory=list)
    variables_snapshot: Dict[str, Any] = field(default_factory=dict)
    promise_met: bool = False

    def to_dict(self) -> dict:
        return {
            "number": self.number,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "checkpoint_results": [cr.to_dict() for cr in self.checkpoint_results],
            "variables_snapshot": self.variables_snapshot,
            "promise_met": self.promise_met,
        }


@dataclass
class WorkflowState:
    workflow_id: str
    workflow_name: str
    workflow_file: str
    status: WorkflowStatus
    variables: Dict[str, Any]
    current_iteration: int
    current_checkpoint: str
    iterations: List[IterationRecord]
    created_at: str
    updated_at: str
    total_agent_spawns: int = 0
    error: str = ""

    @classmethod
    def new(
        cls,
        workflow_id: str,
        workflow_def: WorkflowDef,
        workflow_file: str,
        variables: Dict[str, Any],
    ) -> "WorkflowState":
        now = _now()
        return cls(
            workflow_id=workflow_id,
            workflow_name=workflow_def.name,
            workflow_file=workflow_file,
            status=WorkflowStatus.PENDING,
            variables=variables,
            current_iteration=0,
            current_checkpoint="",
            iterations=[],
            created_at=now,
            updated_at=now,
        )

    # --- Persistence (Markdown + JSON front-matter) ---

    def state_path(self) -> Path:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        return STATE_DIR / f"{self.workflow_id}-state.md"

    def save(self) -> Path:
        self.updated_at = _now()
        path = self.state_path()
        md = self._to_markdown()
        path.write_text(md)
        # Also write a machine-readable JSON sidecar
        json_path = path.with_suffix(".json")
        json_path.write_text(json.dumps(self._to_dict(), indent=2))
        return path

    @classmethod
    def load(cls, workflow_id: str) -> "WorkflowState":
        json_path = STATE_DIR / f"{workflow_id}-state.json"
        if not json_path.exists():
            raise FileNotFoundError(f"No state for workflow {workflow_id}")
        data = json.loads(json_path.read_text())
        iterations = []
        for it in data.get("iterations", []):
            crs = [
                CheckpointResult(
                    name=cr["name"],
                    status=CheckpointStatus(cr["status"]),
                    started_at=cr.get("started_at"),
                    completed_at=cr.get("completed_at"),
                    output=cr.get("output", ""),
                    error=cr.get("error", ""),
                    agent_session=cr.get("agent_session", ""),
                    attempt=cr.get("attempt", 1),
                    decision=cr.get("decision", ""),
                )
                for cr in it.get("checkpoint_results", [])
            ]
            iterations.append(
                IterationRecord(
                    number=it["number"],
                    started_at=it["started_at"],
                    completed_at=it.get("completed_at"),
                    checkpoint_results=crs,
                    variables_snapshot=it.get("variables_snapshot", {}),
                    promise_met=it.get("promise_met", False),
                )
            )
        return cls(
            workflow_id=data["workflow_id"],
            workflow_name=data["workflow_name"],
            workflow_file=data["workflow_file"],
            status=WorkflowStatus(data["status"]),
            variables=data.get("variables", {}),
            current_iteration=data.get("current_iteration", 0),
            current_checkpoint=data.get("current_checkpoint", ""),
            iterations=iterations,
            created_at=data["created_at"],
            updated_at=data["updated_at"],
            total_agent_spawns=data.get("total_agent_spawns", 0),
            error=data.get("error", ""),
        )

    def _to_dict(self) -> dict:
        return {
            "workflow_id": self.workflow_id,
            "workflow_name": self.workflow_name,
            "workflow_file": self.workflow_file,
            "status": self.status.value,
            "variables": self.variables,
            "current_iteration": self.current_iteration,
            "current_checkpoint": self.current_checkpoint,
            "iterations": [it.to_dict() for it in self.iterations],
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "total_agent_spawns": self.total_agent_spawns,
            "error": self.error,
        }

    def _to_markdown(self) -> str:
        lines = [
            f"# Workflow: {self.workflow_name}",
            f"**ID:** `{self.workflow_id}`",
            f"**Status:** {self.status.value}",
            f"**File:** `{self.workflow_file}`",
            f"**Created:** {self.created_at}",
            f"**Updated:** {self.updated_at}",
            f"**Iteration:** {self.current_iteration}",
            f"**Checkpoint:** {self.current_checkpoint or '—'}",
            f"**Agent Spawns:** {self.total_agent_spawns}",
            "",
            "## Variables",
            "```json",
            json.dumps(self.variables, indent=2),
            "```",
            "",
        ]
        if self.error:
            lines += ["## Error", f"```\n{self.error}\n```", ""]

        for it in self.iterations:
            lines.append(f"## Iteration {it.number}")
            lines.append(f"Started: {it.started_at}")
            if it.completed_at:
                lines.append(f"Completed: {it.completed_at}")
            lines.append(f"Promise met: {'✅' if it.promise_met else '❌'}")
            lines.append("")
            for cr in it.checkpoint_results:
                icon = {"completed": "✅", "failed": "❌", "skipped": "⏭️", "running": "🔄"}.get(
                    cr.status.value, "⏳"
                )
                lines.append(f"### {icon} {cr.name} ({cr.status.value})")
                if cr.started_at:
                    lines.append(f"- Started: {cr.started_at}")
                if cr.completed_at:
                    lines.append(f"- Completed: {cr.completed_at}")
                if cr.decision:
                    lines.append(f"- **Decision:** {cr.decision}")
                if cr.output:
                    lines.append(f"- Output:\n```\n{cr.output[:2000]}\n```")
                if cr.error:
                    lines.append(f"- Error:\n```\n{cr.error[:1000]}\n```")
                lines.append("")

        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Variable interpolation
# ---------------------------------------------------------------------------


def interpolate(template: str, variables: Dict[str, Any]) -> str:
    """Replace {{var}} placeholders with variable values."""
    def replacer(m):
        key = m.group(1).strip()
        val = variables.get(key, m.group(0))
        return str(val)

    return re.sub(r"\{\{(.+?)\}\}", replacer, template)


def eval_condition(expr: str, variables: Dict[str, Any]) -> bool:
    """Evaluate a condition expression safely against variables."""
    if not expr:
        return True
    try:
        return bool(eval(expr, {"__builtins__": {}}, variables))
    except Exception:
        return True  # if condition can't be evaluated, don't skip


# ---------------------------------------------------------------------------
# Action Generators (yield actions for the orchestrator to execute)
# ---------------------------------------------------------------------------


class Action:
    """Base class for actions the engine yields to the orchestrator."""
    pass


@dataclass
class SpawnAgent(Action):
    """Spawn a sub-agent with the given task."""
    label: str
    task: str
    timeout_min: int = 20
    checkpoint_name: str = ""


@dataclass
class RunHook(Action):
    """Run a shell command."""
    command: str
    checkpoint_name: str = ""


@dataclass
class RequestDecision(Action):
    """Pause and ask the orchestrator for a decision."""
    prompt: str
    options: List[str]
    checkpoint_name: str = ""
    context: Dict[str, Any] = field(default_factory=dict)


@dataclass
class EvaluateGate(Action):
    """Evaluate a gate expression."""
    expression: str
    checkpoint_name: str = ""


@dataclass
class WorkflowComplete(Action):
    """Workflow finished."""
    success: bool
    message: str = ""


@dataclass
class WorkflowError(Action):
    """Workflow hit an error."""
    message: str
    checkpoint_name: str = ""


@dataclass
class BudgetExceeded(Action):
    """Budget limit hit."""
    limit: str
    current: Any
    maximum: Any


# ---------------------------------------------------------------------------
# WorkflowRunner — the core engine
# ---------------------------------------------------------------------------


class WorkflowRunner:
    """
    Drives a workflow through its checkpoints, yielding actions for the
    orchestrator (main agent) to execute.

    Design: generator-based. Call `run()` to get an action generator.
    Feed results back via `send()` or `feed_result()`.

    This keeps the engine pure — no I/O, no sub-agent spawning. The
    orchestrator handles that and feeds results back.
    """

    def __init__(self, workflow_file: str | Path):
        self.workflow_file = str(workflow_file)
        self.definition = WorkflowDef.from_yaml(workflow_file)
        self.state: Optional[WorkflowState] = None

    def run(
        self,
        workflow_id: str,
        variables: Optional[Dict[str, Any]] = None,
    ) -> "WorkflowExecution":
        """Start a new workflow execution."""
        variables = variables or {}
        # Merge defaults from schema
        merged = {}
        for var_name, var_def in self.definition.variables_schema.items():
            if isinstance(var_def, dict):
                if var_name in variables:
                    merged[var_name] = variables[var_name]
                elif "default" in var_def:
                    merged[var_name] = var_def["default"]
                elif var_def.get("required", False):
                    raise ValueError(f"Required variable '{var_name}' not provided")
            else:
                merged[var_name] = variables.get(var_name, var_def)
        # Add any extra variables not in schema
        for k, v in variables.items():
            if k not in merged:
                merged[k] = v

        self.state = WorkflowState.new(
            workflow_id=workflow_id,
            workflow_def=self.definition,
            workflow_file=self.workflow_file,
            variables=merged,
        )
        self.state.save()
        return WorkflowExecution(self.definition, self.state)

    def resume(self, workflow_id: str) -> "WorkflowExecution":
        """Resume a paused/failed workflow."""
        self.state = WorkflowState.load(workflow_id)
        return WorkflowExecution(self.definition, self.state)

    @staticmethod
    def inspect(workflow_id: str) -> WorkflowState:
        """Load and return state without running."""
        return WorkflowState.load(workflow_id)

    @staticmethod
    def list_active() -> List[str]:
        """List workflow IDs with active state files."""
        if not STATE_DIR.exists():
            return []
        return [
            p.stem.replace("-state", "")
            for p in STATE_DIR.glob("*-state.json")
        ]


class WorkflowExecution:
    """
    Iterator-style execution. Call `next_action()` to get the next action,
    then `feed_result()` with the outcome.
    """

    def __init__(self, definition: WorkflowDef, state: WorkflowState):
        self.definition = definition
        self.state = state
        self._checkpoint_idx = 0
        self._done = False

        # If resuming, find where we left off
        if state.current_checkpoint:
            for i, cp in enumerate(definition.checkpoints):
                if cp.name == state.current_checkpoint:
                    self._checkpoint_idx = i
                    break

    def next_action(self) -> Action:
        """Get the next action to execute. Returns WorkflowComplete when done."""
        if self._done:
            return WorkflowComplete(success=True, message="Already completed")

        state = self.state
        defn = self.definition

        # --- Start new iteration if needed ---
        if state.status == WorkflowStatus.PENDING or (
            state.status == WorkflowStatus.RUNNING
            and self._checkpoint_idx == 0
            and (
                not state.iterations
                or state.iterations[-1].completed_at is not None
            )
        ):
            state.status = WorkflowStatus.RUNNING
            state.current_iteration += 1

            # Budget check: iterations
            if state.current_iteration > defn.budget.max_iterations:
                state.status = WorkflowStatus.FAILED
                state.error = f"Max iterations ({defn.budget.max_iterations}) exceeded"
                state.save()
                self._done = True
                return BudgetExceeded(
                    limit="max_iterations",
                    current=state.current_iteration,
                    maximum=defn.budget.max_iterations,
                )

            # Budget check: agent spawns
            if state.total_agent_spawns > defn.budget.max_agent_spawns:
                state.status = WorkflowStatus.FAILED
                state.error = f"Max agent spawns ({defn.budget.max_agent_spawns}) exceeded"
                state.save()
                self._done = True
                return BudgetExceeded(
                    limit="max_agent_spawns",
                    current=state.total_agent_spawns,
                    maximum=defn.budget.max_agent_spawns,
                )

            state.iterations.append(
                IterationRecord(
                    number=state.current_iteration,
                    started_at=_now(),
                    variables_snapshot=copy.deepcopy(state.variables),
                )
            )
            state.save()

        # --- Get current checkpoint ---
        if self._checkpoint_idx >= len(defn.checkpoints):
            # All checkpoints done for this iteration
            return self._finish_iteration()

        cp = defn.checkpoints[self._checkpoint_idx]
        state.current_checkpoint = cp.name
        state.save()

        # --- Check condition ---
        if cp.condition and not eval_condition(cp.condition, state.variables):
            self._record_checkpoint(cp.name, CheckpointStatus.SKIPPED)
            self._checkpoint_idx += 1
            return self.next_action()  # recurse to next

        # --- Generate action based on kind ---
        if cp.kind == CheckpointKind.TASK:
            task = interpolate(cp.agent_task, state.variables)
            state.total_agent_spawns += 1
            state.save()
            return SpawnAgent(
                label=cp.agent_label,
                task=task,
                timeout_min=cp.timeout_min,
                checkpoint_name=cp.name,
            )

        elif cp.kind == CheckpointKind.HOOK:
            cmd = interpolate(cp.hook_command, state.variables)
            return RunHook(command=cmd, checkpoint_name=cp.name)

        elif cp.kind == CheckpointKind.DECISION:
            prompt = interpolate(cp.decision_prompt, state.variables)
            return RequestDecision(
                prompt=prompt,
                options=cp.decision_options,
                checkpoint_name=cp.name,
                context={
                    "iteration": state.current_iteration,
                    "variables": state.variables,
                },
            )

        elif cp.kind == CheckpointKind.GATE:
            return EvaluateGate(
                expression=cp.gate_expr,
                checkpoint_name=cp.name,
            )

        return WorkflowError(message=f"Unknown checkpoint kind: {cp.kind}")

    def feed_result(
        self,
        checkpoint_name: str,
        success: bool,
        output: str = "",
        error: str = "",
        variables_update: Optional[Dict[str, Any]] = None,
        decision: str = "",
        agent_session: str = "",
    ) -> None:
        """Feed the result of an action back into the engine."""
        state = self.state

        status = CheckpointStatus.COMPLETED if success else CheckpointStatus.FAILED

        self._record_checkpoint(
            checkpoint_name,
            status,
            output=output,
            error=error,
            decision=decision,
            agent_session=agent_session,
        )

        # Update variables
        if variables_update:
            state.variables.update(variables_update)

        if success:
            self._checkpoint_idx += 1
        else:
            # Check failure policy
            cp = self._find_checkpoint(checkpoint_name)
            if cp and cp.on_failure == "skip":
                self._checkpoint_idx += 1
            elif cp and cp.on_failure == "retry":
                last_cr = self._last_checkpoint_result(checkpoint_name)
                if last_cr and last_cr.attempt < cp.max_retries:
                    pass  # don't advance, will retry
                else:
                    state.status = WorkflowStatus.FAILED
                    state.error = f"Checkpoint '{checkpoint_name}' failed after {cp.max_retries} retries"
                    self._done = True
            else:  # abort
                state.status = WorkflowStatus.FAILED
                state.error = f"Checkpoint '{checkpoint_name}' failed: {error}"
                self._done = True

        state.save()

    def cancel(self) -> None:
        self.state.status = WorkflowStatus.CANCELLED
        self.state.save()
        self._done = True

    def pause(self) -> None:
        self.state.status = WorkflowStatus.PAUSED
        self.state.save()

    # --- Internal ---

    def _finish_iteration(self) -> Action:
        state = self.state
        defn = self.definition
        iteration = state.iterations[-1]
        iteration.completed_at = _now()
        iteration.variables_snapshot = copy.deepcopy(state.variables)

        # Check completion promise
        if defn.completion_promise:
            met = defn.completion_promise.evaluate(state.variables)
            iteration.promise_met = met
            if met:
                state.status = WorkflowStatus.COMPLETED
                state.save()
                self._done = True
                return WorkflowComplete(
                    success=True,
                    message=f"✅ Completion promise met: {defn.completion_promise.description}",
                )

        # If not a loop, we're done after one pass
        if not defn.loop:
            state.status = WorkflowStatus.COMPLETED
            state.save()
            self._done = True
            return WorkflowComplete(
                success=True,
                message="Workflow completed (single pass)",
            )

        # Loop: reset checkpoint index and continue
        self._checkpoint_idx = 0
        state.save()
        return self.next_action()

    def _record_checkpoint(
        self,
        name: str,
        status: CheckpointStatus,
        output: str = "",
        error: str = "",
        decision: str = "",
        agent_session: str = "",
    ) -> None:
        if not self.state.iterations:
            return
        iteration = self.state.iterations[-1]
        cr = CheckpointResult(
            name=name,
            status=status,
            started_at=_now() if status == CheckpointStatus.RUNNING else None,
            completed_at=_now() if status in (CheckpointStatus.COMPLETED, CheckpointStatus.FAILED, CheckpointStatus.SKIPPED) else None,
            output=output,
            error=error,
            decision=decision,
            agent_session=agent_session,
            attempt=self._count_attempts(name) + 1,
        )
        iteration.checkpoint_results.append(cr)

    def _find_checkpoint(self, name: str) -> Optional[Checkpoint]:
        for cp in self.definition.checkpoints:
            if cp.name == name:
                return cp
        return None

    def _last_checkpoint_result(self, name: str) -> Optional[CheckpointResult]:
        if not self.state.iterations:
            return None
        for cr in reversed(self.state.iterations[-1].checkpoint_results):
            if cr.name == name:
                return cr
        return None

    def _count_attempts(self, name: str) -> int:
        if not self.state.iterations:
            return 0
        return sum(
            1 for cr in self.state.iterations[-1].checkpoint_results if cr.name == name
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _now() -> str:
    return _dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
