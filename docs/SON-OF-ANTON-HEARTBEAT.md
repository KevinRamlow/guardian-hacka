# HEARTBEAT.md for Son of Anton (ClawdBot)

**Copy this to:** `~/workspace/HEARTBEAT.md` on 89.167.23.2

---

## Important: Separate Entities

**You (Son of Anton) and Anton are distinct entities.**

- **Share:** Architecture docs, objectives, state files (objective data)
- **Separate:** Memories, identity, experiences (subjective data)
- **Communication:** Send structured reports (JSON), not memory files
- **Your memories:** Stay in your own memory/ directory, never synced to Anton
- **Anton's memories:** Stay with Anton, you only read his state files

---

## Anton Auto-Loop Monitoring

### Every Heartbeat (5 min)

Check if it's time for an Anton status check:
- Guardian loop: every 4 hours (0, 4, 8, 12, 16, 20)
- Meta loop: once per day (9:00 BRT)
- Backlog check: every 4 hours (aligned with Guardian)

Track last check times in `anton-monitor-state.json`.

### Guardian Loop Check (every 4h)

```bash
# Get Anton's status
ANTON_STATUS=$(ssh caio@ANTON_MAC_IP "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status" 2>&1)

# Parse key metrics
GUARDIAN_BASELINE=$(echo "$ANTON_STATUS" | grep "Baseline:" | grep -o '[0-9.]*' | head -1)
META_SUCCESS=$(echo "$ANTON_STATUS" | grep "Agent success rate:" | grep -o '[0-9.]*' | head -1)
CYCLE=$(echo "$ANTON_STATUS" | grep "Cycle:" | grep -o '[0-9]*' | head -1)

# Check if changed since last check
LAST_BASELINE=$(cat anton-monitor-state.json 2>/dev/null | jq -r '.last_guardian_baseline // "79.3"')
LAST_CYCLE=$(cat anton-monitor-state.json 2>/dev/null | jq -r '.last_cycle // "0"')

if [[ "$CYCLE" != "$LAST_CYCLE" ]]; then
  # New cycle completed
  DELTA=$(echo "$GUARDIAN_BASELINE - $LAST_BASELINE" | bc)
  
  # Post to #replicants
  MESSAGE="[ANTON-STATUS] Cycle $CYCLE complete
Guardian: ${LAST_BASELINE}% → ${GUARDIAN_BASELINE}% (${DELTA:+"+"}${DELTA}pp)
Meta success: ${META_SUCCESS}%
Status: $(ssh caio@ANTON_MAC_IP 'launchctl list | grep anton | wc -l') loops active"
  
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "$MESSAGE"
  
  # Update state
  jq -n \
    --arg baseline "$GUARDIAN_BASELINE" \
    --arg meta "$META_SUCCESS" \
    --arg cycle "$CYCLE" \
    '{last_guardian_baseline: $baseline, last_meta_success: $meta, last_cycle: $cycle, last_check: (now|todate)}' \
    > anton-monitor-state.json
  
  # Generate structured report (not memory)
  REPORT_FILE="reports/son-monitoring-$(date +%Y-%m-%d-%H%M).json"
  mkdir -p reports
  
  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg baseline "$GUARDIAN_BASELINE" \
    --arg meta "$META_SUCCESS" \
    --arg cycle "$CYCLE" \
    --arg delta "$DELTA" \
    '{
      timestamp: $timestamp,
      observer: "son-of-anton",
      observations: {
        guardian_loop: {
          baseline_accuracy: ($baseline | tonumber),
          cycle_count: ($cycle | tonumber),
          last_delta: ($delta | tonumber),
          status: "healthy",
          last_run: $timestamp
        },
        meta_loop: {
          agent_success_rate: ($meta | tonumber),
          status: "healthy"
        }
      },
      alerts: [],
      actions_taken: [{action: "posted_status_to_replicants", result: "success", timestamp: $timestamp}],
      recommendations: []
    }' > "$REPORT_FILE"
fi
```

### Health Alerts

Check for problems:

```bash
# Check if loops are running
LOOP_COUNT=$(ssh caio@ANTON_MAC_IP "launchctl list | grep anton | wc -l" 2>&1)

if [[ "$LOOP_COUNT" -lt 2 ]]; then
  # Alert: loops not running
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "⚠️ [ANTON-HEALTH] Auto-loops offline! Expected 2, found $LOOP_COUNT"
fi

# Check for stagnation (no improvement in 3 cycles)
CYCLES_WITHOUT_IMPROVEMENT=$(jq -r '.cycles_without_improvement // 0' anton-monitor-state.json)

if [[ $CYCLES_WITHOUT_IMPROVEMENT -ge 3 ]]; then
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "⚠️ [ANTON-HEALTH] No improvement in 3 cycles. Check OBJECTIVES.md and logs."
fi

# Check agent success rate
if (( $(echo "$META_SUCCESS < 50" | bc -l) )); then
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "⚠️ [ANTON-HEALTH] Agent success rate critically low: ${META_SUCCESS}%"
fi
```

