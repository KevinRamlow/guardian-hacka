#!/bin/bash
# alert-dedup.sh — Deduplicate alerts with TTL-based cooldown
#
# Usage: bash scripts/alert-dedup.sh <event-key> <cooldown-seconds> <message>
#
# Returns: exit 0 = send alert (not a duplicate), exit 1 = suppress (duplicate within cooldown)
#
# Example:
#   if bash scripts/alert-dedup.sh "done:AUTO-123" 300 "Task AUTO-123 completed"; then
#     send_slack_alert "$message"
#   fi
#
set -euo pipefail

COOLDOWN_FILE="/Users/fonsecabc/.openclaw/workspace/metrics/alert-cooldown.json"
EVENT_KEY="${1:?Event key required (e.g., done:AUTO-123)}"
COOLDOWN_SEC="${2:-300}"  # default 5 min cooldown
MESSAGE="${3:-}"

mkdir -p "$(dirname "$COOLDOWN_FILE")"

# Atomic read-check-write
python3 << PYEOF
import json, time, sys, os

COOLDOWN_FILE = "$COOLDOWN_FILE"
EVENT_KEY = """$EVENT_KEY"""
COOLDOWN_SEC = int($COOLDOWN_SEC)

now = int(time.time())

# Load existing cooldowns
try:
    with open(COOLDOWN_FILE) as f:
        cooldowns = json.load(f)
except Exception:
    cooldowns = {}

# Clean expired entries (prevent file growth)
cooldowns = {k: v for k, v in cooldowns.items() if now - v < 86400}  # 24h max

# Check if event is in cooldown
last_sent = cooldowns.get(EVENT_KEY, 0)
elapsed = now - last_sent

if elapsed < COOLDOWN_SEC:
    remaining = COOLDOWN_SEC - elapsed
    print(f"SUPPRESSED: {EVENT_KEY} (sent {elapsed}s ago, cooldown {remaining}s remaining)", file=sys.stderr)
    sys.exit(1)

# Not in cooldown — record and allow
cooldowns[EVENT_KEY] = now
with open(COOLDOWN_FILE, "w") as f:
    json.dump(cooldowns, f, indent=2)

print(f"ALLOWED: {EVENT_KEY}")
sys.exit(0)
PYEOF
