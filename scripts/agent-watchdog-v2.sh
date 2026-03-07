#!/bin/bash
# Agent Watchdog v2 — Single monitoring script replacing agent-monitor + completion-checker + kill-zombies
# Runs every 60s via cron
# Reads from agent-registry.json (single source of truth)
set -euo pipefail

REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
REGISTRY_FILE="/root/.openclaw/tasks/agent-registry.json"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOCKFILE="/tmp/agent-watchdog-v2.lock"
LOG="/root/.openclaw/tasks/agent-logs/master.log"

mkdir -p /root/.openclaw/tasks/agent-logs

log() { echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*" >> "$LOG"; }

# Lockfile
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Skipped: already running"; exit 0; }

# Ensure registry exists
bash "$REGISTRY" list > /dev/null 2>&1

NOW_EPOCH=$(date +%s)

# ── 1. Check registered agents ──
COMPLETIONS=0
TIMEOUTS=0
CLEANED=0

python3 << 'PYEOF'
import json, os, time, subprocess, sys

REGISTRY_FILE = "/root/.openclaw/tasks/agent-registry.json"
LOGGER = "/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG = "/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REGISTRY = "/root/.openclaw/workspace/scripts/agent-registry.sh"

now = int(time.time())

try:
    d = json.load(open(REGISTRY_FILE))
except:
    d = {"agents": {}, "maxConcurrent": 3}

agents = dict(d.get("agents", {}))
removals = []
completions = 0
timeouts = 0

for task_id, a in agents.items():
    pid = a.get("pid", 0)
    timeout_min = a.get("timeoutMin", 25)
    spawned_epoch = a.get("spawnedEpoch", now)
    age_min = (now - spawned_epoch) // 60
    label = a.get("label", task_id)

    # Check if process is alive
    alive = False
    try:
        os.kill(pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        alive = False

    if not alive:
        # Agent completed (or crashed) — check output log
        output_log = f"/root/.openclaw/tasks/agent-logs/{task_id}-output.log"
        output_size = 0
        if os.path.exists(output_log):
            output_size = os.path.getsize(output_log)

        if output_size > 100:
            # Has output — likely completed successfully
            print(f"✅ {task_id}: Completed (PID={pid}, {age_min}min, output={output_size}B)")
            subprocess.run([LOGGER, task_id, "complete", f"Agent finished after {age_min}min (output={output_size}B)"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"✅ [{time.strftime('%H:%M', time.gmtime())}] Agent completed after {age_min}min", "done"], capture_output=True)
            completions += 1
        else:
            # No output — likely crashed
            print(f"💀 {task_id}: Died with no output (PID={pid}, {age_min}min)")
            subprocess.run([LOGGER, task_id, "error", f"Agent died after {age_min}min with no output"], capture_output=True)
            subprocess.run([LINEAR_LOG, task_id, f"❌ [{time.strftime('%H:%M', time.gmtime())}] Agent died after {age_min}min (no output)", "blocked"], capture_output=True)

        removals.append(task_id)
        continue

    # Process is alive — check timeout
    if age_min >= timeout_min:
        print(f"⏱️  {task_id}: Timed out ({age_min}min >= {timeout_min}min limit) — killing PID {pid}")
        try:
            os.kill(pid, 9)
        except:
            pass

        # Also kill bridge if present
        bridge_pid = a.get("bridgePid", 0)
        if bridge_pid > 0:
            try:
                os.kill(bridge_pid, 9)
            except:
                pass

        subprocess.run([LOGGER, task_id, "timeout", f"Killed after {age_min}min (timeout={timeout_min}min)"], capture_output=True)
        subprocess.run([LINEAR_LOG, task_id, f"⏱️ [{time.strftime('%H:%M', time.gmtime())}] Agent timed out after {age_min}min — killed", "blocked"], capture_output=True)
        timeouts += 1
        removals.append(task_id)
        continue

    # Still running and within timeout
    print(f"🟢 {task_id}: Running (PID={pid}, {age_min}/{timeout_min}min)")

# Remove completed/timed-out entries
for task_id in removals:
    subprocess.run(["bash", REGISTRY, "remove", task_id], capture_output=True)

# ── 2. Kill orphan claude processes NOT in registry ──
registered_pids = set()
try:
    d2 = json.load(open(REGISTRY_FILE))
    for a in d2.get("agents", {}).values():
        registered_pids.add(a.get("pid", 0))
except:
    pass

orphans_killed = 0
try:
    result = subprocess.run(["pgrep", "-x", "claude"], capture_output=True, text=True)
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            pid = int(line.strip())
            if pid not in registered_pids:
                # Check age — only kill if > 5 min (give new spawns time to register)
                try:
                    age_result = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], capture_output=True, text=True)
                    age_s = int(age_result.stdout.strip())
                    if age_s > 300:
                        os.kill(pid, 9)
                        print(f"🧹 Killed orphan claude PID={pid} (age={age_s//60}min, not in registry)")
                        orphans_killed += 1
                except:
                    pass
except:
    pass

# Kill orphan bridge processes
try:
    result = subprocess.run(["pgrep", "-f", "claude-agent-acp"], capture_output=True, text=True)
    if result.returncode == 0:
        registered_bridge_pids = set()
        try:
            for a in d2.get("agents", {}).values():
                bp = a.get("bridgePid", 0)
                if bp > 0:
                    registered_bridge_pids.add(bp)
        except:
            pass

        for line in result.stdout.strip().split("\n"):
            if not line.strip():
                continue
            pid = int(line.strip())
            if pid not in registered_bridge_pids:
                try:
                    os.kill(pid, 9)
                    print(f"🧹 Killed orphan bridge PID={pid}")
                    orphans_killed += 1
                except:
                    pass
except:
    pass

# ── 3. Clean stale session store entries ──
SESSIONS_FILE = "/root/.openclaw/agents/claude/sessions/sessions.json"
try:
    sessions = json.load(open(SESSIONS_FILE))
    stale_cutoff = now * 1000 - (30 * 60 * 1000)  # 30 min
    cleaned = {k: v for k, v in sessions.items() if v.get("updatedAt", 0) > stale_cutoff}
    removed = len(sessions) - len(cleaned)
    if removed > 0:
        json.dump(cleaned, open(SESSIONS_FILE, "w"))
        print(f"🧹 Cleaned {removed} stale session store entries")
except:
    pass

# ── 4. Summary ──
alive_count = 0
try:
    d3 = json.load(open(REGISTRY_FILE))
    alive_count = len(d3.get("agents", {}))
except:
    pass

print(f"\n=== Watchdog Summary ===")
print(f"Running: {alive_count} | Completed: {completions} | Timed out: {timeouts} | Orphans killed: {orphans_killed}")
PYEOF
