#!/bin/bash
# Process Completion Checker — Detects when tracked processes finish and triggers callbacks.
# Runs every 30s via launchd. Decoupled from agents — processes survive agent death.
#
# For each registered process:
#   1. Check if PID is alive
#   2. If dead: read exit code, mark completed/failed
#   3. If callback=dispatch: spawn fresh agent with original task context + results
#   4. If callback=notify: post to Linear + Slack
#   5. If timeout exceeded: kill and mark failed
#
set -euo pipefail

PROCESS_MGR="/Users/fonsecabc/.openclaw/workspace/scripts/process-manager.sh"
REGISTRY_FILE="/Users/fonsecabc/.openclaw/tasks/process-registry.json"
DISPATCH="/Users/fonsecabc/.openclaw/workspace/scripts/dispatch-task.sh"
SPAWNER="/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOCKFILE="/tmp/process-completion-checker.lock"

# Single instance
exec 202>"$LOCKFILE"
flock -n 202 || { exit 0; }

source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null || true
source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || true

[ -f "$REGISTRY_FILE" ] || exit 0

python3 << 'PYEOF'
import json, os, sys, time, subprocess, glob

REGISTRY_FILE = "/Users/fonsecabc/.openclaw/tasks/process-registry.json"
SPAWNER = "/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
LINEAR_LOG = "/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
PROCESS_MGR = "/Users/fonsecabc/.openclaw/workspace/scripts/process-manager.sh"
LOGS_DIR = "/Users/fonsecabc/.openclaw/tasks/agent-logs"
SPAWN_TASKS_DIR = "/Users/fonsecabc/.openclaw/tasks/spawn-tasks"

SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
CAIO_DM = "D0AK1B981QR"

now = int(time.time())

try:
    with open(REGISTRY_FILE) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

processes = data.get("processes", {})
if not processes:
    sys.exit(0)

changes = False

