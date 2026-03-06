#!/bin/bash
# Meta-learning engine for self-improvement system
# Analyzes the improvement process itself

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_REPORT_JSON="$SCRIPT_DIR/meta-report.json"
META_REPORT_MD="$SCRIPT_DIR/meta-report.md"
STRATEGY_ADJUSTMENTS="$SCRIPT_DIR/strategy-adjustments.json"

# Calculate hypothesis hit rate
calculate_hypothesis_hit_rate() {
  local total=0
  local successful=0
  
  if [[ ! -d "$WORKSPACE_ROOT/experiments/results" ]]; then
    echo "0"
    return
  fi
  
  for result in "$WORKSPACE_ROOT/experiments/results"/*.json; do
    [[ -f "$result" ]] || continue
    
    total=$((total + 1))
    
    local improvement=$(jq -r '.metrics.improvement_pp // 0' "$result")
    if (( $(echo "$improvement > 0" | bc -l) )); then
      successful=$((successful + 1))
    fi
  done
  
  if (( total > 0 )); then
    echo "scale=2; $successful * 100 / $total" | bc
  else
    echo "0"
  fi
}

# Calculate deployment success rate
calculate_deployment_success_rate() {
  local deployment_log="$WORKSPACE_ROOT/experiments/deployment-log.json"
  
  if [[ ! -f "$deployment_log" ]]; then
    echo "0"
    return
  fi
  
  local total=$(jq '. | length' "$deployment_log")
  local successful=$(jq '[.[] | select(.probation_passed == true)] | length' "$deployment_log")
  
  if (( total > 0 )); then
    echo "scale=2; $successful * 100 / $total" | bc
  else
    echo "0"
  fi
}

# Calculate improvement velocity (pp/week)
calculate_improvement_velocity() {
  local deployment_log="$WORKSPACE_ROOT/experiments/deployment-log.json"
  
  if [[ ! -f "$deployment_log" ]] || [[ ! -s "$deployment_log" ]]; then
    echo "0"
    return
  fi
  
  local total_pp=$(jq '[.[] | select(.probation_passed == true) | .improvement_pp] | add // 0' "$deployment_log")
  
  # Get time span
  local first_deployment=$(jq -r '.[0].deployed_at' "$deployment_log")
  local last_deployment=$(jq -r '.[-1].deployed_at' "$deployment_log")
  
  if [[ "$first_deployment" == "null" ]] || [[ "$last_deployment" == "null" ]]; then
    echo "0"
    return
  fi
  
  local first_ts=$(date -d "$first_deployment" +%s)
  local last_ts=$(date -d "$last_deployment" +%s)
  local weeks=$(echo "scale=2; ($last_ts - $first_ts) / 604800" | bc)
  
  if (( $(echo "$weeks > 0" | bc -l) )); then
    echo "scale=2; $total_pp / $weeks" | bc
  else
    echo "$total_pp"
  fi
}

# Calculate cost efficiency (pp/$)
calculate_cost_efficiency() {
  local state_file="$WORKSPACE_ROOT/loop/state.json"
  
  if [[ ! -f "$state_file" ]]; then
    echo "0"
    return
  fi
  
  local total_pp=$(jq -r '.total_pp_gained' "$state_file")
  local total_cost=$(jq -r '.total_cost' "$state_file")
  
  if (( $(echo "$total_cost > 0" | bc -l) )); then
    echo "scale=2; $total_pp / $total_cost" | bc
  else
    echo "0"
  fi
}

# Find best hypothesis sources
find_best_hypothesis_sources() {
  local results_dir="$WORKSPACE_ROOT/experiments/results"
  
  if [[ ! -d "$results_dir" ]]; then
    echo "[]"
    return
  fi
  
  # Aggregate by failure category
  declare -A category_successes
  declare -A category_totals
  
  for result in "$results_dir"/*.json; do
    [[ -f "$result" ]] || continue
    
    local category=$(jq -r '.hypothesis.failure_category // "unknown"' "$result")
    local improvement=$(jq -r '.metrics.improvement_pp // 0' "$result")
    
    category_totals["$category"]=$((${category_totals["$category"]:-0} + 1))
    
    if (( $(echo "$improvement > 0" | bc -l) )); then
      category_successes["$category"]=$((${category_successes["$category"]:-0} + 1))
    fi
  done
  
  # Generate JSON array
  local json="["
  local first=true
  
  for category in "${!category_totals[@]}"; do
    local total=${category_totals["$category"]}
    local successes=${category_successes["$category"]:-0}
    local rate=$(echo "scale=2; $successes * 100 / $total" | bc)
    
    if [[ "$first" == true ]]; then
      first=false
    else
      json+=","
    fi
    
    json+="{\"category\":\"$category\",\"success_rate\":$rate,\"total\":$total,\"successes\":$successes}"
  done
  
  json+="]"
  echo "$json"
}

# Detect compound effects
detect_compound_effects() {
  local deployment_log="$WORKSPACE_ROOT/experiments/deployment-log.json"
  
  if [[ ! -f "$deployment_log" ]]; then
    echo "[]"
    return
  fi
  
  # Look for deployments that enabled further improvements
  # This is a placeholder - would need more sophisticated analysis
  echo "[]"
}

# Generate meta-report
generate_report() {
  echo "Generating meta-learning report..."
  
  local hypothesis_hit_rate=$(calculate_hypothesis_hit_rate)
  local deployment_success_rate=$(calculate_deployment_success_rate)
  local improvement_velocity=$(calculate_improvement_velocity)
  local cost_efficiency=$(calculate_cost_efficiency)
  local best_sources=$(find_best_hypothesis_sources)
  local compound_effects=$(detect_compound_effects)
  
  # Generate JSON report
  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson hypothesis_hit_rate "$hypothesis_hit_rate" \
    --argjson deployment_success_rate "$deployment_success_rate" \
    --argjson improvement_velocity "$improvement_velocity" \
    --argjson cost_efficiency "$cost_efficiency" \
    --argjson best_sources "$best_sources" \
    --argjson compound_effects "$compound_effects" \
    '{
      generated_at: $timestamp,
      metrics: {
        hypothesis_hit_rate: $hypothesis_hit_rate,
        deployment_success_rate: $deployment_success_rate,
        improvement_velocity_pp_per_week: $improvement_velocity,
        cost_efficiency_pp_per_dollar: $cost_efficiency
      },
      best_hypothesis_sources: $best_sources,
      compound_effects: $compound_effects
    }' > "$META_REPORT_JSON"
  
  # Generate markdown report
  cat > "$META_REPORT_MD" <<EOF
# Meta-Learning Report

Generated: $(date -u +%Y-%m-%d)

## Performance Metrics

- **Hypothesis Hit Rate:** ${hypothesis_hit_rate}% (% of hypotheses that produced positive results)
- **Deployment Success Rate:** ${deployment_success_rate}% (% of deployments that passed probation)
- **Improvement Velocity:** ${improvement_velocity} pp/week
- **Cost Efficiency:** ${cost_efficiency} pp/\$

## Best Hypothesis Sources

EOF
  
  if [[ "$best_sources" != "[]" ]]; then
    echo "$best_sources" | jq -r '.[] | "- **\(.category)**: \(.success_rate)% success (\(.successes)/\(.total))"' >> "$META_REPORT_MD"
  else
    echo "No data yet" >> "$META_REPORT_MD"
  fi
  
  cat >> "$META_REPORT_MD" <<EOF

## Recommendations

EOF
  
  # Generate strategy adjustments
  generate_strategy_adjustments "$hypothesis_hit_rate" "$deployment_success_rate"
  
  if [[ -f "$STRATEGY_ADJUSTMENTS" ]]; then
    jq -r '.adjustments[] | "- \(.recommendation) (reason: \(.reason))"' "$STRATEGY_ADJUSTMENTS" >> "$META_REPORT_MD"
  fi
  
  echo "Report generated: $META_REPORT_MD"
}

# Generate strategy adjustments
generate_strategy_adjustments() {
  local hypothesis_hit_rate=$1
  local deployment_success_rate=$2
  
  local adjustments="[]"
  
  # Low hypothesis hit rate? Need better failure analysis
  if (( $(echo "$hypothesis_hit_rate < 30" | bc -l) )); then
    adjustments=$(echo "$adjustments" | jq '. += [{
      "type": "improve_analysis",
      "reason": "Low hypothesis hit rate (<30%)",
      "recommendation": "Improve failure analysis - current hypotheses not addressing root causes"
    }]')
  fi
  
  # Low deployment success? Safety threshold too low
  if (( $(echo "$deployment_success_rate < 70" | bc -l) )); then
    adjustments=$(echo "$adjustments" | jq '. += [{
      "type": "increase_threshold",
      "reason": "Low deployment success rate (<70%)",
      "recommendation": "Increase improvement threshold from 3pp to 5pp"
    }]')
  fi
  
  # High success rates? Can be more aggressive
  if (( $(echo "$hypothesis_hit_rate > 70 && $deployment_success_rate > 90" | bc -l) )); then
    adjustments=$(echo "$adjustments" | jq '. += [{
      "type": "increase_autonomy",
      "reason": "High success rates (>70% hypothesis, >90% deployment)",
      "recommendation": "Can increase probation capacity from 3 to 5 concurrent changes"
    }]')
  fi
  
  jq -n --argjson adjustments "$adjustments" '{
    generated_at: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    adjustments: $adjustments
  }' > "$STRATEGY_ADJUSTMENTS"
}

# Main
generate_report
