#!/bin/bash
# system-health-check.sh - Proactive system health monitoring
# Anton runs this periodically to detect and fix issues autonomously

LOGS_DIR="/root/.openclaw/tasks/agent-logs"
REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"

# Check 1: Agent success rate last 30min
check_success_rate() {
  local completed=$(find "$LOGS_DIR" -name "CAI-*-output.log" -mmin -30 -exec wc -c {} + 2>/dev/null | awk '$1 > 100' | wc -l)
  local total=$(find "$LOGS_DIR" -name "CAI-*-output.log" -mmin -30 | wc -l)
  
  if [ "$total" -gt 5 ] && [ "$completed" -lt $((total / 2)) ]; then
    echo "WARN: Low success rate - $completed/$total agents completed in last 30min"
    return 1
  fi
  return 0
}

# Check 2: Auto-queue repeated failures
check_auto_queue_failures() {
  local stuck_task=$(tail -100 "$LOGS_DIR/auto-queue.log" 2>/dev/null | grep "FAIL:" | awk '{print $2}' | sort | uniq -c | sort -rn | head -1)
  local count=$(echo "$stuck_task" | awk '{print $1}')
  
  if [ "$count" -gt 5 ]; then
    local task_id=$(echo "$stuck_task" | awk '{print $2}')
    echo "WARN: Task $task_id failing repeatedly ($count times)"
    return 1
  fi
  return 0
}

# Check 3: Orphaned agents (running >45min)
check_stuck_agents() {
  local stuck=$(bash "$REGISTRY" list 2>/dev/null | grep -E "[4-9][0-9]/25min|[0-9]{3}/25min")
  
  if [ -n "$stuck" ]; then
    echo "WARN: Agents stuck >40min detected"
    echo "$stuck"
    return 1
  fi
  return 0
}

# Check 4: Watchdog timeouts rate
check_timeout_rate() {
  local timeouts=$(grep "TIMEOUT" "$LOGS_DIR/watchdog.log" 2>/dev/null | wc -l)
  local completions=$(grep "DONE" "$LOGS_DIR/watchdog.log" 2>/dev/null | wc -l)
  local total=$((timeouts + completions))
  
  if [ "$total" -gt 10 ] && [ $((timeouts * 100 / total)) -gt 30 ]; then
    echo "WARN: High timeout rate - $timeouts/$total (>30%)"
    return 1
  fi
  return 0
}

# Run all checks
issues=0
check_success_rate || ((issues++))
check_auto_queue_failures || ((issues++))
check_stuck_agents || ((issues++))
check_timeout_rate || ((issues++))

if [ "$issues" -eq 0 ]; then
  echo "OK: All health checks passed"
  exit 0
else
  echo "ISSUES: $issues health check(s) failed"
  exit 1
fi
