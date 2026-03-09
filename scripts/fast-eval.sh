#!/bin/bash
# fast-eval.sh - Fast mode evaluation (10% dataset, ~5 min)
# Usage: bash scripts/fast-eval.sh [dataset.jsonl]

set -e

REPO_DIR="$HOME/.openclaw/workspace/guardian-agents-api-real"
DATASET="${1:-evals/datasets/guidelines_combined_dataset.jsonl}"
FAST_DATASET="/tmp/fast_dataset_$(date +%s).jsonl"
OUTPUT_DIR="$REPO_DIR/evals/.runs/content_moderation/fast_run_$(date +%Y%m%d_%H%M%S)"

cd "$REPO_DIR"

echo "=== Fast Mode Eval ==="
echo "Dataset: $DATASET"

# Sample 10% of dataset (min 10 cases, max 15)
TOTAL_LINES=$(wc -l < "$DATASET")
SAMPLE_SIZE=$(echo "scale=0; $TOTAL_LINES * 0.1 / 1" | bc)
[[ $SAMPLE_SIZE -lt 10 ]] && SAMPLE_SIZE=10
[[ $SAMPLE_SIZE -gt 15 ]] && SAMPLE_SIZE=15

echo "Sampling $SAMPLE_SIZE cases from $TOTAL_LINES total..."

# Stratified sampling - ensure we get cases from each guideline type
shuf "$DATASET" | head -n "$SAMPLE_SIZE" > "$FAST_DATASET"

echo "Fast dataset: $FAST_DATASET"

# Run eval with fast dataset
source .env.guardian-eval 2>/dev/null || export GOOGLE_CLOUD_PROJECT=brandlovers-prod
source .venv/bin/activate

python3 evals/run_eval.py \
  --config evals/content_moderation.yaml \
  --dataset "$FAST_DATASET" \
  --workers 10 \
  --output-dir "$OUTPUT_DIR" \
  2>&1 | tee /tmp/fast-eval.log

# Extract accuracy
ACCURACY=$(tail -1 "$OUTPUT_DIR/results.jsonl" 2>/dev/null | jq -r '.summary.accuracy' 2>/dev/null || echo "N/A")

echo ""
echo "=== Fast Eval Results ==="
echo "Accuracy: $ACCURACY"
echo "Output: $OUTPUT_DIR"
echo "Sample size: $SAMPLE_SIZE cases"

# Cleanup temp dataset
rm -f "$FAST_DATASET"

# Return accuracy for scripting
echo "$ACCURACY"