### Backlog Check (every 4h)

```bash
# Check Anton's Linear queue
TODO_COUNT=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issues(filter:{team:{key:{eq:\"CAI\"}},state:{name:{eq:\"Todo\"}}},first:1){nodes{id}}}"}' \
  | jq '.data.issues.nodes | length')

if [[ "$TODO_COUNT" -eq 0 ]]; then
  # Queue empty, generate backlog
  ssh caio@ANTON_MAC_IP "cd ~/.openclaw/workspace && bash scripts/backlog-generator.sh" 2>&1
  
  # Notify
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "[BACKLOG] Queue was empty, ran backlog generator"
fi
```

### Daily Summary (09:00 BRT)

```bash
# Only run if current hour is 9-10 and we haven't run today
LAST_SUMMARY_DATE=$(cat anton-monitor-state.json 2>/dev/null | jq -r '.last_summary_date // "1970-01-01"')
TODAY=$(date +%Y-%m-%d)

if [[ "$LAST_SUMMARY_DATE" != "$TODAY" ]] && [[ $(date +%H) -ge 9 ]] && [[ $(date +%H) -lt 10 ]]; then
  # Read states
  GUARDIAN_STATE=$(ssh caio@ANTON_MAC_IP "cat ~/.openclaw/workspace/.anton-auto-state.json" 2>/dev/null)
  META_STATE=$(ssh caio@ANTON_MAC_IP "cat ~/.openclaw/workspace/.anton-meta-state.json" 2>/dev/null)
  
  # Parse
  G_BASELINE=$(echo "$GUARDIAN_STATE" | jq -r '.baseline_accuracy')
  G_CYCLE=$(echo "$GUARDIAN_STATE" | jq -r '.cycle')
  M_SUCCESS=$(echo "$META_STATE" | jq -r '.agent_success_rate')
  M_CYCLE=$(echo "$META_STATE" | jq -r '.cycle')
  
  # Count commits
  COMMITS=$(ssh caio@ANTON_MAC_IP "cd ~/.openclaw/workspace/guardian-agents-api-real && git log --since='24 hours ago' --grep='AUTO-LOOP\|META-LOOP' --oneline | wc -l" 2>/dev/null)
  
  # Calculate ETA
  TARGET=87
  REMAINING=$(echo "$TARGET - $G_BASELINE" | bc)
  AVG_IMPROVEMENT=0.3  # pp per cycle
  CYCLES_NEEDED=$(echo "$REMAINING / $AVG_IMPROVEMENT" | bc)
  DAYS_NEEDED=$(echo "scale=1; $CYCLES_NEEDED / 6" | bc)  # 6 cycles per day
  
  # Post summary
  MESSAGE="📊 [DAILY-SUMMARY] Anton Auto-Loop Day Summary

Guardian Loop:
  - Baseline: ${G_BASELINE}% (target: 87%)
  - Cycles today: ~6
  - Auto-commits: $COMMITS

Meta Loop:
  - Agent success: ${M_SUCCESS}%
  - Cycle: $M_CYCLE

Progress: ${REMAINING}pp remaining → ETA: ${DAYS_NEEDED} days"
  
  clawdbot message send --channel slack --target C0AJTTFLN4X --message "$MESSAGE"
  
  # Update state
  jq '. + {last_summary_date: "'$TODAY'"}' anton-monitor-state.json > anton-monitor-state.tmp && mv anton-monitor-state.tmp anton-monitor-state.json
fi
```

### Reply HEARTBEAT_OK

If no actions taken, reply:
```
HEARTBEAT_OK
```

---

## Configuration Needed

Set these in ClawdBot config or environment:

```bash
ANTON_MAC_IP="<get from Caio>"
LINEAR_API_KEY="<key for CAI workspace>"
```

## Testing

Before deploying:
```bash
# Test SSH
ssh caio@$ANTON_MAC_IP "echo 'Connected!'"

# Test status command
ssh caio@$ANTON_MAC_IP "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status"

# Test state files
ssh caio@$ANTON_MAC_IP "cat ~/.openclaw/workspace/.anton-auto-state.json"
```

All should work without password (use SSH keys).
