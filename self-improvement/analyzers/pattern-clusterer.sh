#!/bin/bash
# pattern-clusterer.sh - Group failures into patterns and rank by impact

set -euo pipefail

SELF_IMPROVEMENT="/root/.openclaw/workspace/self-improvement"
ANALYSIS_DIR="$SELF_IMPROVEMENT/analysis"
FAILURES_DIR="$ANALYSIS_DIR/failures"
OUTPUT_FILE="$ANALYSIS_DIR/patterns.json"

echo "=== Pattern Clusterer ==="

# Collect all failure files
FAILURE_FILES=("$FAILURES_DIR"/*.json)
if [[ ! -f "${FAILURE_FILES[0]}" ]]; then
  echo "⚠️  No failure files found. Creating empty patterns."
  echo '{"patterns":[],"updated":"'"$(date -Iseconds)"'"}' > "$OUTPUT_FILE"
  exit 0
fi

echo "Found ${#FAILURE_FILES[@]} failure file(s)"

# Merge all failures into one array
ALL_FAILURES="[]"
for FILE in "${FAILURE_FILES[@]}"; do
  FAILURES=$(jq -r '.failures' "$FILE" 2>/dev/null || echo "[]")
  ALL_FAILURES=$(jq -s '.[0] + .[1]' <(echo "$ALL_FAILURES") <(echo "$FAILURES"))
done

TOTAL_FAILURES=$(echo "$ALL_FAILURES" | jq 'length')
echo "Total failures across all files: $TOTAL_FAILURES"

if [[ $TOTAL_FAILURES -eq 0 ]]; then
  echo "⚠️  No failures to cluster. Creating empty patterns."
  echo '{"patterns":[],"updated":"'"$(date -Iseconds)"'"}' > "$OUTPUT_FILE"
  exit 0
fi

# Group by category + component
PATTERNS=$(echo "$ALL_FAILURES" | jq -r '
  group_by(.category + "_" + .component) | 
  map({
    category: .[0].category,
    component: .[0].component,
    frequency: length,
    avg_severity: (map(.severity) | add / length | floor),
    examples: map(.description) | .[0:3]
  })
')

# Calculate fixability heuristic
FIXABILITY_MAP='{
  "SOUL.md": 0.9,
  "MEMORY.md": 0.7,
  "HEARTBEAT.md": 0.7,
  "AGENTS.md": 0.8,
  "openclaw.json": 0.5,
  "config": 0.5,
  "memory": 0.7,
  "tool": 0.6
}'

# Add fixability and impact score
PATTERNS_SCORED=$(echo "$PATTERNS" | jq --argjson fixmap "$FIXABILITY_MAP" '
  map(. + {
    fixability: (
      if ($fixmap[.component] != null) then $fixmap[.component]
      elif (.component | startswith("skill")) then 0.8
      elif (.component | contains("tool")) then 0.6
      else 0.5 end
    )
  }) |
  map(. + {
    impact_score: (.avg_severity * .frequency * .fixability)
  }) |
  sort_by(-.impact_score)
')

# Take top 5
TOP_PATTERNS=$(echo "$PATTERNS_SCORED" | jq '.[0:5]')

# Build output
OUTPUT=$(jq -n \
  --argjson patterns "$TOP_PATTERNS" \
  --arg updated "$(date -Iseconds)" \
  --arg total "$TOTAL_FAILURES" \
  '{
    patterns: $patterns,
    total_failures: ($total | tonumber),
    updated: $updated
  }')

echo "$OUTPUT" > "$OUTPUT_FILE"
echo "✅ Pattern clustering complete: $OUTPUT_FILE"
echo "Identified $(echo "$TOP_PATTERNS" | jq 'length') top patterns"
