#!/bin/bash
# Deployment Engine - Deploys winning experiments with backups and probation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
BACKUPS_DIR="$SCRIPT_DIR/backups"
PROBATION_FILE="$SCRIPT_DIR/probation.json"
DEPLOYMENT_LOG="$SCRIPT_DIR/deployment-log.json"
WORKSPACE_ROOT="/Users/fonsecabc/.openclaw/workspace"

# Ensure directories exist
mkdir -p "$BACKUPS_DIR"

# Initialize files if they don't exist
[[ -f "$PROBATION_FILE" ]] || echo '{"experiments": []}' > "$PROBATION_FILE"
[[ -f "$DEPLOYMENT_LOG" ]] || echo '{"deployments": []}' > "$DEPLOYMENT_LOG"

# Function to deploy experiment
deploy_experiment() {
    local exp_id="$1"
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    
    if [[ ! -f "$exp_file" ]]; then
        echo "❌ Experiment $exp_id not found"
        return 1
    fi
    
    local result=$(jq -r '.result' "$exp_file")
    
    if [[ "$result" != "deploy" ]]; then
        echo "❌ Experiment $exp_id not approved for deployment (result: $result)"
        return 1
    fi
    
    local target_file=$(jq -r '.target_file' "$exp_file")
    local variant_file=$(jq -r '.variant_file' "$exp_file")
    local improvement=$(jq -r '.metrics_after.improvement_pp' "$exp_file")
    
    local target_path="$WORKSPACE_ROOT/$target_file"
    local variant_path="$BASE_DIR/$variant_file"
    
    if [[ ! -f "$target_path" ]]; then
        echo "❌ Target file not found: $target_path"
        return 1
    fi
    
    if [[ ! -f "$variant_path" ]]; then
        echo "❌ Variant file not found: $variant_path"
        return 1
    fi
    
    echo "🚀 Deploying experiment $exp_id"
    echo "   Target: $target_file"
    echo "   Expected improvement: ${improvement}pp"
    
    # Create timestamped backup
    local timestamp=$(date -u +"%Y-%m-%d-%H%M%S")
    local backup_name="${timestamp}-${exp_id}-$(basename "$target_file").bak"
    local backup_path="$BACKUPS_DIR/$backup_name"
    
    cp "$target_path" "$backup_path"
    echo "📦 Backup created: $backup_path"
    
    # Deploy variant
    cp "$variant_path" "$target_path"
    echo "✅ Deployed variant to $target_path"
    
    # Set 24h probation
    local deploy_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local probation_end=$(date -u -v+24H +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add to probation tracking
    jq ".experiments += [{
        exp_id: \"$exp_id\",
        target_file: \"$target_file\",
        backup_file: \"$backup_path\",
        deployed_at: \"$deploy_timestamp\",
        probation_end: \"$probation_end\",
        expected_improvement_pp: $improvement,
        status: \"on_probation\"
    }]" "$PROBATION_FILE" > "${PROBATION_FILE}.tmp" && mv "${PROBATION_FILE}.tmp" "$PROBATION_FILE"
    
    echo "⏱️ Probation period: 24h (until $probation_end)"
    
    # Log deployment
    jq ".deployments += [{
        exp_id: \"$exp_id\",
        target_file: \"$target_file\",
        deployed_at: \"$deploy_timestamp\",
        expected_improvement_pp: $improvement,
        backup_file: \"$backup_path\"
    }]" "$DEPLOYMENT_LOG" > "${DEPLOYMENT_LOG}.tmp" && mv "${DEPLOYMENT_LOG}.tmp" "$DEPLOYMENT_LOG"
    
    # Update experiment status
    jq ".status = \"deployed\" | .deployed_at = \"$deploy_timestamp\"" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    
    echo ""
    echo "✅ Deployment complete for $exp_id"
    echo "   Monitor metrics for next 24h"
    echo "   Auto-rollback if performance degrades >5pp"
}

# Function to list deployments
list_deployments() {
    echo "Recent Deployments:"
    echo "==================="
    
    if [[ ! -f "$DEPLOYMENT_LOG" ]]; then
        echo "No deployments yet"
        return 0
    fi
    
    jq -r '.deployments[] | "  \(.exp_id) [\(.deployed_at)] → \(.target_file) (expected: +\(.expected_improvement_pp)pp)"' "$DEPLOYMENT_LOG"
}

# Function to list probation experiments
list_probation() {
    echo "Experiments on Probation:"
    echo "========================="
    
    if [[ ! -f "$PROBATION_FILE" ]]; then
        echo "None"
        return 0
    fi
    
    local count=$(jq '.experiments | length' "$PROBATION_FILE")
    
    if [[ $count -eq 0 ]]; then
        echo "None"
        return 0
    fi
    
    jq -r '.experiments[] | select(.status == "on_probation") | "  \(.exp_id) until \(.probation_end) → \(.target_file)"' "$PROBATION_FILE"
}

# Main command router
case "${1:-}" in
    deploy)
        if [[ -n "${2:-}" ]]; then
            deploy_experiment "$2"
        else
            echo "Usage: $0 deploy <experiment_id>"
            exit 1
        fi
        ;;
    list)
        list_deployments
        ;;
    probation)
        list_probation
        ;;
    *)
        echo "Usage: $0 {deploy <exp_id>|list|probation}"
        exit 1
        ;;
esac
