#!/bin/bash
# Experiment Manager - Creates experiment definitions from hypotheses

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
HYPOTHESES_FILE="$BASE_DIR/analysis/hypotheses.json"
ACTIVE_DIR="$SCRIPT_DIR/active"
VARIANTS_DIR="$SCRIPT_DIR/variants"
BASELINES_DIR="$SCRIPT_DIR/baselines"

# Ensure directories exist
mkdir -p "$ACTIVE_DIR" "$VARIANTS_DIR" "$BASELINES_DIR"

# Function to generate experiment ID
generate_exp_id() {
    local count=$(ls -1 "$ACTIVE_DIR" 2>/dev/null | wc -l)
    printf "exp-%03d" $((count + 1))
}

# Function to create experiment from hypothesis
create_experiment() {
    local hyp_id="$1"
    
    if [[ ! -f "$HYPOTHESES_FILE" ]]; then
        echo "❌ No hypotheses file found at $HYPOTHESES_FILE"
        return 1
    fi
    
    # Extract hypothesis details
    local hypothesis=$(jq -r ".hypotheses[] | select(.id == \"$hyp_id\")" "$HYPOTHESES_FILE")
    
    if [[ -z "$hypothesis" || "$hypothesis" == "null" ]]; then
        echo "❌ Hypothesis $hyp_id not found"
        return 1
    fi
    
    local description=$(echo "$hypothesis" | jq -r '.description')
    local target_file=$(echo "$hypothesis" | jq -r '.target_file // ""')
    local proposed_change=$(echo "$hypothesis" | jq -r '.proposed_change // ""')
    
    # If no target file specified, try to infer from description
    if [[ -z "$target_file" || "$target_file" == "null" ]]; then
        echo "⚠️ No target_file specified in hypothesis. Manual intervention required."
        echo "   Description: $description"
        return 1
    fi
    
    # Generate experiment ID
    local exp_id=$(generate_exp_id)
    
    # Create experiment definition
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$exp_file" <<EOF
{
  "id": "$exp_id",
  "hypothesis_id": "$hyp_id",
  "description": "$description",
  "proposed_change": "$proposed_change",
  "target_file": "$target_file",
  "variant_file": "experiments/variants/${exp_id}-variant.md",
  "baseline_file": "experiments/baselines/${exp_id}-baseline.md",
  "status": "created",
  "created_at": "$timestamp",
  "started_at": null,
  "metrics_before": {},
  "metrics_after": {},
  "sample_size": 0,
  "min_sample_size": 30,
  "result": null
}
EOF
    
    echo "✅ Created experiment $exp_id for hypothesis $hyp_id"
    echo "   Target: $target_file"
    echo "   File: $exp_file"
}

# Function to list all active experiments
list_experiments() {
    if [[ ! -d "$ACTIVE_DIR" ]] || [[ -z "$(ls -A "$ACTIVE_DIR" 2>/dev/null)" ]]; then
        echo "No active experiments"
        return 0
    fi
    
    echo "Active Experiments:"
    echo "==================="
    for exp_file in "$ACTIVE_DIR"/*.json; do
        local exp_id=$(jq -r '.id' "$exp_file")
        local status=$(jq -r '.status' "$exp_file")
        local description=$(jq -r '.description' "$exp_file")
        local sample_size=$(jq -r '.sample_size' "$exp_file")
        
        echo "  $exp_id [$status] (n=$sample_size): $description"
    done
}

# Function to create experiments from all pending hypotheses
create_all() {
    if [[ ! -f "$HYPOTHESES_FILE" ]]; then
        echo "❌ No hypotheses file found"
        return 1
    fi
    
    local hyp_ids=$(jq -r '.hypotheses[].id' "$HYPOTHESES_FILE")
    
    if [[ -z "$hyp_ids" ]]; then
        echo "No hypotheses to process"
        return 0
    fi
    
    echo "Creating experiments from hypotheses..."
    while IFS= read -r hyp_id; do
        create_experiment "$hyp_id"
    done <<< "$hyp_ids"
}

# Main command router
case "${1:-list}" in
    create)
        if [[ -n "${2:-}" ]]; then
            create_experiment "$2"
        else
            echo "Usage: $0 create <hypothesis_id>"
            exit 1
        fi
        ;;
    create-all)
        create_all
        ;;
    list)
        list_experiments
        ;;
    *)
        echo "Usage: $0 {create <hyp_id>|create-all|list}"
        exit 1
        ;;
esac
