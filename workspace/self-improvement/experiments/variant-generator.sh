#!/bin/bash
# Variant Generator - Creates modified file versions using LLM

set -euo pipefail

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ACTIVE_DIR="$SCRIPT_DIR/active"
VARIANTS_DIR="$SCRIPT_DIR/variants"
BASELINES_DIR="$SCRIPT_DIR/baselines"
WORKSPACE_ROOT="$OC_HOME/workspace"

# Function to generate variant for experiment
generate_variant() {
    local exp_id="$1"
    local exp_file="$ACTIVE_DIR/${exp_id}.json"
    
    if [[ ! -f "$exp_file" ]]; then
        echo "❌ Experiment $exp_id not found"
        return 1
    fi
    
    local target_file=$(jq -r '.target_file' "$exp_file")
    local description=$(jq -r '.description' "$exp_file")
    local proposed_change=$(jq -r '.proposed_change' "$exp_file")
    local hypothesis_id=$(jq -r '.hypothesis_id' "$exp_file")
    
    # Resolve target file path (relative to workspace)
    local target_path="$WORKSPACE_ROOT/$target_file"
    
    if [[ ! -f "$target_path" ]]; then
        echo "❌ Target file not found: $target_path"
        return 1
    fi
    
    # Save baseline (original file)
    local baseline_file="$BASELINES_DIR/${exp_id}-baseline.md"
    cp "$target_path" "$baseline_file"
    echo "📄 Saved baseline: $baseline_file"
    
    # Read original content
    local original_content=$(cat "$target_path")
    
    # Build LLM prompt
    local prompt="You are helping improve an AI agent's configuration files.

**Experiment:** $exp_id
**Hypothesis:** $hypothesis_id
**Goal:** $description
**Proposed Change:** $proposed_change

**Original File Content:**
\`\`\`
$original_content
\`\`\`

**Task:** Generate an improved version of this file that implements the proposed change.

**Requirements:**
- Keep the overall structure and format
- Only modify what's necessary for the improvement
- Maintain readability and clarity
- Preserve all critical safety rules and constraints
- Output ONLY the complete modified file content, no explanations

**Output the complete modified file:**"
    
    # Call Haiku for variant generation
    echo "🤖 Generating variant with Haiku..."
    local variant_content=$(echo "$prompt" | openclaw invoke model \
        --model anthropic/claude-haiku-3.5 \
        --temperature 0.3 \
        --max-tokens 4096 2>/dev/null || echo "")
    
    if [[ -z "$variant_content" ]]; then
        echo "❌ Failed to generate variant"
        return 1
    fi
    
    # Save variant
    local variant_file="$VARIANTS_DIR/${exp_id}-variant.md"
    echo "$variant_content" > "$variant_file"
    echo "✅ Generated variant: $variant_file"
    
    # Generate diff for human review
    local diff_file="$VARIANTS_DIR/${exp_id}-diff.txt"
    diff -u "$baseline_file" "$variant_file" > "$diff_file" || true
    echo "📊 Diff saved: $diff_file"
    
    # Update experiment status
    jq '.status = "variant_generated"' "$exp_file" > "${exp_file}.tmp" && mv "${exp_file}.tmp" "$exp_file"
    
    echo ""
    echo "Variant generation complete for $exp_id"
}

# Main command router
case "${1:-}" in
    generate)
        if [[ -n "${2:-}" ]]; then
            generate_variant "$2"
        else
            echo "Usage: $0 generate <experiment_id>"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 generate <experiment_id>"
        exit 1
        ;;
esac
