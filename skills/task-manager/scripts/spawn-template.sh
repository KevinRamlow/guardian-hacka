#!/bin/bash
# Spawn Template Helper
# Generates standardized spawn descriptions with logging instructions

set -e

TASK_ID="$1"
TIMEOUT="${2:-15}"
TASK_DESC="$3"

if [ -z "$TASK_ID" ] || [ -z "$TASK_DESC" ]; then
    echo "Usage: $0 <CAI-XX> <timeout-minutes> <task-description>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 CAI-42 15 'Implement archetype standardization in severity_agent.py'" >&2
    exit 1
fi

# Generate spawn description with logging instructions
cat << EOF
## Task Context
- **Linear Task:** $TASK_ID
- **Timeout:** $TIMEOUT minutes

## Logging (MANDATORY)
Read /root/.openclaw/workspace/CLAUDE.md for full logging instructions.

Use this script: /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh

**Log on:**
- Start: \`linear-log.sh $TASK_ID "🚀 Starting: [brief]" progress\`
- Progress (every 5-10 min): \`linear-log.sh $TASK_ID "📍 [what you completed]"\`
- Done: \`linear-log.sh $TASK_ID "✅ Done: [summary]" done\`
- Failed: \`linear-log.sh $TASK_ID "❌ Failed: [reason]" blocked\`

**Keep logs SHORT** - think application logs, not reports.

## Task
$TASK_DESC
EOF
