#!/bin/bash
# Agent Status — Single source of truth across Linear, Registry, and Processes
# Shows mismatches and optionally fixes them with --sync
set -euo pipefail

REGISTRY_FILE="/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
SYNC_MODE="${1:-}"

source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null
source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null

export AGENT_STATUS_SYNC="$SYNC_MODE"

python3 << 'PYEOF'
import json, os, sys, subprocess, time

REGISTRY_FILE = "/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
REGISTRY = "/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
LINEAR_LOG = "/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR = "/Users/fonsecabc/.openclaw/tasks/agent-logs"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
SYNC = os.environ.get("AGENT_STATUS_SYNC") == "--sync"

now = int(time.time())

# 1. Get registry state
try:
    reg = json.load(open(REGISTRY_FILE))
except:
    reg = {"agents": {}, "maxConcurrent": 3}

# 2. Get Linear state (Todo + In Progress + Blocked)
linear_tasks = {}
if LINEAR_API_KEY:
    try:
        r = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", '{"query":"query{issues(filter:{team:{key:{eq:\\"CAI\\"}},state:{name:{in:[\\"Todo\\",\\"In Progress\\",\\"Blocked\\"]}}},first:30,orderBy:updatedAt){nodes{id identifier title state{name}}}}"}'],
            capture_output=True, text=True, timeout=10
        )
        data = json.loads(r.stdout)
        for n in data.get("data", {}).get("issues", {}).get("nodes", []):
            linear_tasks[n["identifier"]] = {
                "id": n["id"],
                "title": n["title"][:50],
                "state": n["state"]["name"],
            }
    except Exception as e:
        print(f"  Linear API error: {e}")

# 3. Check actual running processes
running_pids = set()
try:
    r = subprocess.run(["pgrep", "-f", "claude --print|claude --danger"], capture_output=True, text=True)
    if r.returncode == 0:
        running_pids = {int(p.strip()) for p in r.stdout.strip().split("\n") if p.strip()}
except:
    pass

# Also check for sub-agent claude processes (not main thread)
try:
    r = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "claude --print" in line or ("claude --dangerously" in line and "--teammate-mode" not in line):
            parts = line.split()
            running_pids.add(int(parts[1]))
except:
    pass

# 4. Build unified view
print("=" * 70)
print(f"{'Task':<10} {'Linear':<14} {'Registry':<12} {'Process':<10} {'Issue'}")
print("-" * 70)

all_tasks = set(list(linear_tasks.keys()) + list(reg.get("agents", {}).keys()))
issues = []

for tid in sorted(all_tasks):
    lin = linear_tasks.get(tid, {})
    lin_state = lin.get("state", "-")

    agent = reg.get("agents", {}).get(tid)
    reg_state = "-"
    pid = 0
    if agent:
        pid = agent.get("pid", 0)
        reg_state = "registered"

    proc_state = "-"
    if pid and pid in running_pids:
        proc_state = "alive"
    elif pid:
        proc_state = "dead"

    # Detect mismatches
    issue = ""
    if lin_state == "In Progress" and reg_state == "-":
        issue = "LINEAR=InProgress but no agent"
        issues.append((tid, "orphan_in_progress", lin))
    elif lin_state == "In Progress" and proc_state == "dead":
        issue = "LINEAR=InProgress but process dead"
        issues.append((tid, "dead_in_progress", lin))
    elif reg_state == "registered" and proc_state == "dead":
        issue = "Registry has dead PID"
        issues.append((tid, "dead_registry", agent))
    elif lin_state == "Todo" and reg_state == "registered":
        issue = "LINEAR=Todo but agent running?"
        issues.append((tid, "todo_but_running", lin))

    print(f"{tid:<10} {lin_state:<14} {reg_state:<12} {proc_state:<10} {issue}")

print("-" * 70)

# Summary
reg_count = len(reg.get("agents", {}))
lin_ip = sum(1 for t in linear_tasks.values() if t["state"] == "In Progress")
lin_todo = sum(1 for t in linear_tasks.values() if t["state"] == "Todo")
lin_blocked = sum(1 for t in linear_tasks.values() if t["state"] == "Blocked")
actual = len(running_pids)

print(f"\nLinear: {lin_ip} in-progress, {lin_todo} todo, {lin_blocked} blocked")
print(f"Registry: {reg_count} agents")
print(f"Processes: {actual} claude sub-agents running")

if issues:
    print(f"\n⚠️  {len(issues)} MISMATCHES DETECTED")

    if SYNC:
        print("\n--- SYNCING ---")
        # Get workflow state IDs
        todo_state_id = None
        blocked_state_id = None
        try:
            r = subprocess.run(
                ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
                 "-H", f"Authorization: {LINEAR_API_KEY}",
                 "-H", "Content-Type: application/json",
                 "-d", '{"query":"{workflowStates(filter:{team:{key:{eq:\\"CAI\\"}}},first:10){nodes{id name}}}"}'],
                capture_output=True, text=True, timeout=10
            )
            states = json.loads(r.stdout).get("data", {}).get("workflowStates", {}).get("nodes", [])
            for s in states:
                if s["name"] == "Todo": todo_state_id = s["id"]
                if s["name"] == "Blocked": blocked_state_id = s["id"]
        except:
            pass

        for tid, itype, data in issues:
            if itype in ("orphan_in_progress", "dead_in_progress"):
                # Move to Blocked in Linear
                if blocked_state_id and data.get("id"):
                    subprocess.run(
                        ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
                         "-H", f"Authorization: {LINEAR_API_KEY}",
                         "-H", "Content-Type: application/json",
                         "-d", json.dumps({"query": f'mutation{{issueUpdate(id:"{data["id"]}",input:{{stateId:"{blocked_state_id}"}}){{success}}}}'})],
                        capture_output=True, timeout=10
                    )
                    print(f"  {tid}: Linear → Blocked (no agent running)")

            elif itype == "dead_registry":
                # Remove from registry
                subprocess.run(["bash", REGISTRY, "remove", tid], capture_output=True)
                print(f"  {tid}: Removed dead entry from registry")
    else:
        print("Run with --sync to fix mismatches")
else:
    print("\n✅ All views in sync")
PYEOF
