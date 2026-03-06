#!/bin/bash
# Rollback Engine - Auto-rollback experiments with degraded metrics

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
PROBATION_FILE="$SCRIPT_DIR/probation.json"
METRICS_DIR="$BASE_DIR/metrics/daily-scores"
WORKSPACE_ROOT="/root/.openclaw/workspace"

# Degradation threshold (percentage points)
DEGRADATION_THRESHOLD=5

# Function to get recent average score
get_recent_avg_score() {
    local days="${1:-3}"
    
    if [[ ! -d "$METRICS_DIR" ]]; then
        echo "0"
        return
    fi
    
    # Get last N days of scores
    local scores=$(find "$METRICS_DIR" -name "*.json" -type f | sort -r | head -n "$days" | xargs -I {} jq -r '.overall_score' {} 2>/dev/null | grep -v null || echo "")
    
    if [[ -z "$scores" ]]; then
        echo "0"
        return
    fi
    
    # Calculate average
    local sum=0
    local count=0
    
    while read -r score; do
        sum=$(echo "$sum + $score" | bc)
        count=$((count + 1))
    done <<< "$scores"
    
    if [[ $count -eq 0 ]]; then
        echo "0"
    else
        echo "scale=2; $sum / $count" | bc
    fi
}

# Function to check if probation experiment should be rolled back
check_probation_experiment() {
    local exp_id="$1"
    local target_file="$2"
    local backup_file="$3"
    local expected_improvement="$4"
    local deployed_at="$5"
    
    echo "Checking $exp_id..."
    
    # Get pre-deployment baseline (from experiment file)
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    local baseline_score=$(jq -r '.metrics_after.baseline_mean // 0' "$exp_file")
    
    # Get recent average score (last 3 days)
    local current_avg=$(get_recent_avg_score 3)
    
    echo "  Baseline: $baseline_score"
    echo "  Current avg (3d): $current_avg"
    
    # Calculate actual change
    local actual_change=$(echo "scale=2; ($current_avg - $baseline_score) * 10" | bc)
    
    echo "  Expected improvement: ${expected_improvement}pp"
    echo "  Actual change: ${actual_change}pp"
    
    # Check if degraded significantly
    if (( $(echo "$actual_change < -$DEGRADATION_THRESHOLD" | bc -l) )); then
        echo "  ⚠️ DEGRADATION DETECTED: ${actual_change}pp"
        rollback_experiment "$exp_id" "$target_file" "$backup_file" "$actual_change"
        return 0
    else
        echo "  ✅ Performance OK"
        return 1
    fi
}

# Function to rollback experiment
rollback_experiment() {
    local exp_id="$1"
    local target_file="$2"
    local backup_file="$3"
    local degradation="$4"
    
    local target_path="$WORKSPACE_ROOT/$target_file"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    echo ""
    echo "🔄 ROLLING BACK experiment $exp_id"
    echo "   Degradation: ${degradation}pp"
    echo "   Restoring from: $backup_file"
    
    # Restore backup
    cp "$backup_file" "$target_path"
    echo "✅ Restored $target_path from backup"
    
    # Update probation status
    jq "(.experiments[] | select(.exp_id == \"$exp_id\") | .status) = \"rolled_back\"" "$PROBATION_FILE" > "${PROBATION_FILE}.tmp" && mv "${PROBATION_FILE}.tmp" "$PROBATION_FILE"
    jq "(.experiments[] | select(.exp_id == \"$exp_id\") | .rollback_reason) = \"Performance degraded by ${degradation}pp (threshold: ${DEGRADATION_THRESHOLD}pp)\"" "$PROBATION_FILE" > "${PROBATION_FILE}.tmp" && mv "${PROBATION_FILE}.tmp" "$PROBATION_FILE"
    jq "(.experiments[] | select(.exp_id == \"$exp_id\") | .rolled_back_at) = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$PROBATION_FILE" > "${PROBATION_FILE}.tmp" && mv "${PROBATION_FILE}.tmp" "$PROBATION_FILE"
    
    # Update experiment file
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    if [[ -f "$exp_file" ]]; then
        jq ".status = \"rolled_back\" | .rollback_reason = \"Performance degraded by ${degradation}pp\"" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    fi
    
    echo "✅ Rollback complete for $exp_id"
}

# Function to check all probation experiments
check_all_probation() {
    if [[ ! -f "$PROBATION_FILE" ]]; then
        echo "No probation file found"
        return 0
    fi
    
    local probation_exps=$(jq -r '.experiments[] | select(.status == "on_probation") | @json' "$PROBATION_FILE")
    
    if [[ -z "$probation_exps" ]]; then
        echo "No experiments on probation"
        return 0
    fi
    
    echo "Checking experiments on probation..."
    echo "====================================="
    echo ""
    
    local rolled_back_count=0
    
    while IFS= read -r exp_json; do
        local exp_id=$(echo "$exp_json" | jq -r '.exp_id')
        local target_file=$(echo "$exp_json" | jq -r '.target_file')
        local backup_file=$(echo "$exp_json" | jq -r '.backup_file')
        local expected_improvement=$(echo "$exp_json" | jq -r '.expected_improvement_pp')
        local deployed_at=$(echo "$exp_json" | jq -r '.deployed_at')
        
        if check_probation_experiment "$exp_id" "$target_file" "$backup_file" "$expected_improvement" "$deployed_at"; then
            rolled_back_count=$((rolled_back_count + 1))
        fi
        echo ""
    done <<< "$probation_exps"
    
    if [[ $rolled_back_count -gt 0 ]]; then
        echo "⚠️ Rolled back $rolled_back_count experiment(s)"
    else
        echo "✅ All probation experiments performing well"
    fi
}

# Function to manually rollback an experiment
manual_rollback() {
    local exp_id="$1"
    local reason="${2:-Manual rollback}"
    
    if [[ ! -f "$PROBATION_FILE" ]]; then
        echo "❌ No probation file found"
        return 1
    fi
    
    local exp_json=$(jq -r ".experiments[] | select(.exp_id == \"$exp_id\") | @json" "$PROBATION_FILE")
    
    if [[ -z "$exp_json" ]]; then
        echo "❌ Experiment $exp_id not found in probation"
        return 1
    fi
    
    local target_file=$(echo "$exp_json" | jq -r '.target_file')
    local backup_file=$(echo "$exp_json" | jq -r '.backup_file')
    
    rollback_experiment "$exp_id" "$target_file" "$backup_file" "manual: $reason"
}

# Main command router
case "${1:-}" in
    check)
        check_all_probation
        ;;
    rollback)
        if [[ -n "${2:-}" ]]; then
            manual_rollback "$2" "${3:-Manual rollback}"
        else
            echo "Usage: $0 rollback <experiment_id> [reason]"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {check|rollback <exp_id> [reason]}"
        exit 1
        ;;
esac
