#!/bin/bash
# failure-analyzer.sh - Extract and classify failures from memory logs

set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
SELF_IMPROVEMENT="$WORKSPACE/self-improvement"
ANALYSIS_DIR="$SELF_IMPROVEMENT/analysis"
FAILURES_DIR="$ANALYSIS_DIR/failures"
MEMORY_DIR="$WORKSPACE/memory"
METRICS_DIR="$SELF_IMPROVEMENT/metrics"
ANTHROPIC_API_KEY="[REDACTED]"

TODAY=$(date +%Y-%m-%d)
OUTPUT_FILE="$FAILURES_DIR/$TODAY.json"

echo "=== Failure Analyzer ==="
echo "Analyzing last 7 days of memory logs..."

# Get last 7 days of memory files
MEMORY_FILES=()
for i in {0..6}; do
  DATE=$(date -d "$TODAY -$i days" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d)
  FILE="$MEMORY_DIR/$DATE.md"
  if [[ -f "$FILE" ]]; then
    MEMORY_FILES+=("$FILE")
  fi
done

if [[ ${#MEMORY_FILES[@]} -eq 0 ]]; then
  echo "⚠️  No memory files found for last 7 days. Creating empty output."
  echo '{"date":"'"$TODAY"'","failures":[],"source":"no_memory_files"}' > "$OUTPUT_FILE"
  exit 0
fi

echo "Found ${#MEMORY_FILES[@]} memory files"

# Concatenate memory content
MEMORY_CONTENT=""
for FILE in "${MEMORY_FILES[@]}"; do
  MEMORY_CONTENT+="=== $(basename $FILE) ===\n"
  MEMORY_CONTENT+="$(cat "$FILE")\n\n"
done

# Read Phase 1 metrics if available (graceful degradation)
METRICS_CONTENT=""
SCORECARD="$METRICS_DIR/daily-scorecard.json"
if [[ -f "$SCORECARD" ]]; then
  METRICS_CONTENT="Daily Scorecard:\n$(cat "$SCORECARD")\n\n"
  echo "✓ Phase 1 metrics found"
else
  echo "⚠️  Phase 1 metrics not found (graceful degradation)"
fi

# Build prompt for Claude Haiku
PROMPT="You are analyzing an AI orchestrator's memory logs to identify failures, mistakes, corrections, and retries.

MEMORY LOGS (last 7 days):
$MEMORY_CONTENT

${METRICS_CONTENT}

TASK:
Extract ALL failures, mistakes, corrections, or retry attempts from these logs.

For each failure, classify it into ONE of these categories:
- knowledge_gap: Missing information or understanding
- reasoning_error: Logical mistake or wrong conclusion
- tool_misuse: Incorrect use of tools/commands
- communication_mismatch: Misunderstood user intent or unclear response
- speed_issue: Too slow, inefficient approach
- context_loss: Forgot something that was mentioned before

For each failure, determine:
- description: Brief summary (1-2 sentences)
- category: One of the above
- severity: 1-5 (1=minor, 5=critical)
- component: Which file/system is most relevant (SOUL.md, skill name, memory, tool, config, openclaw.json, AGENTS.md, HEARTBEAT.md)
- timestamp: Best estimate from context

Output ONLY valid JSON array with this structure:
[
  {
    \"description\": \"...\",
    \"category\": \"...\",
    \"severity\": 3,
    \"component\": \"...\",
    \"timestamp\": \"2026-03-05T15:30:00Z\"
  }
]

If no failures found, output: []"

# Call Claude Haiku
echo "Calling Claude Haiku for analysis..."
RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "max_tokens": 4096,
    "messages": [
      {
        "role": "user",
        "content": '"$(echo "$PROMPT" | jq -Rs .)"'
      }
    ]
  }')

# Extract content from response
FAILURES=$(echo "$RESPONSE" | jq -r '.content[0].text' | sed 's/```json//g' | sed 's/```//g' | jq -c .)

# Wrap in metadata
OUTPUT=$(jq -n \
  --arg date "$TODAY" \
  --argjson failures "$FAILURES" \
  '{
    date: $date,
    analyzed_files: '"${#MEMORY_FILES[@]}"',
    failures: $failures,
    source: "memory_logs"
  }')

echo "$OUTPUT" > "$OUTPUT_FILE"
echo "✅ Failure analysis complete: $OUTPUT_FILE"
echo "Found $(echo "$FAILURES" | jq 'length') failures"
