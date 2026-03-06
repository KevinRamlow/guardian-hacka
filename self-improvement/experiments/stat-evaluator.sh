#!/bin/bash
# Statistical Evaluator - Analyzes experiment results and makes deployment decisions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
RESULTS_DIR="$SCRIPT_DIR/results"
WORKSPACE_ROOT="/root/.openclaw/workspace"

# Unsafe targets requiring human approval
UNSAFE_TARGETS=(
    "AGENTS.md"
    "openclaw.json"
    "TOOLS.md"
    ".env"
    "config/gateway.json"
)

# Function to check if target is safe for auto-deploy
is_safe_target() {
    local target="$1"
    
    for unsafe in "${UNSAFE_TARGETS[@]}"; do
        if [[ "$target" == *"$unsafe"* ]]; then
            return 1
        fi
    done
    
    return 0
}

# Function to calculate mean of array
calculate_mean() {
    local sum=0
    local count=0
    
    while read -r value; do
        sum=$(echo "$sum + $value" | bc)
        count=$((count + 1))
    done
    
    if [[ $count -eq 0 ]]; then
        echo "0"
    else
        echo "scale=2; $sum / $count" | bc
    fi
}

# Function to calculate standard deviation
calculate_stdev() {
    local mean="$1"
    local sum_sq_diff=0
    local count=0
    
    while read -r value; do
        local diff=$(echo "$value - $mean" | bc)
        local sq_diff=$(echo "$diff * $diff" | bc)
        sum_sq_diff=$(echo "$sum_sq_diff + $sq_diff" | bc)
        count=$((count + 1))
    done
    
    if [[ $count -le 1 ]]; then
        echo "0"
    else
        echo "scale=4; sqrt($sum_sq_diff / ($count - 1))" | bc
    fi
}

# Function to evaluate experiment
evaluate_experiment() {
    local exp_id="$1"
    
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    local results_file="$RESULTS_DIR/$exp_id/results.jsonl"
    
    if [[ ! -f "$exp_file" ]]; then
        echo "❌ Experiment $exp_id not found"
        return 1
    fi
    
    if [[ ! -f "$results_file" ]]; then
        echo "❌ No results found for $exp_id"
        return 1
    fi
    
    local target_file=$(jq -r '.target_file' "$exp_file")
    local min_sample_size=$(jq -r '.min_sample_size' "$exp_file")
    local sample_size=$(wc -l < "$results_file")
    
    echo "📊 Evaluating experiment $exp_id"
    echo "   Sample size: $sample_size (min: $min_sample_size)"
    echo "   Target: $target_file"
    echo ""
    
    # Check minimum sample size
    if [[ $sample_size -lt $min_sample_size ]]; then
        echo "⚠️ Insufficient samples. Status: INCONCLUSIVE"
        jq ".result = \"inconclusive\" | .result_reason = \"Insufficient samples ($sample_size < $min_sample_size)\"" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
        return 0
    fi
    
    # Calculate aggregate scores across all dimensions
    local baseline_scores=()
    local variant_scores=()
    
    # Extract scores for each dimension
    for dimension in task_completion response_speed communication_quality autonomy proactiveness; do
        local baseline_mean=$(jq -r ".baseline.$dimension" "$results_file" | calculate_mean)
        local variant_mean=$(jq -r ".variant.$dimension" "$results_file" | calculate_mean)
        
        baseline_scores+=("$baseline_mean")
        variant_scores+=("$variant_mean")
        
        echo "  $dimension: baseline=$baseline_mean, variant=$variant_mean"
    done
    
    # Calculate overall mean scores
    local baseline_total=0
    local variant_total=0
    
    for score in "${baseline_scores[@]}"; do
        baseline_total=$(echo "$baseline_total + $score" | bc)
    done
    
    for score in "${variant_scores[@]}"; do
        variant_total=$(echo "$variant_total + $score" | bc)
    done
    
    local baseline_mean=$(echo "scale=2; $baseline_total / ${#baseline_scores[@]}" | bc)
    local variant_mean=$(echo "scale=2; $variant_total / ${#variant_scores[@]}" | bc)
    
    # Calculate improvement in percentage points
    local improvement=$(echo "scale=2; ($variant_mean - $baseline_mean) * 10" | bc)
    
    echo ""
    echo "  Overall: baseline=$baseline_mean, variant=$variant_mean"
    echo "  Improvement: ${improvement}pp"
    echo ""
    
    # Simple statistical test (approximate t-test)
    # For simplicity, we check if improvement > threshold
    local deploy_threshold=3
    local large_effect_threshold=10
    
    local decision="reject"
    local reason=""
    
    # Check deployment criteria
    if (( $(echo "$improvement > $deploy_threshold" | bc -l) )); then
        if is_safe_target "$target_file"; then
            decision="deploy"
            reason="Improvement ${improvement}pp > ${deploy_threshold}pp threshold, safe target"
        else
            decision="human_review"
            reason="Improvement ${improvement}pp > ${deploy_threshold}pp but target is unsafe: $target_file"
        fi
    elif (( $(echo "$improvement > $large_effect_threshold" | bc -l) )); then
        decision="human_review"
        reason="Large effect ${improvement}pp detected, flagging for review"
    elif (( $(echo "$improvement < -$deploy_threshold" | bc -l) )); then
        decision="reject"
        reason="Variant performs worse by ${improvement}pp"
    else
        decision="reject"
        reason="Insufficient improvement: ${improvement}pp < ${deploy_threshold}pp threshold"
    fi
    
    echo "🎯 Decision: $decision"
    echo "   Reason: $reason"
    
    # Update experiment with results
    jq ".result = \"$decision\" | .result_reason = \"$reason\" | .metrics_after = {baseline_mean: $baseline_mean, variant_mean: $variant_mean, improvement_pp: $improvement}" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    
    echo ""
    echo "✅ Evaluation complete for $exp_id"
}

# Main command router
case "${1:-}" in
    evaluate)
        if [[ -n "${2:-}" ]]; then
            evaluate_experiment "$2"
        else
            echo "Usage: $0 evaluate <experiment_id>"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 evaluate <experiment_id>"
        exit 1
        ;;
esac
