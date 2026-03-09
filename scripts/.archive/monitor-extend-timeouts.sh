#!/bin/bash
# monitor-extend-timeouts.sh — Proactive timeout monitoring and extension
#
# Checks all running agents every 5-10min:
# - If agent >80% through timeout AND still actively working → extend +15min
# - Active = eval/child processes running, activity.jsonl updated recently, output growing
#
# Run via heartbeat or launchd every 5min

set -euo pipefail

REGISTRY="/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"

[ ! -f "$REGISTRY" ] && { echo "No registry found"; exit 0; }

# Parse registry and check each agent
python3 <<'EOF'
import json
import time
import subprocess
import os

registry_path = "/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
logs_dir = "/Users/fonsecabc/.openclaw/tasks/agent-logs"

with open(registry_path) as f:
    registry = json.load(f)

agents = registry.get('agents', {})
if not agents:
    exit(0)

now = time.time()
extensions = []

for task_id, data in agents.items():
    pid = data.get('pid')
    timeout_min = data.get('timeoutMin', 25)
    spawned_epoch = data.get('spawnedEpoch', now)
    
    elapsed_min = (now - spawned_epoch) / 60
    remaining_min = timeout_min - elapsed_min
    percent_elapsed = (elapsed_min / timeout_min) * 100 if timeout_min > 0 else 0
    
    # Only check agents >80% through timeout with <10min remaining
    if percent_elapsed < 80 or remaining_min > 10:
        continue
    
    # Check if agent is still active
    active_signals = []
    
    # 1. Check if PID still exists
    try:
        subprocess.run(['ps', '-p', str(pid)], check=True, capture_output=True)
        active_signals.append('pid_alive')
    except:
        continue  # PID dead, skip
    
    # 2. Check for child processes (eval, python, etc.)
    try:
        result = subprocess.run(['pgrep', '-P', str(pid)], capture_output=True, text=True)
        if result.stdout.strip():
            active_signals.append('child_processes')
    except:
        pass
    
    # 3. Check activity.jsonl mtime (updated in last 5min?)
    activity_file = f"{logs_dir}/{task_id}-activity.jsonl"
    if os.path.exists(activity_file):
        mtime = os.path.getmtime(activity_file)
        age_min = (now - mtime) / 60
        if age_min < 5:
            active_signals.append('activity_recent')
    
    # 4. Check output.log size growing (>100 bytes in last check)
    output_file = f"{logs_dir}/{task_id}-output.log"
    if os.path.exists(output_file):
        size = os.path.getsize(output_file)
        if size > 1000:  # Has meaningful output
            active_signals.append('output_exists')
    
    # If >=2 active signals → extend timeout
    if len(active_signals) >= 2:
        new_timeout = timeout_min + 15  # Add 15min
        extensions.append({
            'task_id': task_id,
            'old_timeout': timeout_min,
            'new_timeout': new_timeout,
            'elapsed_min': round(elapsed_min, 1),
            'remaining_min': round(remaining_min, 1),
            'signals': active_signals
        })
        
        # Update registry
        registry['agents'][task_id]['timeoutMin'] = new_timeout

# Write back registry if any extensions
if extensions:
    with open(registry_path, 'w') as f:
        json.dump(registry, f, indent=2)
    
    for ext in extensions:
        print(f"✅ Extended {ext['task_id']}: {ext['old_timeout']}min → {ext['new_timeout']}min")
        print(f"   Elapsed: {ext['elapsed_min']}min | Remaining: {ext['remaining_min']}min → {ext['remaining_min']+15}min")
        print(f"   Active signals: {', '.join(ext['signals'])}")
        
        # Log to Linear
        try:
            subprocess.run([
                'bash',
                '/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh',
                ext['task_id'],
                f"⏱️ Auto-extended timeout: {ext['old_timeout']}min → {ext['new_timeout']}min (agent still active: {', '.join(ext['signals'])})"
            ], check=False, capture_output=True)
        except:
            pass

EOF
