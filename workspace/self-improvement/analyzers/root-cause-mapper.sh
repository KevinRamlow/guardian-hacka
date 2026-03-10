#!/bin/bash
# root-cause-mapper.sh - Map failures to architectural components

set -euo pipefail

SELF_IMPROVEMENT="/Users/fonsecabc/.openclaw/workspace/self-improvement"
ANALYSIS_DIR="$SELF_IMPROVEMENT/analysis"
FAILURES_DIR="$ANALYSIS_DIR/failures"
OUTPUT_FILE="$ANALYSIS_DIR/component-heatmap.json"

echo "=== Root Cause Mapper ==="

# Collect all failures
FAILURE_FILES=("$FAILURES_DIR"/*.json)
if [[ ! -f "${FAILURE_FILES[0]}" ]]; then
  echo "⚠️  No failure files found. Creating empty heatmap."
  echo '{"components":[],"updated":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$OUTPUT_FILE"
  exit 0
fi

echo "Analyzing failure distribution across components..."

# Merge all failures
ALL_FAILURES="[]"
for FILE in "${FAILURE_FILES[@]}"; do
  FAILURES=$(jq -r '.failures' "$FILE" 2>/dev/null || echo "[]")
  ALL_FAILURES=$(jq -s '.[0] + .[1]' <(echo "$ALL_FAILURES") <(echo "$FAILURES"))
done

TOTAL_FAILURES=$(echo "$ALL_FAILURES" | jq 'length')
echo "Total failures: $TOTAL_FAILURES"

if [[ $TOTAL_FAILURES -eq 0 ]]; then
  echo "⚠️  No failures to map. Creating empty heatmap."
  echo '{"components":[],"updated":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$OUTPUT_FILE"
  exit 0
fi

# Component taxonomy mapping
COMPONENT_MAP='{
  "SOUL.md": "personality_communication",
  "MEMORY.md": "long_term_knowledge",
  "HEARTBEAT.md": "monitoring",
  "AGENTS.md": "operational_rules",
  "openclaw.json": "configuration",
  "config": "configuration",
  "memory": "short_term_context",
  "tool": "tool_implementation"
}'

# Group by component and calculate stats
HEATMAP=$(echo "$ALL_FAILURES" | jq --argjson compmap "$COMPONENT_MAP" '
  group_by(.component) |
  map({
    component: .[0].component,
    area: (
      if ($compmap[.[0].component] != null) then $compmap[.[0].component]
      elif (.[0].component | startswith("skill")) then "tool_implementation"
      elif (.[0].component | contains("tool")) then "tool_implementation"
      else "other" end
    ),
    failure_count: length,
    avg_severity: (map(.severity) | add / length | . * 10 | round / 10),
    categories: (map(.category) | unique),
    severity_distribution: (
      group_by(.severity) | 
      map({
        severity: .[0].severity,
        count: length
      })
    )
  }) |
  sort_by(-.failure_count)
')

# Calculate area-level rollups
AREA_ROLLUP=$(echo "$HEATMAP" | jq 'group_by(.area) | map({
  area: .[0].area,
  total_failures: (map(.failure_count) | add),
  components: (map(.component)),
  avg_severity: (map(.avg_severity * .failure_count) | add) / (map(.failure_count) | add)
}) | sort_by(-.total_failures)')

# Build output
OUTPUT=$(jq -n \
  --argjson components "$HEATMAP" \
  --argjson areas "$AREA_ROLLUP" \
  --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg total "$TOTAL_FAILURES" \
  '{
    components: $components,
    areas: $areas,
    total_failures: ($total | tonumber),
    updated: $updated
  }')

echo "$OUTPUT" > "$OUTPUT_FILE"
echo "✅ Root cause mapping complete: $OUTPUT_FILE"
echo "Component distribution:"
echo "$HEATMAP" | jq -r '.[] | "  \(.component): \(.failure_count) failures (avg severity: \(.avg_severity))"'
