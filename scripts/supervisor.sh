#!/bin/bash
# supervisor.sh — Unified process supervisor (replaces agent-watchdog-v2.sh + process-completion-checker.sh)
# Runs every 30s via launchd. Single source: state.json
#
# Responsibilities:
#   1. Check agent PIDs — detect completions, failures, idle
#   2. Check process PIDs — detect eval/pipeline completions
#   3. Dispatch callbacks — spawn callback agents with results + history
#   4. Handle timeouts — kill + requeue
#   5. Orphan cleanup — kill unregistered claude processes
#   6. Health metrics — track success rates, alert on issues
#
set -euo pipefail

TASK_MGR="/Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh"
SPAWNER="/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REPORT="/Users/fonsecabc/.openclaw/workspace/scripts/agent-report.sh"
KILL_TREE="/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh"
DETECT_IDLE="/Users/fonsecabc/.openclaw/workspace/scripts/detect-agent-idle.sh"
LOCKFILE="/tmp/supervisor.lock"

# Single instance
exec 200>"$LOCKFILE"
flock -n 200 || { exit 0; }

mkdir -p /Users/fonsecabc/.openclaw/tasks/agent-logs

source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || true
source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null || true

python3 << 'PYEOF'
import json, os, sys, time, subprocess, re, glob
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta

STATE_FILE = "/Users/fonsecabc/.openclaw/tasks/state.json"
TASK_MGR = "/Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh"
SPAWNER = "/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
LINEAR_LOG = "/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REPORT = "/Users/fonsecabc/.openclaw/workspace/scripts/agent-report.sh"
KILL_TREE = "/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh"
DETECT_IDLE = "/Users/fonsecabc/.openclaw/workspace/scripts/detect-agent-idle.sh"
LOGS_DIR = "/Users/fonsecabc/.openclaw/tasks/agent-logs"
SPAWN_TASKS_DIR = "/Users/fonsecabc/.openclaw/tasks/spawn-tasks"
METRICS_FILE = "/Users/fonsecabc/.openclaw/workspace/metrics/agent-health.json"
CONSEC_FILE = "/Users/fonsecabc/.openclaw/tasks/consecutive-failures.json"
ALERT_COOLDOWN_FILE = "/Users/fonsecabc/.openclaw/workspace/metrics/alert-cooldown.json"

SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
REPLICANTS_CHANNEL = "D0AK1B981QR"

MIN_OUTPUT_BYTES = 100
CONSECUTIVE_FAILURE_THRESHOLD = 3

FAILURE_PATTERNS = [
    r"permission.*denied", r"not allowed", r"blocked", r"I need.*approval",
    r"I'm unable to", r"I cannot", r"access denied", r"authentication.*failed",
    r"EACCES", r"API Error", r"usage limits", r"rate limit", r"quota exceeded",
    r"invalid_request_error",
]

REVIEW_HOOK = "/Users/fonsecabc/.openclaw/workspace/scripts/review-hook.sh"

now = int(time.time())
ts = time.strftime("%H:%M", time.gmtime())

# Load state
try:
    with open(STATE_FILE) as f:
        state = json.load(f)
except Exception:
    state = {"tasks": {}, "maxConcurrent": 3}

tasks = state.get("tasks", {})
changes = False
completions = timeouts = failures = callbacks_dispatched = 0

# Load consecutive failure tracking
try:
    consec = json.load(open(CONSEC_FILE))
except Exception:
    consec = {"count": 0, "task_ids": []}


