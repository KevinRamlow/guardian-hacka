#!/bin/bash
# Agent Watchdog v2 — Monitors registry, detects completions/timeouts, kills orphans
# Runs every 60s via cron. Single source: agent-registry.json
# v2.1: Re-queues failed agents, validates output content, logs stderr
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
REGISTRY_FILE="/root/.openclaw/tasks/agent-registry.json"
LOCKFILE="/tmp/agent-watchdog-v2.lock"

mkdir -p /root/.openclaw/tasks/agent-logs

exec 200>"$LOCKFILE"
flock -n 200 || { echo "Skipped: locked"; exit 0; }

bash "$REGISTRY" list > /dev/null 2>&1

# Source Linear API key for re-queue
source /root/.openclaw/workspace/.env.linear 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time, subprocess, re

REGISTRY_FILE = "/root/.openclaw/tasks/agent-registry.json"
LOGGER = "/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG = "/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REGISTRY = "/root/.openclaw/workspace/scripts/agent-registry.sh"
LOGS_DIR = "/root/.openclaw/tasks/agent-logs"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")

# Minimum output size to count as real work (not just an error message)
MIN_OUTPUT_BYTES = 100

# Patterns that indicate a failed agent even with output
FAILURE_PATTERNS = [
    r"permission.*denied",
    r"not allowed",
    r"blocked",
    r"I need.*approval",
    r"I'm unable to",
    r"I cannot",
    r"access denied",
    r"authentication.*failed",
    r"EACCES",
]

now = int(time.time())
ts = time.strftime("%H:%M", time.gmtime())

try:
    d = json.load(open(REGISTRY_FILE))
except Exception:
    d = {"agents": {}, "maxConcurrent": 3}

agents = dict(d.get("agents", {}))
removals = []
completions = timeouts = failures = requeued = 0


def requeue_task(task_id):
    """Move task back to Todo in Linear for retry."""
    global requeued
    if not LINEAR_API_KEY:
        return
    try:
        # Get the issue by identifier
        query = f'{{issues(filter:{{identifier:{{eq:"{task_id}"}}}},first:1){{nodes{{id}}}}}}'
        result = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": query})],
            capture_output=True, text=True, timeout=10
        )
        data = json.loads(result.stdout)
        nodes = data.get("data", {}).get("issues", {}).get("nodes", [])
        if not nodes:
            return

        issue_id = nodes[0]["id"]

        # Get Todo state ID
        state_query = '{workflowStates(filter:{name:{eq:"Todo"},team:{key:{eq:"CAI"}}},first:1){nodes{id}}}'
        result2 = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": state_query})],
            capture_output=True, text=True, timeout=10
        )
        data2 = json.loads(result2.stdout)
        state_nodes = data2.get("data", {}).get("workflowStates", {}).get("nodes", [])
        if not state_nodes:
            return

        state_id = state_nodes[0]["id"]

        # Update issue to Todo
        mutation = f'mutation{{issueUpdate(id:"{issue_id}",input:{{stateId:"{state_id}"}}){{success}}}}'
        subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": mutation})],
            capture_output=True, text=True, timeout=10
        )
        requeued += 1
        print(f"  REQUEUED {task_id} → Todo")
    except Exception as e:
        print(f"  REQUEUE FAILED {task_id}: {e}")


def check_output_quality(task_id):
    """Check if agent output represents real work or a failure."""
    output_log = f"{LOGS_DIR}/{task_id}-output.log"
    stderr_log = f"{LOGS_DIR}/{task_id}-stderr.log"

    output_size = os.path.getsize(output_log) if os.path.exists(output_log) else 0
    stderr_size = os.path.getsize(stderr_log) if os.path.exists(stderr_log) else 0

    # No output at all = definite failure
    if output_size < 2:
        stderr_msg = ""
        if stderr_size > 0:
            try:
                with open(stderr_log) as f:
                    stderr_msg = f.read(500)
            except:
                pass
        return "empty", output_size, stderr_msg

    # Small output = likely just an error message
    if output_size < MIN_OUTPUT_BYTES:
        try:
            with open(output_log) as f:
                content = f.read()
            for pattern in FAILURE_PATTERNS:
                if re.search(pattern, content, re.IGNORECASE):
                    return "blocked", output_size, f"Pattern match: {pattern}"
        except:
            pass
        return "small", output_size, ""

    # Larger output but check for failure patterns in first 500 bytes
    try:
        with open(output_log) as f:
            head = f.read(500)
        for pattern in FAILURE_PATTERNS:
            if re.search(pattern, head, re.IGNORECASE):
                return "blocked", output_size, f"Pattern match: {pattern}"
    except:
        pass

    return "success", output_size, ""


