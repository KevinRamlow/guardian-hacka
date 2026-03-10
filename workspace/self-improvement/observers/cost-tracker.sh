#!/bin/bash
# cost-tracker.sh - Track token usage and estimated costs

set -euo pipefail

OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$BASE_DIR/metrics/daily-scores"
MEMORY_DIR="$OC_HOME/workspace/memory"

TODAY=$(date -u +%Y-%m-%d)
OUTPUT_FILE="$METRICS_DIR/$TODAY.json"
MEMORY_FILE="$MEMORY_DIR/$TODAY.md"

echo "[cost-tracker] Estimating token usage and costs..."

# Rough estimation based on memory file size
# Assume: 1 char ≈ 0.25 tokens (conservative), Claude Sonnet 4.5 pricing
TOKENS_INPUT=0
TOKENS_OUTPUT=0
COST_ESTIMATE=0

if [[ -f "$MEMORY_FILE" ]]; then
  CHARS=$(wc -c < "$MEMORY_FILE")
  # Estimate input tokens (conversations + context)
  TOKENS_INPUT=$(echo "scale=0; $CHARS * 0.3" | bc)
  # Estimate output tokens (responses, roughly 30% of input)
  TOKENS_OUTPUT=$(echo "scale=0; $TOKENS_INPUT * 0.3" | bc)
  
  # Claude Sonnet 4.5 pricing (per million tokens)
  # Input: $3/MTok, Output: $15/MTok
  COST_INPUT=$(echo "scale=4; $TOKENS_INPUT * 3 / 1000000" | bc)
  COST_OUTPUT=$(echo "scale=4; $TOKENS_OUTPUT * 15 / 1000000" | bc)
  COST_ESTIMATE=$(echo "scale=4; $COST_INPUT + $COST_OUTPUT" | bc)
fi

# Cost per task (if tasks completed)
COST_PER_TASK=0
if [[ -f "$OUTPUT_FILE" ]]; then
  TASKS_COMPLETED=$(cat "$OUTPUT_FILE" | jq -r '.task_metrics.completed_today // 0')
  if [[ $TASKS_COMPLETED -gt 0 ]]; then
    COST_PER_TASK=$(echo "scale=4; $COST_ESTIMATE / $TASKS_COMPLETED" | bc)
  fi
fi

# Merge into existing output file or create new
if [[ -f "$OUTPUT_FILE" ]]; then
  EXISTING=$(cat "$OUTPUT_FILE")
  MERGED=$(echo "$EXISTING" | jq ". + {
    \"cost_metrics\": {
      \"tokens_input\": $TOKENS_INPUT,
      \"tokens_output\": $TOKENS_OUTPUT,
      \"estimated_cost_usd\": $COST_ESTIMATE,
      \"cost_per_task_usd\": $COST_PER_TASK
    }
  }")
  echo "$MERGED" > "$OUTPUT_FILE"
else
  cat > "$OUTPUT_FILE" <<EOF
{
  "date": "$TODAY",
  "cost_metrics": {
    "tokens_input": $TOKENS_INPUT,
    "tokens_output": $TOKENS_OUTPUT,
    "estimated_cost_usd": $COST_ESTIMATE,
    "cost_per_task_usd": $COST_PER_TASK
  }
}
EOF
fi

echo "[cost-tracker] ✅ Cost metrics written to $OUTPUT_FILE"
cat "$OUTPUT_FILE" | jq .cost_metrics