def is_alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def run_cmd(cmd, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


def check_output_quality(task_id):
    output_log = f"{LOGS_DIR}/{task_id}-output.log"
    stderr_log = f"{LOGS_DIR}/{task_id}-stderr.log"
    output_size = os.path.getsize(output_log) if os.path.exists(output_log) else 0
    stderr_size = os.path.getsize(stderr_log) if os.path.exists(stderr_log) else 0

    if output_size < 2:
        stderr_msg = ""
        if stderr_size > 0:
            try:
                with open(stderr_log) as f:
                    stderr_msg = f.read(500)
            except Exception:
                pass
        return "empty", output_size, stderr_msg

    if output_size < MIN_OUTPUT_BYTES:
        try:
            with open(output_log) as f:
                content = f.read()
            for pattern in FAILURE_PATTERNS:
                if re.search(pattern, content, re.IGNORECASE):
                    return "blocked", output_size, f"Pattern: {pattern}"
        except Exception:
            pass
        return "small", output_size, ""

    try:
        with open(output_log) as f:
            head = f.read(500)
        for pattern in FAILURE_PATTERNS:
            if re.search(pattern, head, re.IGNORECASE):
                return "blocked", output_size, f"Pattern: {pattern}"
    except Exception:
        pass

    return "success", output_size, ""


def requeue_task(task_id):
    """Move task back to Todo in Linear."""
    if not LINEAR_API_KEY:
        return
    try:
        query = json.dumps({"query": 'query{issues(filter:{identifier:{eq:"' + task_id + '"}},first:1){nodes{id}}}'})
        r = run_cmd(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
                      "-H", f"Authorization: {LINEAR_API_KEY}",
                      "-H", "Content-Type: application/json", "-d", query])
        if not r or r.returncode != 0:
            return
        nodes = json.loads(r.stdout).get("data", {}).get("issues", {}).get("nodes", [])
        if not nodes:
            return
        issue_id = nodes[0]["id"]

        state_q = json.dumps({"query": 'query{workflowStates(filter:{name:{eq:"Todo"},team:{key:{eq:"AUTO"}}},first:1){nodes{id}}}'})
        r2 = run_cmd(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
                       "-H", f"Authorization: {LINEAR_API_KEY}",
                       "-H", "Content-Type: application/json", "-d", state_q])
        if not r2:
            return
        state_nodes = json.loads(r2.stdout).get("data", {}).get("workflowStates", {}).get("nodes", [])
        if not state_nodes:
            return
        state_id = state_nodes[0]["id"]

        mutation = json.dumps({"query": f'mutation{{issueUpdate(id:"{issue_id}",input:{{stateId:"{state_id}"}}){{success}}}}'})
        run_cmd(["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
                  "-H", f"Authorization: {LINEAR_API_KEY}",
                  "-H", "Content-Type: application/json", "-d", mutation])
        print(f"  REQUEUED {task_id} → Todo")
    except Exception as e:
        print(f"  REQUEUE FAILED {task_id}: {e}")


