#!/bin/bash
# Safety governor for self-improvement deployments
# Pre-checks before any deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SAFETY_LOG="$SCRIPT_DIR/safety-log.json"
STATE_FILE="$SCRIPT_DIR/state.json"

# Safe target files (allowed for auto-deployment)
SAFE_TARGETS=(
  "observers/*/config.json"
  "analyzers/*/config.json"
  "experiments/config.json"
  "loop/schedule.json"
  "meta/strategy-adjustments.json"
)

# Unsafe targets (require human review)
UNSAFE_TARGETS=(
  "SOUL.md"
  "AGENTS.md"
  "USER.md"
  "MEMORY.md"
  "loop/improvement-loop.sh"
  "loop/budget-controller.sh"
  "loop/safety-governor.sh"
)

# Check if target is safe
is_safe_target() {
  local target=$1
  
  # Check against unsafe list first
  for pattern in "${UNSAFE_TARGETS[@]}"; do
    if [[ "$target" == $pattern ]]; then
      return 1
    fi
  done
  
  # Check against safe list
  for pattern in "${SAFE_TARGETS[@]}"; do
    if [[ "$target" == $pattern ]]; then
      return 0
    fi
  done
  
  # Default: unsafe if not in explicit safe list
  return 1
}

# Check if improvement is statistically significant
is_significant() {
  local experiment_id=$1
  local result_file="$WORKSPACE_ROOT/experiments/results/${experiment_id}.json"
  
  if [[ ! -f "$result_file" ]]; then
    echo "ERROR: Result file not found: $result_file" >&2
    return 1
  fi
  
  local p_value=$(jq -r '.statistical_significance.p_value // 1.0' "$result_file")
  
  # Significant if p < 0.05
  if (( $(echo "$p_value < 0.05" | bc -l) )); then
    return 0
  else
    return 1
  fi
}

# Check if improvement meets threshold
meets_threshold() {
  local experiment_id=$1
  local threshold=${2:-3.0}  # Default: 3pp
  local result_file="$WORKSPACE_ROOT/experiments/results/${experiment_id}.json"
  
  if [[ ! -f "$result_file" ]]; then
    echo "ERROR: Result file not found: $result_file" >&2
    return 1
  fi
  
  local improvement=$(jq -r '.metrics.improvement_pp // 0' "$result_file")
  
  if (( $(echo "$improvement >= $threshold" | bc -l) )); then
    return 0
  else
    return 1
  fi
}

# Check budget status
check_budget() {
  local status=$("$SCRIPT_DIR/budget-controller.sh" check daily 2>&1 || echo "OVER_LIMIT")
  
  if [[ "$status" == "OVER_LIMIT" ]]; then
    return 1
  else
    return 0
  fi
}

# Check probation capacity
check_probation_capacity() {
  local active_probations=$(jq -r '.active_probations' "$STATE_FILE")
  local max_probations=3
  
  if (( active_probations >= max_probations )); then
    return 1
  else
    return 0
  fi
}

# Log veto decision
log_veto() {
  local experiment_id=$1
  local target=$2
  local reason=$3
  
  local entry=$(jq -n \
    --arg exp "$experiment_id" \
    --arg tgt "$target" \
    --arg rsn "$reason" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      experiment_id: $exp,
      target: $tgt,
      reason: $rsn,
      vetoed_at: $ts
    }')
  
  jq --argjson entry "$entry" '. += [$entry]' "$SAFETY_LOG" > "$SAFETY_LOG.tmp"
  mv "$SAFETY_LOG.tmp" "$SAFETY_LOG"
  
  echo "VETO: $reason" >&2
}

# Main safety check
check() {
  local experiment_id=$1
  local target=$2
  
  # Check 1: Safe target?
  if ! is_safe_target "$target"; then
    log_veto "$experiment_id" "$target" "Unsafe target (requires human review)"
    echo "unsafe_target"
    return 1
  fi
  
  # Check 2: Statistically significant?
  if ! is_significant "$experiment_id"; then
    log_veto "$experiment_id" "$target" "Not statistically significant (p >= 0.05)"
    echo "not_significant"
    return 1
  fi
  
  # Check 3: Meets improvement threshold?
  if ! meets_threshold "$experiment_id" 3.0; then
    log_veto "$experiment_id" "$target" "Below improvement threshold (<3pp)"
    echo "below_threshold"
    return 1
  fi
  
  # Check 4: Budget OK?
  if ! check_budget; then
    log_veto "$experiment_id" "$target" "Over budget limit"
    echo "over_budget"
    return 1
  fi
  
  # Check 5: Probation capacity?
  if ! check_probation_capacity; then
    log_veto "$experiment_id" "$target" "Too many active probations (max 3)"
    echo "probation_full"
    return 1
  fi
  
  # All checks passed
  echo "safe"
  return 0
}

# Show recent vetoes
show_vetoes() {
  local limit=${1:-10}
  
  if [[ ! -s "$SAFETY_LOG" ]] || [[ "$(jq '. | length' "$SAFETY_LOG")" == "0" ]]; then
    echo "No vetoes recorded"
    return
  fi
  
  echo "Recent vetoes:"
  jq -r --argjson limit "$limit" '
    .[-$limit:] | .[] | 
    "\(.vetoed_at) | \(.experiment_id) | \(.target) | \(.reason)"
  ' "$SAFETY_LOG"
}

# Main command router
case "${1:-}" in
  check)
    if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
      echo "Usage: $0 check <experiment_id> <target_file>"
      exit 1
    fi
    check "$2" "$3"
    ;;
  vetoes)
    show_vetoes "${2:-10}"
    ;;
  *)
    echo "Usage: $0 {check|vetoes}"
    exit 1
    ;;
esac
