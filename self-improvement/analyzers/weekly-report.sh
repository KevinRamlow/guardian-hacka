#!/bin/bash
# weekly-report.sh - Generate human-readable weekly analysis report

set -euo pipefail

SELF_IMPROVEMENT="/root/.openclaw/workspace/self-improvement"
ANALYSIS_DIR="$SELF_IMPROVEMENT/analysis"
REPORTS_DIR="$ANALYSIS_DIR/reports"
TODAY=$(date +%Y-%m-%d)
OUTPUT_FILE="$REPORTS_DIR/weekly-$TODAY.md"

echo "=== Weekly Report Generator ==="

# Load all analysis files
PATTERNS_FILE="$ANALYSIS_DIR/patterns.json"
HYPOTHESES_FILE="$ANALYSIS_DIR/hypotheses.json"
HEATMAP_FILE="$ANALYSIS_DIR/component-heatmap.json"
FAILURES_DIR="$ANALYSIS_DIR/failures"

# Check if analysis files exist
if [[ ! -f "$PATTERNS_FILE" ]] || [[ ! -f "$HEATMAP_FILE" ]]; then
  echo "⚠️  Analysis files not found. Run other analyzers first."
  exit 1
fi

echo "Generating weekly report..."

# Count total failures from last 7 days
TOTAL_FAILURES=0
for i in {0..6}; do
  DATE=$(date -d "$TODAY -$i days" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d)
  FILE="$FAILURES_DIR/$DATE.json"
  if [[ -f "$FILE" ]]; then
    COUNT=$(jq '.failures | length' "$FILE")
    TOTAL_FAILURES=$((TOTAL_FAILURES + COUNT))
  fi
done

# Generate report
{
  echo "# Weekly Self-Improvement Analysis"
  echo ""
  echo "**Period:** $(date -d "$TODAY -7 days" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d) to $TODAY"
  echo "**Generated:** $(date -Iseconds)"
  echo ""
  
  echo "---"
  echo ""
  
  echo "## Executive Summary"
  echo ""
  echo "- **Total Failures Detected:** $TOTAL_FAILURES"
  echo "- **Unique Patterns:** $(jq '.patterns | length' "$PATTERNS_FILE")"
  echo "- **Components Affected:** $(jq '.components | length' "$HEATMAP_FILE")"
  
  if [[ -f "$HYPOTHESES_FILE" ]]; then
    echo "- **Improvement Hypotheses Generated:** $(jq '.hypotheses | length' "$HYPOTHESES_FILE")"
  fi
  
  echo ""
  echo "---"
  echo ""
  
  echo "## Top Failures"
  echo ""
  
  PATTERNS=$(jq -r '.patterns' "$PATTERNS_FILE")
  if [[ "$(echo "$PATTERNS" | jq 'length')" -gt 0 ]]; then
    echo "$PATTERNS" | jq -r 'to_entries[] | 
      "### \(.key + 1). \(.value.category | ascii_upcase) in \(.value.component)\n\n" +
      "- **Frequency:** \(.value.frequency) occurrences\n" +
      "- **Avg Severity:** \(.value.avg_severity)/5\n" +
      "- **Impact Score:** \(.value.impact_score)\n" +
      "- **Fixability:** \(.value.fixability * 100)%\n\n" +
      "**Examples:**\n\(.value.examples | map("- " + .) | join("\n"))\n"'
  else
    echo "*No patterns identified yet.*"
  fi
  
  echo ""
  echo "---"
  echo ""
  
  echo "## Component Health"
  echo ""
  
  AREAS=$(jq -r '.areas' "$HEATMAP_FILE")
  if [[ "$(echo "$AREAS" | jq 'length')" -gt 0 ]]; then
    echo "### Failure Distribution by Area"
    echo ""
    echo "$AREAS" | jq -r '.[] | 
      "**\(.area | gsub("_"; " ") | ascii_upcase):** \(.total_failures) failures (avg severity: \(.avg_severity * 10 | round / 10)/5)"'
    
    echo ""
    echo "### Component Details"
    echo ""
    
    jq -r '.components[0:10] | .[] | 
      "- **\(.component):** \(.failure_count) failures, severity \(.avg_severity)/5, categories: \(.categories | join(", "))"' \
      "$HEATMAP_FILE"
  else
    echo "*No component data available.*"
  fi
  
  echo ""
  echo "---"
  echo ""
  
  echo "## Improvement Proposals"
  echo ""
  
  if [[ -f "$HYPOTHESES_FILE" ]]; then
    HYPOTHESES=$(jq -r '.hypotheses' "$HYPOTHESES_FILE")
    if [[ "$(echo "$HYPOTHESES" | jq 'length')" -gt 0 ]]; then
      echo "$HYPOTHESES" | jq -r 'sort_by(-.expected_improvement_pp) | .[0:5] | to_entries[] |
        "### \(.key + 1). \(.value.description)\n\n" +
        "- **Target:** `\(.value.target_file)`\n" +
        "- **Expected Impact:** +\(.value.expected_improvement_pp)pp\n" +
        "- **Cost:** \(.value.cost_estimate)\n" +
        "- **Risk:** \(.value.risk)\n" +
        "- **Reversible:** \(if .value.reversible then "✅" else "❌" end)\n\n" +
        "**Implementation:**\n> \(.value.implementation_sketch)\n"'
    else
      echo "*No hypotheses generated yet.*"
    fi
  else
    echo "*Hypotheses file not found. Run hypothesis-generator.sh.*"
  fi
  
  echo ""
  echo "---"
  echo ""
  
  echo "## Next Steps"
  echo ""
  echo "1. Review top patterns and validate their accuracy"
  echo "2. Select 1-2 highest-impact hypotheses for implementation"
  echo "3. Test changes in a controlled environment"
  echo "4. Measure improvement against baseline metrics"
  echo "5. Iterate based on results"
  
} > "$OUTPUT_FILE"

echo "✅ Weekly report generated: $OUTPUT_FILE"
