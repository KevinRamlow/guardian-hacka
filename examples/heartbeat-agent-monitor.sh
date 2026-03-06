#!/bin/bash
# Example: Agent Health Monitoring in Heartbeat
# Add this to HEARTBEAT.md checks

set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
LINEAR_API_KEY="${LINEAR_API_KEY:-}"

# Get current subagents
SUBAGENTS_JSON=$(openclaw subagents list --json 2>/dev/null || echo '{"active":[]}')
ACTIVE_COUNT=$(echo "$SUBAGENTS_JSON" | jq -r '.active | length')

if [[ $ACTIVE_COUNT -eq 0 ]]; then
    echo "HEARTBEAT_OK - No active agents"
    exit 0
fi

echo "🔍 Checking $ACTIVE_COUNT active agents..."

# Check each active agent
echo "$SUBAGENTS_JSON" | jq -r '.active[] | @json' | while IFS= read -r agent_json; do
    LABEL=$(echo "$agent_json" | jq -r '.label')
    RUNTIME_MS=$(echo "$agent_json" | jq -r '.runtimeMs')
    RUNTIME_MIN=$(echo "scale=0; $RUNTIME_MS / 1000 / 60" | bc)
    
    # Extract task ID
    TASK_ID=$(echo "$LABEL" | grep -oP 'CAI-\d+' || echo "")
    
    if [[ -z "$TASK_ID" ]]; then
        echo "⚠️  Agent $LABEL has no task ID - skipping"
        continue
    fi
    
    # Check if frozen (>30 min)
    if [[ $RUNTIME_MIN -gt 30 ]]; then
        echo "🚨 FROZEN AGENT DETECTED: $LABEL"
        echo "   Runtime: ${RUNTIME_MIN}min"
        echo "   Task: $TASK_ID"
        
        # Query Linear for last update
        if [[ -n "$LINEAR_API_KEY" ]]; then
            LAST_COMMENT=$(curl -s -X POST https://api.linear.app/graphql \
                -H "Authorization: $LINEAR_API_KEY" \
                -H "Content-Type: application/json" \
                -d "{\"query\":\"query{issue(id:\\\"$TASK_ID\\\"){comments(first:1 orderBy:createdAt){nodes{createdAt}}}}\"}" \
                | jq -r '.data.issue.comments.nodes[0].createdAt // "unknown"')
            
            if [[ "$LAST_COMMENT" != "unknown" ]]; then
                COMMENT_AGE=$(( ($(date +%s) - $(date -d "$LAST_COMMENT" +%s)) / 60 ))
                echo "   Last Linear update: ${COMMENT_AGE}min ago"
                
                if [[ $COMMENT_AGE -gt 15 ]]; then
                    echo "   ⚠️  Stale logs! Needs steering."
                    # Auto-steer logic here
                fi
            fi
        fi
        
        echo ""
    elif [[ $RUNTIME_MIN -gt 20 ]]; then
        echo "⏱️  Long-running: $LABEL (${RUNTIME_MIN}min)"
    else
        echo "✅ $LABEL (${RUNTIME_MIN}min)"
    fi
done

echo ""
echo "Agent health check complete."
