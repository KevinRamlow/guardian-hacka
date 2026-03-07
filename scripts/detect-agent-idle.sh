#!/bin/bash
# Detect if an agent is idle/stuck based on log activity
# Usage: detect-agent-idle.sh <TASK_ID>
# Output: one of:
#   idle_no_output    — output.log unchanged >5min (no new output being written)
#   idle_no_activity  — activity.jsonl unchanged >3min (no tool calls or events)
#   loop_same_error   — same error repeated 10+ times in last 20 events
#   active            — agent appears to be working normally
#
# Only considers agents older than 5 min to avoid false positives on startup.

TASK_ID="${1:?Usage: detect-agent-idle.sh <TASK_ID>}"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"

python3 - "$TASK_ID" "$LOGS_DIR" << 'PYEOF'
import json, os, sys, time

TASK_ID = sys.argv[1]
LOGS_DIR = sys.argv[2]
now = time.time()

output_log   = f"{LOGS_DIR}/{TASK_ID}-output.log"
activity_log = f"{LOGS_DIR}/{TASK_ID}-activity.jsonl"

IDLE_OUTPUT_SECS   = 600  # 10 min: output.log not growing (increased from 5min for long setup tasks)
IDLE_ACTIVITY_SECS = 600  # 10 min: no events in activity.jsonl (increased from 3min - setup can be long)
MIN_AGE_SECS = 600  # Only check agents older than 10min (avoid false positives on startup)
ERROR_LOOP_THRESHOLD = 10  # same error N+ times in last 20 events

# Check agent age first - if too young, always return active
agent_birth_time = None
for log_file in [output_log, activity_log]:
    if os.path.exists(log_file):
        birth = os.path.getctime(log_file)
        if agent_birth_time is None or birth < agent_birth_time:
            agent_birth_time = birth

if agent_birth_time:
    agent_age = now - agent_birth_time
    if agent_age < MIN_AGE_SECS:
        print("active")  # Too young to judge
        sys.exit(0)

def check_error_loop(activity_log):
    try:
        with open(activity_log) as f:
            lines = f.readlines()
        recent = lines[-20:]
        error_summaries = []
        for line in recent:
            try:
                event = json.loads(line)
                summary = event.get("_summary", "")
                if summary.startswith("ERROR:"):
                    error_summaries.append(summary)
            except Exception:
                pass
        if len(error_summaries) >= ERROR_LOOP_THRESHOLD:
            unique_errors = set(error_summaries)
            if len(unique_errors) <= 2:  # allow minor variation
                return True
    except Exception:
        pass
    return False

# Check 1: activity.jsonl unchanged > 3min (strongest signal — no events at all)
if os.path.exists(activity_log):
    activity_age = now - os.path.getmtime(activity_log)
    if activity_age > IDLE_ACTIVITY_SECS:
        print("idle_no_activity")
        sys.exit(0)
    # Check error loop even when activity is recent
    if check_error_loop(activity_log):
        print("loop_same_error")
        sys.exit(0)
else:
    # No activity file yet — not enough info, consider active
    print("active")
    sys.exit(0)

# Check 2: output.log unchanged > 5min
if os.path.exists(output_log):
    output_age = now - os.path.getmtime(output_log)
    if output_age > IDLE_OUTPUT_SECS:
        # Only flag if activity.jsonl is also old (> 2min)
        if activity_age > 120:
            print("idle_no_output")
            sys.exit(0)

print("active")
PYEOF