def trigger_review_hook(task_id):
    """Trigger adversarial review for completed tasks (if enabled)."""
    if os.path.exists(REVIEW_HOOK):
        try:
            r = subprocess.run(["bash", REVIEW_HOOK, task_id],
                               capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                print(f"  REVIEW: {r.stdout.strip()}")
        except Exception as e:
            print(f"  REVIEW hook error: {e}")


def send_alert(message):
    if not SLACK_BOT_TOKEN:
        return
    try:
        run_cmd(["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
                  "-H", f"Authorization: Bearer {SLACK_BOT_TOKEN}",
                  "-H", "Content-Type: application/json",
                  "-d", json.dumps({"channel": REPLICANTS_CHANNEL, "text": message, "mrkdwn": True})])
    except Exception:
        pass


def build_callback_prompt(task_id, task):
    """Build the prompt for a callback agent, including history and learnings."""
    proc_type = task.get("processType", "process")
    status = task.get("status", "callback_pending")
    results_summary = ""
    metrics_path = task.get("metricsPath", "")
    result_path = task.get("resultPath", "")

    # Read metrics
    if metrics_path and os.path.exists(metrics_path):
        try:
            with open(metrics_path) as f:
                metrics = json.load(f)
            if proc_type == "eval":
                ss = metrics.get("summary_statistics", {})
                accuracy = ss.get("mean_aggregate_score", 0) * 100
                baseline = 79.0
                try:
                    with open("/tmp/guardian-main-baseline-real.json") as bf:
                        baseline = json.load(bf).get("accuracy", 0.79) * 100
                except Exception:
                    pass
                delta = accuracy - baseline
                results_summary = (
                    f"## Eval Results\n"
                    f"- Accuracy: {accuracy:.2f}%\n"
                    f"- Baseline: {baseline:.2f}%\n"
                    f"- Delta: {delta:+.2f}pp\n"
                    f"- Samples: {ss.get('total_samples', 0)}\n"
                    f"- Metrics: {metrics_path}\n"
                )
                per_class = metrics.get("per_classification_scores", {})
                if per_class:
                    results_summary += "\n### Per-Classification:\n"
                    for cls, data in sorted(per_class.items()):
                        results_summary += f"- {cls}: {data.get('mean_score',0)*100:.1f}% ({data.get('count',0)} samples)\n"
            else:
                results_summary = f"## Results\n```json\n{json.dumps(metrics, indent=2)[:2000]}\n```\n"
        except Exception as e:
            results_summary = f"## Results\nFailed to parse: {e}\n"
    elif result_path and os.path.exists(result_path):
        try:
            with open(result_path) as f:
                content = f.read(3000)
            results_summary = f"## Output\n```\n{content}\n```\n"
        except Exception:
            pass

    # Build history context
    history = task.get("history", [])
    history_section = ""
    if history:
        history_section = "## Previous Attempts\n"
        for i, h in enumerate(history[-5:], 1):
            history_section += f"- Cycle {i}: {json.dumps(h)[:200]}\n"
        history_section += "\n"

    # Build learnings context
    learnings = task.get("learnings", [])
    learnings_section = ""
    if learnings:
        learnings_section = "## Known Learnings\n"
        for l in learnings[-5:]:
            learnings_section += f"- {l}\n"
        learnings_section += "\n"

    context = task.get("callbackContext", "")

    prompt = (
        f"# Process Completion — Resume Task {task_id}\n\n"
        f"A {proc_type} process has completed.\n\n"
        f"{results_summary}\n"
        f"{history_section}"
        f"{learnings_section}"
    )
    if context:
        prompt += f"## Original Context\n{context}\n\n"

    prompt += (
        f"## Your Mission\n"
        f"Review the results. Take the next action:\n"
        f"- Improvement: commit, log success, mark done\n"
        f"- Regression: investigate, try alternative, run another eval\n"
        f"- Mixed: analyze per-classification, refine specific areas\n"
        f"- Failed: check logs, fix issue, re-run\n\n"
        f"**After analyzing results, update the task history:**\n"
        f"```bash\n"
        f"bash scripts/task-manager.sh add-history {task_id} '{{\"cycle\": N, \"accuracy\": X.X, \"delta\": \"+Y.Ypp\", \"action\": \"what you did\"}}'\n"
        f"bash scripts/task-manager.sh add-learning {task_id} 'what you learned from this cycle'\n"
        f"```\n\n"
        f"Use `linear-log.sh {task_id} 'message' status` for all logging.\n"
    )
    return prompt


def dispatch_callback(task_id, task):
    """Spawn a callback agent for a completed process."""
    global callbacks_dispatched, changes

    # Check slots
    try:
        r = run_cmd(["bash", TASK_MGR, "slots"])
        slots = int(r.stdout.strip()) if r and r.returncode == 0 else 0
    except Exception:
        slots = 0

    if slots <= 0:
        print(f"  → No agent slots for callback, deferred")
        return False

    # Build callback prompt
    prompt = build_callback_prompt(task_id, task)

    os.makedirs(SPAWN_TASKS_DIR, exist_ok=True)
    callback_file = f"{SPAWN_TASKS_DIR}/{task_id}-callback.md"
    with open(callback_file, "w") as f:
        f.write(prompt)

    # Transition to agent_running first
    run_cmd(["bash", TASK_MGR, "transition", task_id, "agent_running",
             "--source", "process-callback", "--timeout", "30"])

    # Spawn via spawn-agent.sh
    r = run_cmd(["bash", SPAWNER, "--task", task_id, "--label", f"{task_id}-callback",
                  "--source", "process-callback", "--timeout", "30",
                  "--force",  # bypass dedup for callbacks
                  "--file", callback_file], timeout=30)

    if r and r.returncode == 0:
        agent_pid = r.stdout.strip().split("\n")[-1]
        print(f"  → Callback agent spawned: PID={agent_pid}")
        callbacks_dispatched += 1
        run_cmd(["bash", LINEAR_LOG, task_id,
                 f"Process completed. Callback agent spawned to process results.", "progress"])
        return True
    else:
        err = r.stderr[:200] if r else "unknown"
        print(f"  → Callback spawn failed: {err}")
        # Transition back to callback_pending
        # (can't directly — need to go through valid transitions)
        return False


# ============================================================================
# MAIN LOOP — Iterate over all tasks in state
# ============================================================================

for task_id, task in list(tasks.items()):
    status = task.get("status", "todo")
    agent_pid = task.get("agentPid")
    process_pid = task.get("processPid")
    timeout_min = task.get("timeoutMin", 25)
    started_epoch = task.get("startedEpoch") or task.get("createdEpoch", now)
    age_min = (now - started_epoch) // 60
    label = task.get("label", task_id)

    # ── AGENT_RUNNING: Check agent completion via exit-code file ────────
    if status == "agent_running":
        exit_code_file = f"{LOGS_DIR}/{task_id}-exit-code"

        if os.path.exists(exit_code_file):
            # Agent completed — exit-code file written on finish
            quality, output_size, detail = check_output_quality(task_id)

            if quality in ("success", "small"):
                print(f"DONE {task_id}: {age_min}min, {output_size}B")
                run_cmd(["bash", TASK_MGR, "transition", task_id, "done", "--exit-code", "0"])
                run_cmd(["bash", REPORT, task_id, "done"])
                # Link logs to Linear for debugging
                run_cmd(["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/link-logs-to-linear.sh", task_id])
                trigger_review_hook(task_id)
                completions += 1
                consec = {"count": 0, "task_ids": []}
            else:
                print(f"FAIL {task_id}: {age_min}min, {quality} ({detail[:100]})")
                run_cmd(["bash", TASK_MGR, "transition", task_id, "failed", "--exit-code", "1"])
                run_cmd(["bash", REPORT, task_id, "failed"])
                # Link logs to Linear for debugging
                run_cmd(["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/link-logs-to-linear.sh", task_id])
                failures += 1
                consec["count"] += 1
                consec["task_ids"].append(task_id)

                if consec["count"] > CONSECUTIVE_FAILURE_THRESHOLD:
                    task_list = ", ".join(consec["task_ids"][-5:])
                    send_alert(f":rotating_light: *{consec['count']} consecutive failures*\n{task_list}")

                # Requeue if < 2 retries
                if task.get("retries", 0) < 2:
                    run_cmd(["bash", TASK_MGR, "transition", task_id, "todo"])
                    requeue_task(task_id)

            changes = True
            continue

        # No exit-code yet — check timeout
        if age_min >= timeout_min:
            print(f"TIMEOUT {task_id}: {age_min}min >= {timeout_min}min")
            # Kill the agent process if PID is tracked
            if agent_pid and is_alive(agent_pid):
                run_cmd(["bash", KILL_TREE, str(agent_pid)])
            run_cmd(["bash", TASK_MGR, "transition", task_id, "timeout", "--exit-code", "-1"])
            run_cmd(["bash", REPORT, task_id, "timeout"])
            timeouts += 1
            consec["count"] += 1
            consec["task_ids"].append(task_id)
            if task.get("retries", 0) < 2:
                run_cmd(["bash", TASK_MGR, "transition", task_id, "todo"])
                requeue_task(task_id)
            changes = True
            continue

        # 80% timeout warning
        warned = task.get("warned80pct", False)
        warning_threshold = int(timeout_min * 0.8)
        if not warned and age_min >= warning_threshold:
            WARNING_DIR = "/Users/fonsecabc/.openclaw/tasks/timeout-warnings"
            os.makedirs(WARNING_DIR, exist_ok=True)
            remaining = timeout_min - age_min
            with open(f"{WARNING_DIR}/{task_id}.warn", "w") as wf:
                json.dump({"task_id": task_id, "remaining_min": remaining}, wf)
            task["warned80pct"] = True
            changes = True
            run_cmd(["bash", LINEAR_LOG, task_id,
                     f"[{ts}] Timeout warning: {age_min}/{timeout_min}min ({remaining}min left)", "progress"])
            print(f"WARN_80 {task_id}: {remaining}min left")

        # Auto-extend timeout if agent PID is still active
        extensions = task.get("extensions", 0)
        if extensions < 2 and age_min >= timeout_min - 2:
            if agent_pid and is_alive(agent_pid):
                new_timeout = timeout_min + 10
                task["timeoutMin"] = new_timeout
                task["extensions"] = extensions + 1
                changes = True
                print(f"EXTENDED {task_id}: {timeout_min} → {new_timeout}min")

        print(f"OK {task_id}: PID={agent_pid} {age_min}/{timeout_min}min")

    # ── EVAL_RUNNING: Check process PID ─────────────────────────────────
    elif status == "eval_running":
        if process_pid and is_alive(process_pid):
            # Still running — check timeout
            if age_min >= timeout_min:
                print(f"PROCESS_TIMEOUT {task_id}: {age_min}min >= {timeout_min}min")
                run_cmd(["bash", KILL_TREE, str(process_pid)])
                run_cmd(["bash", TASK_MGR, "transition", task_id, "timeout", "--exit-code", "-1"])
                run_cmd(["bash", LINEAR_LOG, task_id,
                         f"Process timed out after {age_min}min. Killed.", "blocked"])
                timeouts += 1
                changes = True
                continue

            if age_min > 0 and age_min % 10 == 0:
                print(f"PROCESS_OK {task_id}: PID={process_pid} {age_min}/{timeout_min}min")
            continue

        # Process dead — check results
        print(f"PROCESS_DONE {task_id}: PID {process_pid} dead after {age_min}min")
        metrics_path = task.get("metricsPath", "")
        result_path = task.get("resultPath", "")
        has_metrics = metrics_path and os.path.exists(metrics_path)
        has_result = result_path and os.path.exists(result_path)

        # For evals: try to find latest metrics
        if task.get("processType") == "eval" and not has_metrics:
            eval_runs = glob.glob("/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_*/metrics.json")
            if eval_runs:
                latest = max(eval_runs, key=os.path.getmtime)
                if os.path.getmtime(latest) > started_epoch:
                    task["metricsPath"] = latest
                    has_metrics = True
                    changes = True
                    print(f"  → Found metrics: {latest}")

        if has_metrics or has_result:
            exit_code = 0
            print(f"  → Results found: metrics={has_metrics} result={has_result}")
        else:
            exit_code = 1
            print(f"  → No results found")

        # Transition to callback_pending
        run_cmd(["bash", TASK_MGR, "transition", task_id, "callback_pending",
                 "--exit-code", str(exit_code)])
        changes = True

    # ── CALLBACK_PENDING: Dispatch callback agent ───────────────────────
    elif status == "callback_pending":
        print(f"CALLBACK {task_id}: dispatching")
        callback_type = task.get("callbackType", "dispatch")

        if callback_type == "dispatch":
            if dispatch_callback(task_id, task):
                changes = True
            # If dispatch failed (no slots), stays in callback_pending for next run

        elif callback_type == "notify":
            msg = f"Process {task.get('processType', 'unknown')} completed (exit={task.get('exitCode', '?')})"
            linear_status = "done" if task.get("exitCode", 1) == 0 else "blocked"
            run_cmd(["bash", LINEAR_LOG, task_id, msg, linear_status])
            run_cmd(["bash", TASK_MGR, "transition", task_id,
                     "done" if task.get("exitCode", 1) == 0 else "failed"])
            changes = True

        elif callback_type == "none":
            run_cmd(["bash", TASK_MGR, "transition", task_id,
                     "done" if task.get("exitCode", 1) == 0 else "failed"])
            changes = True

    # ── Skip todo, done, failed, blocked, timeout ───────────────────────
    # (no action needed)


# ============================================================================
# ORPHAN CLEANUP — Kill unregistered claude processes
# ============================================================================

registered_pids = set()
for t in tasks.values():
    for pid_key in ("agentPid", "processPid"):
        pid = t.get(pid_key)
        if pid:
            registered_pids.add(pid)

orphans = 0
try:
    r = subprocess.run(["pgrep", "-x", "claude"], capture_output=True, text=True)
    if r.returncode == 0:
        for line in r.stdout.strip().split("\n"):
            pid = int(line.strip())
            if pid in registered_pids:
                continue
            try:
                ppid_r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
                ppid = int(ppid_r.stdout.strip())
                parent_r = subprocess.run(["ps", "-o", "comm=", "-p", str(ppid)], capture_output=True, text=True)
                parent_comm = parent_r.stdout.strip()
                if "openclaw" in parent_comm:
                    continue  # Main Anton thread or native sub-agent managed by gateway
                age_r = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], capture_output=True, text=True)
                if int(age_r.stdout.strip()) > 300:
                    subprocess.run(["bash", KILL_TREE, str(pid)], capture_output=True, timeout=10)
                    print(f"ORPHAN killed: PID={pid}")
                    orphans += 1
            except Exception:
                pass