for task_id, a in agents.items():
    pid = a.get("pid", 0)
    timeout_min = a.get("timeoutMin", 25)
    age_min = (now - a.get("spawnedEpoch", now)) // 60
    label = a.get("label", task_id)
    retries = a.get("retries", 0)

    try:
        os.kill(pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        alive = False

    if not alive:
        status, output_size, detail = check_output_quality(task_id)

        if status == "success":
            print(f"DONE {task_id}: {age_min}min, {output_size}B output")
            subprocess.run([LOGGER, task_id, "complete", f"Finished in {age_min}min ({output_size}B)"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Agent completed ({age_min}min, {output_size}B)", "done"], capture_output=True)
            completions += 1

        elif status == "small":
            # Small but no failure patterns — count as done but flag it
            print(f"DONE? {task_id}: {age_min}min, {output_size}B output (small, review needed)")
            subprocess.run([LOGGER, task_id, "complete", f"Finished in {age_min}min ({output_size}B) — small output, review needed"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Agent completed ({age_min}min, {output_size}B) — small output, review", "done"], capture_output=True)
            completions += 1

        else:
            # Empty or blocked — FAIL and re-queue
            fail_reason = f"output={output_size}B"
            if detail:
                fail_reason += f" ({detail[:200]})"

            print(f"[FAIL] {task_id}: {age_min}min, {fail_reason}")
            subprocess.run([LOGGER, task_id, "error", f"[FAIL] Died after {age_min}min, {fail_reason}"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"[{ts}] [FAIL] {fail_reason}. Re-queuing.", "blocked"], capture_output=True)
            failures += 1

            # Re-queue to Todo if not retried too many times (max 2 retries)
            if retries < 2:
                requeue_task(task_id)

        removals.append(task_id)
        continue

    if age_min >= timeout_min:
        print(f"TIMEOUT {task_id}: {age_min}min >= {timeout_min}min — killing PID {pid}")
        try:
            os.kill(pid, 9)
        except Exception:
            pass
        bridge = a.get("bridgePid", 0)
        if bridge > 0:
            try:
                os.kill(bridge, 9)
            except Exception:
                pass

        subprocess.run([LOGGER, task_id, "timeout", f"Killed at {age_min}min (limit={timeout_min}min)"], capture_output=True)
        subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Timed out at {age_min}min — killed. Re-queuing.", "blocked"], capture_output=True)
        timeouts += 1

        # Re-queue timed out tasks too
        requeue_task(task_id)

        removals.append(task_id)
        continue

    print(f"OK {task_id}: PID={pid} {age_min}/{timeout_min}min")

for task_id in removals:
    subprocess.run(["bash", REGISTRY, "remove", task_id], capture_output=True)

# Kill orphan claude processes not in registry (but spare gateway's main thread)
registered_pids = set()
try:
    d2 = json.load(open(REGISTRY_FILE))
    registered_pids = {a["pid"] for a in d2.get("agents", {}).values()}
except Exception:
    pass

orphans = 0
try:
    result = subprocess.run(["pgrep", "-x", "claude"], capture_output=True, text=True)
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            pid = int(line.strip())
            if pid in registered_pids:
                continue
            try:
                # Check if this is the gateway's main thread (PPID is openclaw-gateway)
                ppid_r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
                ppid = int(ppid_r.stdout.strip())
                # Check if parent is openclaw-gateway
                parent_r = subprocess.run(["ps", "-o", "comm=", "-p", str(ppid)], capture_output=True, text=True)
                if "openclaw" in parent_r.stdout.strip():
                    # This is the main Anton thread — DO NOT KILL
                    continue

                age_r = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], capture_output=True, text=True)
                if int(age_r.stdout.strip()) > 300:
                    os.kill(pid, 9)
                    print(f"ORPHAN killed: PID={pid}")
                    orphans += 1
            except Exception:
                pass
except Exception:
    pass

# Clean stale session store
try:
    sf = "/root/.openclaw/agents/claude/sessions/sessions.json"
    sessions = json.load(open(sf))
    cutoff = now * 1000 - 1800000
    cleaned = {k: v for k, v in sessions.items() if v.get("updatedAt", 0) > cutoff}
    if len(cleaned) < len(sessions):
        json.dump(cleaned, open(sf, "w"))
except Exception:
    pass

# Summary
alive = 0
try:
    alive = len(json.load(open(REGISTRY_FILE)).get("agents", {}))
except Exception:
    pass

print(f"\n=== Watchdog: running={alive} done={completions} failed={failures} timeout={timeouts} requeued={requeued} orphans={orphans} ===")
PYEOF
