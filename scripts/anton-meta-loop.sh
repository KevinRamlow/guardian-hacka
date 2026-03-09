#!/bin/bash
# anton-meta-loop.sh - Meta-level self-improvement
# Anton improving Anton (orchestration, templates, spawn logic)

set -e

WORKSPACE="$HOME/.openclaw/workspace"
STATE_FILE="$WORKSPACE/.anton-meta-state.json"
LOG_FILE="$WORKSPACE/logs/anton-meta-loop.log"

mkdir -p "$WORKSPACE/logs"
exec >> "$LOG_FILE" 2>&1

echo ""
echo "=========================================="
echo "Anton Meta-Loop (Self-Improvement) - $(date)"
echo "=========================================="

# Read current meta baseline
if [[ -f "$STATE_FILE" ]]; then
  SUCCESS_RATE=$(jq -r '.agent_success_rate // "60"' "$STATE_FILE")
  AVG_TIME=$(jq -r '.avg_task_time // "25"' "$STATE_FILE")
  CYCLE=$(jq -r '.cycle // 0' "$STATE_FILE")
else
  SUCCESS_RATE="60"
  AVG_TIME="25"
  CYCLE=0
fi

CYCLE=$((CYCLE + 1))

echo "Meta Cycle: $CYCLE"
echo "Current agent success rate: $SUCCESS_RATE%"
echo "Current avg task time: ${AVG_TIME}min"

# Notify cycle start
bash "$WORKSPACE/scripts/notify-slack.sh" "[ANTON] Meta Loop Cycle $CYCLE starting (success rate: ${SUCCESS_RATE}%, avg time: ${AVG_TIME}min)"

# Calculate recent agent performance
echo ""
echo "=== Analyzing Recent Agent Performance ==="

RECENT_AGENTS=$(grep -E "DONE:|FAIL:" "$WORKSPACE/logs/watchdog.log" 2>/dev/null | tail -20 || echo "")
TOTAL=$(echo "$RECENT_AGENTS" | wc -l)
SUCCESS=$(echo "$RECENT_AGENTS" | grep "DONE:" | wc -l || echo "0")

if [[ $TOTAL -gt 0 ]]; then
  CURRENT_SUCCESS_RATE=$(echo "scale=1; $SUCCESS * 100 / $TOTAL" | bc)
  echo "Recent performance: $SUCCESS/$TOTAL = $CURRENT_SUCCESS_RATE%"
else
  CURRENT_SUCCESS_RATE="$SUCCESS_RATE"
  echo "No recent data, using baseline: $SUCCESS_RATE%"
fi

# Define meta-improvement hypotheses
echo ""
echo "=== Meta-Improvement Hypotheses ==="

META_HYPOTHESES=(
  "template-simplify:Simplify CLAUDE.md by removing redundant sections"
  "success-criteria:Add explicit success criteria to all task templates"
  "error-library:Build common-errors.md from recent failures"
  "codemap-expand:Expand guardian-agents-api.map.md with recent changes"
  "spawn-optimize:Reduce spawn overhead by batching Linear API calls"
)

# Pick 2 meta hypotheses for this cycle
SELECTED_META=($(shuf -e "${META_HYPOTHESES[@]}" -n 2))

echo "Selected meta-improvements:"
for i in "${!SELECTED_META[@]}"; do
  echo "  $((i+1)). ${SELECTED_META[$i]}"
done

# Spawn meta-improvement agents
echo ""
echo "=== Spawning Meta-Improvement Agents ==="

for HYPOTHESIS in "${SELECTED_META[@]}"; do
  LABEL=$(echo "$HYPOTHESIS" | cut -d: -f1)
  DESC=$(echo "$HYPOTHESIS" | cut -d: -f2)
  
  echo "Testing: $LABEL - $DESC"
  
  # Create meta task
  TASK_FILE="/tmp/anton-meta-task-$LABEL-$CYCLE.md"
  cat > "$TASK_FILE" << EOF
# Meta-Improvement Task: $LABEL (Cycle $CYCLE)

## Objective
$DESC

## Current Performance
- Agent success rate: $CURRENT_SUCCESS_RATE%
- Avg task completion time: ${AVG_TIME}min

## Target
Improve agent success rate by +5pp OR reduce avg time by 5min

## Instructions