except Exception:
    pass


# ============================================================================
# CLEANUP — Remove old completed tasks (>24h)
# ============================================================================

cleanup_cutoff = now - 86400
for tid in list(tasks.keys()):
    t = tasks[tid]
    if t.get("status") in ("done", "failed", "timeout"):
        created = t.get("createdEpoch", 0)
        if created < cleanup_cutoff:
            # Don't delete from state directly — use task-manager to keep it clean
            # But DO remove from the in-memory view to avoid stale data
            pass  # cleanup command handles this


# ============================================================================
# PERSIST STATE (only if changes happened in-memory that weren't via task-manager.sh)
# ============================================================================

if changes:
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


# ============================================================================
# CONSECUTIVE FAILURE TRACKING
# ============================================================================

try:
    with open(CONSEC_FILE, "w") as f:
        json.dump(consec, f)
except Exception:
    pass


# ============================================================================
# HEALTH METRICS
# ============================================================================

os.makedirs("/Users/fonsecabc/.openclaw/workspace/metrics", exist_ok=True)

# Count current state
running = sum(1 for t in tasks.values() if t.get("status") == "agent_running")
eval_running = sum(1 for t in tasks.values() if t.get("status") == "eval_running")
pending = sum(1 for t in tasks.values() if t.get("status") == "callback_pending")
done_count = sum(1 for t in tasks.values() if t.get("status") == "done")
failed_count = sum(1 for t in tasks.values() if t.get("status") in ("failed", "timeout"))

total_tracked = len(tasks)
active_total = running + eval_running + pending

print(f"\n=== Supervisor: agents={running} evals={eval_running} pending={pending} done={completions} failed={failures} timeout={timeouts} callbacks={callbacks_dispatched} orphans={orphans} ===")

PYEOF
