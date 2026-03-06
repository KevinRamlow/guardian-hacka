#!/usr/bin/env bash
# spawn-and-log.sh - Batch spawn + log operation
# Usage: spawn-and-log.sh CAI-XX "task description" [timeout_min] [runtime]

set -e

TASK_ID="$1"
DESCRIPTION="$2"
TIMEOUT="${3:-15}"
RUNTIME="${4:-subagent}"

if [[ -z "$TASK_ID" ]] || [[ -z "$DESCRIPTION" ]]; then
    echo "Usage: spawn-and-log.sh CAI-XX \"task description\" [timeout_min] [runtime]"
    exit 1
fi

# Log spawn
bash "$(dirname "$0")/linear-log.sh" "$TASK_ID" "🚀 [$(date -u +%H:%M) UTC] Spawning: $DESCRIPTION (${TIMEOUT}min, $RUNTIME)" progress

# Return spawn template
cat <<EOF
sessions_spawn:
  runtime: "$RUNTIME"
  label: "${TASK_ID}-${DESCRIPTION// /-}"
  timeout: $((TIMEOUT * 60))
  description: |
    ## Task Context
    - **Linear Task:** $TASK_ID
    - **Timeout:** ${TIMEOUT} minutes
    
    ## Logging
    Log to: /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh $TASK_ID "message"
    
    ## Task
    $DESCRIPTION
EOF