1. **Analyze recent failures:**
   - Check \`~/.openclaw/tasks/agent-logs/*-stderr.log\` for patterns
   - Review watchdog.log for timeout/failure reasons
   - Identify common causes

2. **Implement hypothesis:**
   - Make targeted improvements to templates/scripts
   - Focus on: $LABEL

3. **Validate:**
   - Review last 10 agent runs
   - Check if changes would have prevented failures
   - Estimate success rate improvement

4. **Report format:**
   - Changes made: [list files modified]
   - Failure patterns addressed: [list]
   - Expected success rate: [X%]
   - Recommendation: [commit / test further / abandon]

## Success Criteria
- Clear improvement path identified
- Changes are backward-compatible
- No breaking changes to existing workflows

## Time Budget
20 minutes
EOF

  # Spawn meta-agent
  AGENT_ID="META-$CYCLE-$LABEL"
  
  bash "$WORKSPACE/scripts/spawn-agent.sh" \
    --task "$AGENT_ID" \
    --label "anton-meta:$LABEL" \
    --timeout 20 \
    --model "sonnet" \
    --file "$TASK_FILE" &
  
  echo "  Spawned: $AGENT_ID"
  sleep 5
done

echo ""
echo "Meta-agents spawned. Waiting for completion..."
sleep 1200  # 20 min

echo ""
echo "=== Collecting Meta Results ==="

IMPROVEMENTS=()

for HYPOTHESIS in "${SELECTED_META[@]}"; do
  LABEL=$(echo "$HYPOTHESIS" | cut -d: -f1)
  AGENT_ID="META-$CYCLE-$LABEL"
  OUTPUT_LOG="$HOME/.openclaw/tasks/agent-logs/${AGENT_ID}-output.log"
  
  if [[ -f "$OUTPUT_LOG" ]]; then
    echo "$LABEL:"
    
    # Extract recommendation
    RECOMMENDATION=$(grep -i "recommendation:" "$OUTPUT_LOG" | head -1 || echo "No recommendation")
    echo "  $RECOMMENDATION"
    
    if echo "$RECOMMENDATION" | grep -qi "commit"; then
      IMPROVEMENTS+=("$LABEL")
      echo "  ✅ Marking for commit"
    fi
  else
    echo "$LABEL: No output (agent failed)"
  fi
done

# Commit improvements
if [[ ${#IMPROVEMENTS[@]} -gt 0 ]]; then
  echo ""
  echo "=== Committing Meta Improvements ==="
  
  cd "$WORKSPACE"
  git add -A
  git commit -m "META-LOOP: Self-improvement cycle $CYCLE

Improvements:
$(printf '  - %s\n' "${IMPROVEMENTS[@]}")

Expected impact:
  - Higher agent success rate
  - Faster task completion
  - Better failure recovery

Meta-cycle: $CYCLE
" || echo "Nothing to commit or commit failed"
  
  # Update meta state
  jq -n \
    --arg success_rate "$CURRENT_SUCCESS_RATE" \
    --arg avg_time "$AVG_TIME" \
    --arg cycle "$CYCLE" \
    --argjson improvements "$(printf '%s\n' "${IMPROVEMENTS[@]}" | jq -R . | jq -s .)" \
    '{agent_success_rate: $success_rate, avg_task_time: $avg_time, cycle: ($cycle|tonumber), improvements: $improvements, last_run: (now|todate)}' \
    > "$STATE_FILE"
  
  # Notify
  bash "$WORKSPACE/scripts/notify-slack.sh" "🔧 Anton Meta-Loop: Self-improved (cycle $CYCLE). Changes: ${IMPROVEMENTS[*]}"
  
  echo "✅ Meta-improvements committed"
else
  echo ""
  echo "No meta-improvements ready for commit this cycle"
  
  # Update state (no changes)
  jq -n \
    --arg success_rate "$CURRENT_SUCCESS_RATE" \
    --arg avg_time "$AVG_TIME" \
    --arg cycle "$CYCLE" \
    '{agent_success_rate: $success_rate, avg_task_time: $avg_time, cycle: ($cycle|tonumber), last_run: (now|todate)}' \
    > "$STATE_FILE"
fi

echo ""
echo "=========================================="
echo "Anton Meta-Loop Complete"
echo "Next run: $(date -d '+1 day' 2>/dev/null || date -v+1d 2>/dev/null)"
echo "=========================================="
