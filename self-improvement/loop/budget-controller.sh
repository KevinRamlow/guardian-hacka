#!/bin/bash
# Budget controller for self-improvement system
# Tracks spend and enforces limits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET_FILE="$SCRIPT_DIR/budget-status.json"

# Estimate cost from token usage (rough approximation)
# Input tokens: ~$0.003/1K, Output tokens: ~$0.015/1K (Claude Sonnet 4)
estimate_cost() {
  local input_tokens=$1
  local output_tokens=$2
  echo "scale=4; ($input_tokens * 0.003 / 1000) + ($output_tokens * 0.015 / 1000)" | bc
}

# Get current spend
get_spend() {
  local period=$1
  jq -r ".${period}_spend" "$BUDGET_FILE"
}

# Get limit
get_limit() {
  local period=$1
  jq -r ".${period}_limit" "$BUDGET_FILE"
}

# Check if over limit
check_limit() {
  local period=$1
  local spend=$(get_spend "$period")
  local limit=$(get_limit "$period")
  
  if (( $(echo "$spend >= $limit" | bc -l) )); then
    echo "OVER_LIMIT"
    return 1
  elif (( $(echo "$spend >= $limit * 0.9" | bc -l) )); then
    echo "APPROACHING_LIMIT"
    return 0
  else
    echo "OK"
    return 0
  fi
}

# Reset period if needed
reset_if_needed() {
  local now=$(date -u +%s)
  local last_daily=$(jq -r '.last_reset_daily // "null"' "$BUDGET_FILE")
  local last_weekly=$(jq -r '.last_reset_weekly // "null"' "$BUDGET_FILE")
  local last_monthly=$(jq -r '.last_reset_monthly // "null"' "$BUDGET_FILE")
  
  # Reset daily if more than 24h
  if [[ "$last_daily" != "null" ]]; then
    local last_daily_ts=$(date -jf "%Y-%m-%dT%H:%M:%S" "${last_daily%%Z*}" +%s 2>/dev/null || echo 0)
    local diff=$(( now - last_daily_ts ))
    if (( diff > 86400 )); then
      jq '.daily_spend = 0 | .last_reset_daily = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
      mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
    fi
  fi
  
  # Reset weekly if more than 7 days
  if [[ "$last_weekly" != "null" ]]; then
    local last_weekly_ts=$(date -jf "%Y-%m-%dT%H:%M:%S" "${last_weekly%%Z*}" +%s 2>/dev/null || echo 0)
    local diff=$(( now - last_weekly_ts ))
    if (( diff > 604800 )); then
      jq '.weekly_spend = 0 | .last_reset_weekly = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
      mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
    fi
  fi
  
  # Reset monthly if new month
  local current_month=$(date -u +%Y-%m)
  if [[ "$last_monthly" != "null" ]]; then
    local last_month=$(date -jf "%Y-%m-%dT%H:%M:%S" "${last_monthly%%Z*}" +%Y-%m 2>/dev/null || echo "1970-01")
    if [[ "$current_month" != "$last_month" ]]; then
      jq '.monthly_spend = 0 | .last_reset_monthly = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
      mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
    fi
  fi
}

# Add spend
add_spend() {
  local amount=$1
  local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Initialize reset times if null
  if [[ "$(jq -r '.last_reset_daily' "$BUDGET_FILE")" == "null" ]]; then
    jq '.last_reset_daily = "'$now'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  fi
  if [[ "$(jq -r '.last_reset_weekly' "$BUDGET_FILE")" == "null" ]]; then
    jq '.last_reset_weekly = "'$now'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  fi
  if [[ "$(jq -r '.last_reset_monthly' "$BUDGET_FILE")" == "null" ]]; then
    jq '.last_reset_monthly = "'$now'"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  fi
  
  reset_if_needed
  
  jq --arg amount "$amount" '
    .daily_spend = (.daily_spend + ($amount | tonumber)) |
    .weekly_spend = (.weekly_spend + ($amount | tonumber)) |
    .monthly_spend = (.monthly_spend + ($amount | tonumber))
  ' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
  mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  
  # Update status
  if ! check_limit "daily" >/dev/null 2>&1; then
    jq '.status = "over_daily_limit"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  elif ! check_limit "weekly" >/dev/null 2>&1; then
    jq '.status = "over_weekly_limit"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  elif ! check_limit "monthly" >/dev/null 2>&1; then
    jq '.status = "over_monthly_limit"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  else
    jq '.status = "ok"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
  fi
}

# Status report
status() {
  reset_if_needed
  
  local daily=$(get_spend "daily")
  local daily_limit=$(get_limit "daily")
  local weekly=$(get_spend "weekly")
  local weekly_limit=$(get_limit "weekly")
  local monthly=$(get_spend "monthly")
  local monthly_limit=$(get_limit "monthly")
  local status=$(jq -r '.status' "$BUDGET_FILE")
  
  echo "Budget Status: $status"
  echo "Daily:   \$$daily / \$$daily_limit ($(echo "scale=1; $daily * 100 / $daily_limit" | bc)%)"
  echo "Weekly:  \$$weekly / \$$weekly_limit ($(echo "scale=1; $weekly * 100 / $weekly_limit" | bc)%)"
  echo "Monthly: \$$monthly / \$$monthly_limit ($(echo "scale=1; $monthly * 100 / $monthly_limit" | bc)%)"
}

# Main command router
case "${1:-}" in
  status)
    status
    ;;
  add)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 add <amount>"
      exit 1
    fi
    add_spend "$2"
    ;;
  check)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 check <daily|weekly|monthly>"
      exit 1
    fi
    check_limit "$2"
    ;;
  reset)
    # Manual reset (for testing)
    jq '.daily_spend = 0 | .weekly_spend = 0 | .monthly_spend = 0 | .status = "ok"' "$BUDGET_FILE" > "$BUDGET_FILE.tmp"
    mv "$BUDGET_FILE.tmp" "$BUDGET_FILE"
    echo "Budget reset"
    ;;
  *)
    echo "Usage: $0 {status|add|check|reset}"
    exit 1
    ;;
esac
