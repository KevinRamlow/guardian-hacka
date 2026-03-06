#!/bin/bash
# Experiment Dashboard - Human-readable summary of all experiments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
DEPLOYMENT_LOG="$SCRIPT_DIR/deployment-log.json"
PROBATION_FILE="$SCRIPT_DIR/probation.json"

# Function to display dashboard
show_dashboard() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        Self-Improvement Experimentation Dashboard             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Count experiments by status
    local total=0
    local created=0
    local variant_generated=0
    local running=0
    local completed=0
    local deployed=0
    local rolled_back=0
    
    if [[ -d "$ACTIVE_DIR" ]] && [[ -n "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        for exp_file in "$ACTIVE_DIR"/*.json; do
            total=$((total + 1))
            local status=$(jq -r '.status' "$exp_file")
            
            case "$status" in
                created) created=$((created + 1)) ;;
                variant_generated) variant_generated=$((variant_generated + 1)) ;;
                running) running=$((running + 1)) ;;
                completed) completed=$((completed + 1)) ;;
                deployed) deployed=$((deployed + 1)) ;;
                rolled_back) rolled_back=$((rolled_back + 1)) ;;
            esac
        done
    fi
    
    # Count decisions
    local deploy_decision=0
    local reject_decision=0
    local human_review=0
    local inconclusive=0
    
    if [[ $total -gt 0 ]]; then
        for exp_file in "$ACTIVE_DIR"/*.json; do
            local result=$(jq -r '.result // "null"' "$exp_file")
            
            case "$result" in
                deploy) deploy_decision=$((deploy_decision + 1)) ;;
                reject) reject_decision=$((reject_decision + 1)) ;;
                human_review) human_review=$((human_review + 1)) ;;
                inconclusive) inconclusive=$((inconclusive + 1)) ;;
            esac
        done
    fi
    
    # Calculate win rate
    local win_rate=0
    if [[ $completed -gt 0 ]]; then
        win_rate=$(echo "scale=1; ($deploy_decision * 100) / $completed" | bc)
    fi
    
    # Calculate net improvement
    local net_improvement=0
    if [[ -f "$DEPLOYMENT_LOG" ]]; then
        net_improvement=$(jq -r '[.deployments[].expected_improvement_pp] | add // 0' "$DEPLOYMENT_LOG")
    fi
    
    # Probation count
    local on_probation=0
    if [[ -f "$PROBATION_FILE" ]]; then
        on_probation=$(jq '[.experiments[] | select(.status == "on_probation")] | length' "$PROBATION_FILE")
    fi
    
    # Display summary
    echo "📊 EXPERIMENT STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total experiments:      $total"
    echo "  Created:                $created"
    echo "  Variant generated:      $variant_generated"
    echo "  Running:                $running"
    echo "  Completed:              $completed"
    echo "  Deployed:               $deployed"
    echo "  Rolled back:            $rolled_back"
    echo ""
    
    echo "🎯 EVALUATION RESULTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Deploy:                 $deploy_decision"
    echo "  Reject:                 $reject_decision"
    echo "  Human review needed:    $human_review"
    echo "  Inconclusive:           $inconclusive"
    echo "  Win rate:               ${win_rate}%"
    echo ""
    
    echo "🚀 DEPLOYMENT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total deployments:      $deployed"
    echo "  On probation:           $on_probation"
    echo "  Net improvement:        +${net_improvement}pp"
    echo ""
    
    # Show active experiments
    if [[ $total -gt 0 ]]; then
        echo "📋 ACTIVE EXPERIMENTS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        for exp_file in "$ACTIVE_DIR"/*.json; do
            local exp_id=$(jq -r '.id' "$exp_file")
            local status=$(jq -r '.status' "$exp_file")
            local description=$(jq -r '.description' "$exp_file")
            local sample_size=$(jq -r '.sample_size // 0' "$exp_file")
            local result=$(jq -r '.result // "-"' "$exp_file")
            local improvement=$(jq -r '.metrics_after.improvement_pp // "-"' "$exp_file")
            
            echo "  $exp_id [$status]"
            echo "    Description: $description"
            echo "    Sample size: $sample_size"
            
            if [[ "$result" != "-" ]]; then
                echo "    Result: $result"
            fi
            
            if [[ "$improvement" != "-" ]]; then
                echo "    Improvement: ${improvement}pp"
            fi
            
            echo ""
        done
    else
        echo "No experiments yet. Run './run-experiments.sh create' to start."
        echo ""
    fi
    
    # Show probation experiments
    if [[ $on_probation -gt 0 ]]; then
        echo "⏱️  EXPERIMENTS ON PROBATION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        jq -r '.experiments[] | select(.status == "on_probation") | "  \(.exp_id) → \(.target_file)\n    Deployed: \(.deployed_at)\n    Probation ends: \(.probation_end)\n    Expected: +\(.expected_improvement_pp)pp\n"' "$PROBATION_FILE"
    fi
    
    # Show recent rollbacks
    local recent_rollbacks=$(jq '[.experiments[] | select(.status == "rolled_back")] | length' "$PROBATION_FILE" 2>/dev/null || echo "0")
    
    if [[ $recent_rollbacks -gt 0 ]]; then
        echo "🔄 RECENT ROLLBACKS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        jq -r '.experiments[] | select(.status == "rolled_back") | "  \(.exp_id)\n    Reason: \(.rollback_reason)\n    Rolled back: \(.rolled_back_at)\n"' "$PROBATION_FILE"
    fi
    
    echo "════════════════════════════════════════════════════════════════"
}

# Main execution
show_dashboard
