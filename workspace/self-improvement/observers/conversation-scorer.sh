#!/bin/bash
# conversation-scorer.sh - Score Anton's conversation quality using Claude Haiku

set -euo pipefail
OC_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
source "$OC_HOME/.env" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$BASE_DIR/metrics/daily-scores"
MEMORY_DIR="$OC_HOME/workspace/memory"

# Get today and yesterday in YYYY-MM-DD format
TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(date -u -v-1d +%Y-%m-%d)

TODAY_FILE="$MEMORY_DIR/$TODAY.md"
YESTERDAY_FILE="$MEMORY_DIR/$YESTERDAY.md"
OUTPUT_FILE="$METRICS_DIR/$TODAY.json"

echo "[conversation-scorer] Reading memory files..."

# Combine today + yesterday memory
MEMORY_CONTENT=""
if [[ -f "$YESTERDAY_FILE" ]]; then
  MEMORY_CONTENT+="# Yesterday ($YESTERDAY)"$'\n'
  MEMORY_CONTENT+=$(head -n 500 "$YESTERDAY_FILE")
  MEMORY_CONTENT+=$'\n\n'
fi

if [[ -f "$TODAY_FILE" ]]; then
  MEMORY_CONTENT+="# Today ($TODAY)"$'\n'
  MEMORY_CONTENT+=$(head -n 500 "$TODAY_FILE")
else
  echo "[conversation-scorer] No memory file for today, using yesterday only"
fi

if [[ -z "$MEMORY_CONTENT" ]]; then
  echo "[conversation-scorer] No memory content found, outputting default low scores"
  cat > "$OUTPUT_FILE" <<EOF
{
  "date": "$TODAY",
  "conversation_quality": {
    "task_completion": 5,
    "response_speed": 5,
    "communication_quality": 5,
    "autonomy": 5,
    "proactiveness": 5
  }
}
EOF
  exit 0
fi

# Build prompt for Claude
PROMPT="You are analyzing conversation logs between Anton (an AI orchestrator) and Caio (a software engineer).

Score Anton's performance on these 5 dimensions (1-10 scale):
1. **task_completion**: Did Anton complete assigned tasks? Did work get shipped?
2. **response_speed**: Was Anton fast and efficient, or slow and verbose?
3. **communication_quality**: Clear, direct, data-driven communication?
4. **autonomy**: Did Anton work independently or need constant hand-holding?
5. **proactiveness**: Did Anton anticipate needs or just react?

Conversation logs:
\`\`\`
$MEMORY_CONTENT
\`\`\`

Respond ONLY with valid JSON in this exact format:
{
  \"task_completion\": <1-10>,
  \"response_speed\": <1-10>,
  \"communication_quality\": <1-10>,
  \"autonomy\": <1-10>,
  \"proactiveness\": <1-10>,
  \"reasoning\": \"<one sentence explaining the scores>\"
}"

echo "[conversation-scorer] Calling Claude Haiku API..."

# Call Anthropic API
RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{
    \"model\": \"claude-3-haiku-20240307\",
    \"max_tokens\": 500,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": $(echo "$PROMPT" | jq -Rs .)
    }]
  }")

# Extract scores from response
SCORES=$(echo "$RESPONSE" | jq -r '.content[0].text' | jq -c .)

if [[ -z "$SCORES" ]] || [[ "$SCORES" == "null" ]]; then
  echo "[conversation-scorer] ERROR: Failed to get scores from Claude"
  echo "Response: $RESPONSE"
  exit 1
fi

# Build output JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "date": "$TODAY",
  "conversation_quality": $SCORES
}
EOF

echo "[conversation-scorer] ✅ Scores written to $OUTPUT_FILE"
cat "$OUTPUT_FILE" | jq .
