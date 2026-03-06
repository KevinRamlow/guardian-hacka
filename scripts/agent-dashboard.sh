#!/bin/bash
# Agent Dashboard - Quick status view of all running agents
# Shows: Linear task | agent label | runtime | last log time | status

set -e

LINEAR_API_KEY="${LINEAR_API_KEY:-[REDACTED]}"
TEAM_ID="b0bf6f0c-d989-42d2-9ada-3bb3abadec58"

echo "🦞 Anton Agent Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get running agents
AGENTS_JSON=$(openclaw subagents list --json 2>/dev/null || echo '{"active":[]}')

if [ "$(echo "$AGENTS_JSON" | jq -r '.active | length')" -eq 0 ]; then
    echo "✅ No active agents running"
    echo ""
    exit 0
fi

# For each running agent
echo "$AGENTS_JSON" | jq -r '.active[] | [.label, .runtime, .sessionKey] | @tsv' | while IFS=$'\t' read -r label runtime sessionKey; do
    # Extract task ID from label (e.g., "CAI-42-something" -> "CAI-42")
    TASK_ID=$(echo "$label" | grep -oP '\b(CAI-\d+)\b' | head -1 || echo "")
    
    # Get runtime in minutes
    RUNTIME_DISPLAY="$runtime"
    
    # Get last Linear log time (if we have task ID)
    LAST_LOG="unknown"
    if [ -n "$TASK_ID" ]; then
        # Query Linear for latest comment on this task
        QUERY="{\"query\":\"query{issues(filter:{identifier:{eq:\\\"$TASK_ID\\\"}}){nodes{comments(last:1){nodes{createdAt}}}}}\"}";
        LAST_COMMENT=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Authorization: $LINEAR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$QUERY" | jq -r '.data.issues.nodes[0].comments.nodes[0].createdAt // "none"')
        
        if [ "$LAST_COMMENT" != "none" ]; then
            # Calculate time since last log
            LAST_TS=$(date -d "$LAST_COMMENT" +%s 2>/dev/null || echo "0")
            NOW_TS=$(date +%s)
            DIFF_MIN=$(( (NOW_TS - LAST_TS) / 60 ))
            LAST_LOG="${DIFF_MIN}min ago"
        else
            LAST_LOG="no logs"
        fi
    fi
    
    # Status indicator based on runtime and last log
    STATUS="🟢"
    if [[ "$RUNTIME_DISPLAY" =~ ([0-9]+)m ]] && [ "${BASH_REMATCH[1]}" -gt 25 ]; then
        STATUS="🔴"
    elif [[ "$RUNTIME_DISPLAY" =~ ([0-9]+)m ]] && [ "${BASH_REMATCH[1]}" -gt 15 ]; then
        STATUS="🟡"
    fi
    
    # Print row
    printf "%s %-12s | %-25s | %8s | Last log: %s\n" "$STATUS" "${TASK_ID:-N/A}" "$label" "$RUNTIME_DISPLAY" "$LAST_LOG"
done

echo ""
echo "Legend: 🟢 Normal | 🟡 >15min | 🔴 >25min (check on it)"
