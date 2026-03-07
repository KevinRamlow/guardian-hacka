#!/bin/bash
# Agent Watchdog v2 — Monitors registry, detects completions/timeouts, kills orphans
# Runs every 60s via cron. Single source: agent-registry.json
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
REGISTRY_FILE="/root/.openclaw/tasks/agent-registry.json"
LOCKFILE="/tmp/agent-watchdog-v2.lock"

mkdir -p /root/.openclaw/tasks/agent-logs

exec 200>"$LOCKFILE"
flock -n 200 || { echo "Skipped: locked"; exit 0; }

bash "$REGISTRY" list > /dev/null 2>&1

python3 << 'PYEOF'
import json, os, time, subprocess

REGISTRY_FILE = "/root/.openclaw/tasks/agent-registry.json"
LOGGER = "/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG = "/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REGISTRY = "/root/.openclaw/workspace/scripts/agent-registry.sh"

now = int(time.time())
ts = time.strftime("%H:%M", time.gmtime())

try:
    d = json.load(open(REGISTRY_FILE))
except Exception:
    d = {"agents": {}, "maxConcurrent": 3}

agents = dict(d.get("agents", {}))
removals = []
completions = timeouts = failures = 0

for task_id, a in agents.items():
    pid = a.get("pid", 0)
    timeout_min = a.get("timeoutMin", 25)
    age_min = (now - a.get("spawnedEpoch", now)) // 60
    label = a.get("label", task_id)

    try:
        os.kill(pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        alive = False

    if not alive:
        output_log = f"/root/.openclaw/tasks/agent-logs/{task_id}-output.log"
        output_size = os.path.getsize(output_log) if os.path.exists(output_log) else 0

        if output_size > 1:
            print(f"DONE {task_id}: {age_min}min, {output_size}B output")
            subprocess.run([LOGGER, task_id, "complete", f"Finished in {age_min}min ({output_size}B)"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Agent completed ({age_min}min)", "done"], capture_output=True)
            completions += 1
        else:
            print(f"[FAIL] {task_id}: {age_min}min, {output_size}B output (empty)")
            subprocess.run([LOGGER, task_id, "error", f"[FAIL] Died after {age_min}min, output={output_size}B (empty/invalid)"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"[{ts}] [FAIL] Agent produced {output_size}B output ({age_min}min)", "blocked"], capture_output=True)
            failures += 1

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
        subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Timed out at {age_min}min — killed", "blocked"], capture_output=True)
        timeouts += 1
        removals.append(task_id)
        continue

    print(f"OK {task_id}: PID={pid} {age_min}/{timeout_min}min")

for task_id in removals:
    subprocess.run(["bash", REGISTRY, "remove", task_id], capture_output=True)

# Kill orphan claude processes not in registry
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
                age_r = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], capture_output=True, text=True)
                if int(age_r.stdout.strip()) > 300:
                    os.kill(pid, 9)
                    print(f"ORPHAN killed: PID={pid}")
                    orphans += 1
            except Exception:
                pass
except Exception:
    pass

# Kill orphan ACP bridges
try:
    result = subprocess.run(["pgrep", "-f", "claude-agent-acp"], capture_output=True, text=True)
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                try:
                    os.kill(int(line.strip()), 9)
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

print(f"\n=== Watchdog: running={alive} done={completions} failed={failures} timeout={timeouts} orphans={orphans} ===")
PYEOF