for proc_id, proc in list(processes.items()):
    status = proc.get("status", "running")
    callback_dispatched = proc.get("callbackDispatched", False)

    # Handle already-completed processes with pending callbacks
    if status != "running" and not callback_dispatched:
        # Fall through to callback logic below
        pass
    elif status != "running":
        continue

    pid = proc.get("pid", 0)
    task_id = proc.get("taskId", "")
    proc_type = proc.get("type", "unknown")
    timeout_min = proc.get("timeoutMin", 120)
    started_epoch = proc.get("startedEpoch", now)
    age_min = (now - started_epoch) // 60
    callback_type = proc.get("callbackType", "none")
    callback_dispatched = proc.get("callbackDispatched", False)

    # Check if PID is alive
    alive = False
    try:
        os.kill(pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        alive = False

    # --- Already completed but callback pending? Skip detection, go straight to callback ---
    if status != "running" and not callback_dispatched:
        print(f"PENDING_CALLBACK {proc_id}: status={status}, dispatching callback")
        # Jump directly to callback execution below (after the detection block)
        # We need the results_summary — try to build it from existing data
        results_summary = ""
        metrics_path = proc.get("metricsPath", "")
        result_path = proc.get("resultPath", "")
        has_metrics = metrics_path and os.path.exists(metrics_path)
        has_result = result_path and os.path.exists(result_path)
        exit_code = proc.get("exitCode", 1)

        if has_metrics:
            try:
                with open(metrics_path) as f:
                    metrics = json.load(f)
                if proc_type == "eval":
                    summary_stats = metrics.get("summary_statistics", {})
                    accuracy = summary_stats.get("mean_aggregate_score", 0) * 100
                    baseline_acc = 76.86
                    try:
                        with open("/tmp/guardian-main-baseline-real.json") as bf:
                            bl = json.load(bf)
                            baseline_acc = bl.get("accuracy", 0.7686) * 100
                    except Exception:
                        pass
                    delta = accuracy - baseline_acc
                    results_summary = (
                        f"## Eval Results\n"
                        f"- Accuracy: {accuracy:.2f}%\n"
                        f"- Baseline: {baseline_acc:.2f}%\n"
                        f"- Delta: {delta:+.2f}pp\n"
                        f"- Samples: {summary_stats.get('total_samples', 0)}\n"
                        f"- Metrics file: {metrics_path}\n"
                    )
                    per_class = metrics.get("per_classification_scores", {})
                    if per_class:
                        results_summary += "\n### Per-Classification:\n"
                        for cls_name, cls_data in sorted(per_class.items()):
                            cls_acc = cls_data.get("mean_score", 0) * 100
                            cls_count = cls_data.get("count", 0)
                            results_summary += f"- {cls_name}: {cls_acc:.1f}% ({cls_count} samples)\n"
                else:
                    results_summary = f"## Process Results\n```json\n{json.dumps(metrics, indent=2)[:2000]}\n```\n"
            except Exception as e:
                results_summary = f"## Results\nFailed to parse metrics: {e}\n"
        elif has_result:
            try:
                with open(result_path) as f:
                    content = f.read(3000)
                results_summary = f"## Process Output\n```\n{content}\n```\n"
            except Exception:
                pass

        # Build and dispatch callback
        if callback_type == "dispatch":
            callback_context = proc.get("callbackContext", "")
            callback_prompt = (
                f"# Process Completion — Resume Task {task_id}\n\n"
                f"A {proc_type} process has {'completed successfully' if status == 'completed' else 'FAILED'}.\n\n"
                f"{results_summary}\n\n"
            )
            if callback_context:
                callback_prompt += f"## Original Context\n{callback_context}\n\n"
            if status == "completed":
                callback_prompt += (
                    f"## Your Mission\n"
                    f"Review the results above and take the appropriate next action:\n"
                    f"- If the eval shows improvement: commit changes, log success to Linear, mark done\n"
                    f"- If the eval shows regression: investigate, try alternative approaches\n"
                    f"- If mixed results: analyze per-classification breakdown, refine specific areas\n\n"
                    f"Use `linear-log.sh {task_id} 'message' status` for all logging.\n"
                )
            else:
                callback_prompt += (
                    f"## Your Mission\n"
                    f"The process failed. Investigate why, fix the issue, re-run if appropriate.\n"
                    f"Use `linear-log.sh {task_id} 'message' status` for all logging.\n"
                )

            callback_file = f"{SPAWN_TASKS_DIR}/{task_id}-callback.md"
            os.makedirs(SPAWN_TASKS_DIR, exist_ok=True)
            with open(callback_file, "w") as f:
                f.write(callback_prompt)

            try:
                slots_result = subprocess.run(
                    ["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh", "slots"],
                    capture_output=True, text=True, timeout=5
                )
                slots = int(slots_result.stdout.strip())
            except Exception:
                slots = 0

            if slots > 0:
                try:
                    result = subprocess.run(
                        ["bash", SPAWNER,
                         "--task", task_id,
                         "--label", f"{task_id}-callback",
                         "--source", "process-callback",
                         "--timeout", "30",
                         "--file", callback_file],
                        capture_output=True, text=True, timeout=30
                    )
                    if result.returncode == 0:
                        proc["callbackDispatched"] = True
                        changes = True
                        print(f"  → Callback agent spawned for {task_id}")
                    else:
                        print(f"  → Spawn failed: {result.stderr[:200]}")
                except Exception as e:
                    print(f"  → Spawn error: {e}")
            else:
                print(f"  → No agent slots, deferred")

        elif callback_type == "notify":
            msg = f"Process {proc_type} {status} (exit={exit_code}). {results_summary[:500]}"
            try:
                subprocess.run(["bash", LINEAR_LOG, task_id, msg, "done" if status == "completed" else "blocked"],
                    capture_output=True, timeout=15)
            except Exception:
                pass
            proc["callbackDispatched"] = True
            changes = True

        continue

    # --- Timeout check ---
    if alive and age_min >= timeout_min:
        print(f"TIMEOUT {proc_id}: {age_min}min >= {timeout_min}min — killing PID {pid}")
        try:
            # Kill process tree
            subprocess.run(
                ["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh", str(pid)],
                capture_output=True, timeout=10
            )
        except Exception:
            try:
                os.kill(pid, 9)
            except Exception:
                pass

        proc["status"] = "timeout"
        proc["exitCode"] = -1
        proc["completedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        changes = True

        # Log to Linear
        try:
            subprocess.run(
                ["bash", LINEAR_LOG, task_id,
                 f"Process {proc_type} timed out after {age_min}min (limit: {timeout_min}min). PID {pid} killed.",
                 "blocked"],
                capture_output=True, timeout=15
            )
        except Exception:
            pass

        print(f"  → Logged timeout for {task_id}")
        continue

    if alive:
        # Still running, nothing to do
        if age_min > 0 and age_min % 10 == 0:
            print(f"OK {proc_id}: PID={pid} alive, {age_min}/{timeout_min}min")
        continue

    # --- Process is DEAD — determine outcome ---
    print(f"DETECTED {proc_id}: PID {pid} is dead after {age_min}min")

    # Try to determine exit code from wait file or /proc (macOS doesn't have /proc)
    # Best effort: check if result/metrics files exist
    result_path = proc.get("resultPath", "")
    metrics_path = proc.get("metricsPath", "")

    has_result = result_path and os.path.exists(result_path)
    has_metrics = metrics_path and os.path.exists(metrics_path)

    # For evals: check if metrics.json appeared in the expected run dir
    if proc_type == "eval" and not has_metrics and metrics_path:
        # Try glob for the latest run dir
        base_dir = os.path.dirname(metrics_path)
        if os.path.isdir(base_dir):
            has_metrics = os.path.exists(metrics_path)
        else:
            # Try to find any recent metrics.json in the evals runs directory
            eval_runs = glob.glob("/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_*/metrics.json")
            if eval_runs:
                latest_run = max(eval_runs, key=os.path.getmtime)
                if os.path.getmtime(latest_run) > started_epoch:
                    metrics_path = latest_run
                    has_metrics = True
                    proc["metricsPath"] = metrics_path
                    print(f"  → Found eval metrics: {metrics_path}")

    # Determine success/failure
    if has_metrics or has_result:
        exit_code = 0
        proc["status"] = "completed"
        print(f"  → Result found: metrics={has_metrics} result={has_result}")
    else:
        # Check result log for error indicators
        exit_code = 1
        proc["status"] = "failed"
        if result_path and os.path.exists(result_path):
            try:
                with open(result_path) as f:
                    content = f.read(500)
                if "error" in content.lower() or "traceback" in content.lower():
                    print(f"  → Result log has errors")
                else:
                    # Has output but no metrics — might be partial success
                    exit_code = 0
                    proc["status"] = "completed"
            except Exception:
                pass
        print(f"  → No result/metrics found, status={proc['status']}")

    proc["exitCode"] = exit_code
    proc["completedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    changes = True

    # --- Read results for callback context ---
    results_summary = ""

    if has_metrics:
        try:
            with open(metrics_path) as f:
                metrics = json.load(f)

            # Extract key metrics depending on type
            if proc_type == "eval":
                summary_stats = metrics.get("summary_statistics", {})
                accuracy = summary_stats.get("mean_aggregate_score", 0) * 100
                total_samples = summary_stats.get("total_samples", 0)

                # Load baseline for comparison
                baseline_acc = 76.86  # default
                baseline_file = "/tmp/guardian-main-baseline-real.json"
                try:
                    with open(baseline_file) as bf:
                        bl = json.load(bf)
                        baseline_acc = bl.get("accuracy", 0.7686) * 100
                except Exception:
                    pass

                delta = accuracy - baseline_acc
                results_summary = (
                    f"## Eval Results\n"
                    f"- Accuracy: {accuracy:.2f}%\n"
                    f"- Baseline: {baseline_acc:.2f}%\n"
                    f"- Delta: {delta:+.2f}pp\n"
                    f"- Samples: {total_samples}\n"
                    f"- Metrics file: {metrics_path}\n"
                )

                # Add per-classification breakdown if available
                per_class = metrics.get("per_classification_scores", {})
                if per_class:
                    results_summary += "\n### Per-Classification:\n"
                    for cls_name, cls_data in sorted(per_class.items()):
                        cls_acc = cls_data.get("mean_score", 0) * 100
                        cls_count = cls_data.get("count", 0)
                        results_summary += f"- {cls_name}: {cls_acc:.1f}% ({cls_count} samples)\n"
            else:
                results_summary = f"## Process Results\n```json\n{json.dumps(metrics, indent=2)[:2000]}\n```\n"
        except Exception as e:
            results_summary = f"## Results\nFailed to parse metrics: {e}\nFile: {metrics_path}\n"

    elif has_result:
        try:
            with open(result_path) as f:
                content = f.read(3000)
            results_summary = f"## Process Output (last 3KB)\n```\n{content}\n```\n"
        except Exception:
            results_summary = f"## Results\nResult file exists but could not be read: {result_path}\n"

    # --- Execute callback ---
    if callback_dispatched:
        print(f"  → Callback already dispatched, skipping")
        continue

    if callback_type == "dispatch" and proc["status"] in ("completed", "failed"):
        # Build callback prompt: original context + results
        callback_context = proc.get("callbackContext", "")

        callback_prompt = (
            f"# Process Completion — Resume Task {task_id}\n\n"
            f"A {proc_type} process has {'completed successfully' if proc['status'] == 'completed' else 'FAILED'}.\n\n"
            f"{results_summary}\n\n"
        )

        if callback_context:
            callback_prompt += f"## Original Context\n{callback_context}\n\n"

        if proc["status"] == "completed":
            callback_prompt += (
                f"## Your Mission\n"
                f"Review the results above and take the appropriate next action:\n"
                f"- If the eval shows improvement: commit changes, log success to Linear, mark done\n"
                f"- If the eval shows regression: investigate, try alternative approaches, run another eval if needed\n"
                f"- If mixed results: analyze per-classification breakdown, refine the specific areas that regressed\n\n"
                f"Use `linear-log.sh {task_id} 'message' status` for all logging.\n"
            )
        else:
            callback_prompt += (
                f"## Your Mission\n"
                f"The process failed. Investigate why:\n"
                f"- Check the result/log files listed above\n"
                f"- Fix the underlying issue\n"
                f"- Re-run the process if appropriate\n"
                f"- Log findings to Linear\n\n"
                f"Use `linear-log.sh {task_id} 'message' status` for all logging.\n"
            )

        # Save callback prompt to file
        callback_file = f"{SPAWN_TASKS_DIR}/{task_id}-callback.md"
        os.makedirs(SPAWN_TASKS_DIR, exist_ok=True)
        with open(callback_file, "w") as f:
            f.write(callback_prompt)

        # Check if we have agent slots available
        try:
            slots_result = subprocess.run(
                ["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh", "slots"],
                capture_output=True, text=True, timeout=5
            )
            slots = int(slots_result.stdout.strip())
        except Exception:
            slots = 0

        if slots > 0:
            print(f"  → Dispatching callback agent for {task_id}")
            try:
                result = subprocess.run(
                    ["bash", SPAWNER,
                     "--task", task_id,
                     "--label", f"{task_id}-callback",
                     "--source", "process-callback",
                     "--timeout", "30",
                     "--file", callback_file],
                    capture_output=True, text=True, timeout=30
                )
                if result.returncode == 0:
                    agent_pid = result.stdout.strip().split("\n")[-1]
                    proc["callbackDispatched"] = True
                    print(f"  → Callback agent spawned: PID={agent_pid}")

                    # Log to Linear
                    subprocess.run(
                        ["bash", LINEAR_LOG, task_id,
                         f"Process {proc_type} completed (exit={exit_code}). Callback agent spawned to process results.",
                         "progress"],
                        capture_output=True, timeout=15
                    )
                else:
                    print(f"  → Spawn failed: {result.stderr[:200]}")
                    # Log failure but don't block
                    subprocess.run(
                        ["bash", LINEAR_LOG, task_id,
                         f"Process {proc_type} completed but callback spawn failed: {result.stderr[:200]}",
                         "blocked"],
                        capture_output=True, timeout=15
                    )
            except Exception as e:
                print(f"  → Spawn error: {e}")
        else:
            print(f"  → No agent slots available, callback deferred")
            # Will be retried next checker run since callbackDispatched is still False

    elif callback_type == "notify":
        # Just post to Linear + Slack
        status_word = "completed" if proc["status"] == "completed" else "failed"
        msg = f"Process {proc_type} {status_word} after {age_min}min (exit={exit_code})."
        if results_summary:
            msg += f"\n{results_summary[:500]}"

        try:
            linear_status = "done" if proc["status"] == "completed" else "blocked"
            subprocess.run(
                ["bash", LINEAR_LOG, task_id, msg, linear_status],
                capture_output=True, timeout=15
            )
        except Exception:
            pass

        # Slack notification
        if SLACK_BOT_TOKEN:
            try:
                icon = "✅" if proc["status"] == "completed" else "❌"
                slack_msg = f"{icon} *Process {proc_type}* for {task_id}: {status_word} after {age_min}min"
                subprocess.run(
                    ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
                     "-H", f"Authorization: Bearer {SLACK_BOT_TOKEN}",
                     "-H", "Content-Type: application/json",
                     "-d", json.dumps({"channel": CAIO_DM, "text": slack_msg})],
                    capture_output=True, timeout=10
                )
            except Exception:
                pass

        proc["callbackDispatched"] = True
        changes = True

    elif callback_type == "none":
        proc["callbackDispatched"] = True
        changes = True
        print(f"  → No callback configured")

# --- Cleanup old completed processes (>24h) ---
cleanup_cutoff = now - 86400
for proc_id, proc in list(processes.items()):
    if proc.get("status") in ("completed", "failed", "timeout"):
        completed_at = proc.get("completedAt", "")
        completed_epoch = proc.get("startedEpoch", 0) + proc.get("timeoutMin", 0) * 60
        if completed_epoch < cleanup_cutoff and proc.get("callbackDispatched", False):
            del processes[proc_id]
            changes = True
            print(f"CLEANUP {proc_id}: removed (>24h old, callback dispatched)")

# Write back
if changes:
    with open(REGISTRY_FILE, "w") as f:
        json.dump(data, f, indent=2)

# Summary
running = sum(1 for p in processes.values() if p.get("status") == "running")
completed = sum(1 for p in processes.values() if p.get("status") == "completed")
failed = sum(1 for p in processes.values() if p.get("status") in ("failed", "timeout"))
pending_callback = sum(1 for p in processes.values() if p.get("status") != "running" and not p.get("callbackDispatched", False))

if running or completed or failed or pending_callback:
    print(f"\n=== Process Checker: running={running} completed={completed} failed={failed} pending_callbacks={pending_callback} ===")

PYEOF
