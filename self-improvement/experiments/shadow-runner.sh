#!/bin/bash
# Shadow Runner - Runs simulated A/B tests using LLM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
RESULTS_DIR="$SCRIPT_DIR/results"

# Sample conversation contexts for testing
SAMPLE_CONTEXTS=(
    "User: Can you analyze the Guardian agreement rate and tell me what's causing disagreements?"
    "User: Write a SQL query to find all campaigns with >10% rejection rate"
    "User: Review this PR and tell me if it's ready to merge"
    "User: What's the current status of CAI-42?"
    "User: Generate a team update about yesterday's deployment"
    "User: Debug why the tolerance check is failing for mild vs neutral"
)

# Scoring dimensions (same as Phase 1)
DIMENSIONS=(
    "task_completion"
    "response_speed"
    "communication_quality"
    "autonomy"
    "proactiveness"
)

# Function to run single simulation
run_simulation() {
    local exp_id="$1"
    local context="$2"
    local iteration="$3"
    
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    local baseline_file=$(jq -r '.baseline_file' "$exp_file")
    local variant_file=$(jq -r '.variant_file' "$exp_file")
    local description=$(jq -r '.description' "$exp_file")
    
    # Read baseline and variant content
    local baseline_content=$(cat "$BASE_DIR/$baseline_file" 2>/dev/null || echo "")
    local variant_content=$(cat "$BASE_DIR/$variant_file" 2>/dev/null || echo "")
    
    if [[ -z "$baseline_content" ]] || [[ -z "$variant_content" ]]; then
        echo "❌ Missing baseline or variant file"
        return 1
    fi
    
    # Build simulation prompt
    local prompt="You are evaluating two versions of an AI agent configuration for an A/B test.

**Experiment:** $exp_id
**Change:** $description
**Context:** $context

**BASELINE Configuration:**
\`\`\`
${baseline_content:0:2000}
\`\`\`

**VARIANT Configuration:**
\`\`\`
${variant_content:0:2000}
\`\`\`

**Task:** Simulate how Anton (the AI orchestrator) would respond to this context with BASELINE vs VARIANT configuration. Score each on 1-10 scale:
- task_completion: Completeness and correctness of response
- response_speed: Efficiency, no redundant steps
- communication_quality: Clarity, appropriate detail
- autonomy: Independent problem-solving
- proactiveness: Going beyond the ask

**Output JSON only:**
{
  \"baseline\": {\"task_completion\": X, \"response_speed\": X, \"communication_quality\": X, \"autonomy\": X, \"proactiveness\": X},
  \"variant\": {\"task_completion\": X, \"response_speed\": X, \"communication_quality\": X, \"autonomy\": X, \"proactiveness\": X},
  \"reasoning\": \"brief explanation of key differences\"
}"
    
    # Call Haiku for simulation
    local response=$(echo "$prompt" | openclaw invoke model \
        --model anthropic/claude-haiku-3.5 \
        --temperature 0.5 \
        --max-tokens 1024 2>/dev/null || echo "{}")
    
    # Extract JSON (remove markdown code blocks if present)
    response=$(echo "$response" | sed -n '/^{/,/^}/p' | jq -c '.')
    
    echo "$response"
}

# Function to run full experiment (multiple iterations)
run_experiment() {
    local exp_id="$1"
    local num_iterations="${2:-10}"
    
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    
    if [[ ! -f "$exp_file" ]]; then
        echo "❌ Experiment $exp_id not found"
        return 1
    fi
    
    # Create results directory
    local exp_results_dir="$RESULTS_DIR/$exp_id"
    mkdir -p "$exp_results_dir"
    
    echo "🧪 Running experiment $exp_id with $num_iterations iterations..."
    
    # Update experiment status
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq ".status = \"running\" | .started_at = \"$timestamp\"" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    
    # Run simulations
    local results_file="$exp_results_dir/results.jsonl"
    > "$results_file"  # Clear file
    
    for i in $(seq 1 "$num_iterations"); do
        echo "  Run $i/$num_iterations..."
        
        # Pick random context
        local context_idx=$((RANDOM % ${#SAMPLE_CONTEXTS[@]}))
        local context="${SAMPLE_CONTEXTS[$context_idx]}"
        
        # Run simulation
        local result=$(run_simulation "$exp_id" "$context" "$i")
        
        if [[ -n "$result" ]] && [[ "$result" != "{}" ]]; then
            # Add metadata
            result=$(echo "$result" | jq -c ". + {iteration: $i, context: \"$context\", timestamp: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}")
            echo "$result" >> "$results_file"
        else
            echo "    ⚠️ Simulation failed, skipping"
        fi
        
        # Small delay to avoid rate limits
        sleep 1
    done
    
    # Update sample size
    local actual_samples=$(wc -l < "$results_file")
    jq ".sample_size = $actual_samples | .status = \"completed\"" "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    
    echo "✅ Completed $actual_samples simulations for $exp_id"
    echo "   Results: $results_file"
}

# Main command router
case "${1:-}" in
    run)
        if [[ -n "${2:-}" ]]; then
            run_experiment "$2" "${3:-10}"
        else
            echo "Usage: $0 run <experiment_id> [num_iterations]"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 run <experiment_id> [num_iterations]"
        exit 1
        ;;
esac
