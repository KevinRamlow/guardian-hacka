#!/bin/bash
# hypothesis-generator.sh - Generate improvement hypotheses from top patterns

set -euo pipefail

SELF_IMPROVEMENT="/root/.openclaw/workspace/self-improvement"
ANALYSIS_DIR="$SELF_IMPROVEMENT/analysis"
PATTERNS_FILE="$ANALYSIS_DIR/patterns.json"
HYPOTHESES_FILE="$ANALYSIS_DIR/hypotheses.json"
PROPOSALS_FILE="$ANALYSIS_DIR/improvement-proposals.md"
ANTHROPIC_API_KEY="[REDACTED]"

echo "=== Hypothesis Generator ==="

if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "⚠️  Patterns file not found. Run pattern-clusterer.sh first."
  exit 1
fi

# Read top 3 patterns
TOP_PATTERNS=$(jq -r '.patterns[0:3]' "$PATTERNS_FILE")
PATTERN_COUNT=$(echo "$TOP_PATTERNS" | jq 'length')

echo "Generating hypotheses for top $PATTERN_COUNT patterns..."

if [[ $PATTERN_COUNT -eq 0 ]]; then
  echo "⚠️  No patterns to analyze. Creating empty hypotheses."
  echo '{"hypotheses":[],"updated":"'"$(date -Iseconds)"'"}' > "$HYPOTHESES_FILE"
  echo "# Improvement Proposals\n\nNo patterns identified yet." > "$PROPOSALS_FILE"
  exit 0
fi

# Build prompt
PROMPT="You are analyzing failure patterns in an AI orchestrator (Anton) and generating concrete improvement hypotheses.

TOP FAILURE PATTERNS:
$(echo "$TOP_PATTERNS" | jq -r 'to_entries[] | "Pattern \(.key + 1): \(.value.category) in \(.value.component) (frequency: \(.value.frequency), severity: \(.value.avg_severity), impact: \(.value.impact_score))\nExamples:\n- \(.value.examples | join("\n- "))\n"')

For EACH of the top 3 patterns above, generate 3-5 improvement hypotheses.

Each hypothesis should include:
- description: What to change (1-2 sentences)
- target_file: Specific file to modify (e.g., SOUL.md, skills/github/SKILL.md, AGENTS.md)
- expected_improvement_pp: Expected improvement in percentage points (realistic estimate)
- cost_estimate: Implementation effort (low/medium/high)
- risk: Risk level (low/medium/high)
- reversible: Whether change can be easily reverted (true/false)
- implementation_sketch: 2-3 sentences describing the change

Output ONLY valid JSON array:
[
  {
    \"pattern_id\": 0,
    \"description\": \"...\",
    \"target_file\": \"SOUL.md\",
    \"expected_improvement_pp\": 5,
    \"cost_estimate\": \"low\",
    \"risk\": \"low\",
    \"reversible\": true,
    \"implementation_sketch\": \"...\"
  }
]"

# Call Claude Haiku
echo "Calling Claude Haiku for hypothesis generation..."
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

# Extract hypotheses
HYPOTHESES=$(echo "$RESPONSE" | jq -r '.content[0].text' | sed 's/```json//g' | sed 's/```//g' | jq -c .)

# Save JSON
OUTPUT=$(jq -n \
  --argjson hypotheses "$HYPOTHESES" \
  --arg updated "$(date -Iseconds)" \
  '{
    hypotheses: $hypotheses,
    updated: $updated
  }')

echo "$OUTPUT" > "$HYPOTHESES_FILE"

# Generate human-readable markdown
{
  echo "# Improvement Proposals"
  echo ""
  echo "Generated: $(date -Iseconds)"
  echo ""
  echo "## Top Patterns"
  echo ""
  echo "$TOP_PATTERNS" | jq -r 'to_entries[] | "### Pattern \(.key + 1): \(.value.category) in \(.value.component)\n\n- **Frequency:** \(.value.frequency)\n- **Avg Severity:** \(.value.avg_severity)\n- **Impact Score:** \(.value.impact_score)\n- **Fixability:** \(.value.fixability)\n\n**Examples:**\n\(.value.examples | map("- " + .) | join("\n"))\n"'
  
  echo ""
  echo "## Proposed Improvements"
  echo ""
  
  echo "$HYPOTHESES" | jq -r 'group_by(.pattern_id)[] | 
    "\n### For Pattern \(.[0].pattern_id + 1)\n\n" + 
    (to_entries[] | 
      "#### Hypothesis \(.key + 1): \(.value.description)\n\n" +
      "- **Target:** `\(.value.target_file)`\n" +
      "- **Expected Improvement:** +\(.value.expected_improvement_pp)pp\n" +
      "- **Cost:** \(.value.cost_estimate)\n" +
      "- **Risk:** \(.value.risk)\n" +
      "- **Reversible:** \(if .value.reversible then "✅ Yes" else "❌ No" end)\n\n" +
      "**Implementation:**\n\(.value.implementation_sketch)\n"
    )'
} > "$PROPOSALS_FILE"

echo "✅ Hypothesis generation complete"
echo "   JSON: $HYPOTHESES_FILE"
echo "   Markdown: $PROPOSALS_FILE"
echo "Generated $(echo "$HYPOTHESES" | jq 'length') hypotheses"
