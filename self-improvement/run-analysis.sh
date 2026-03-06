#!/bin/bash
# run-analysis.sh - Master runner for Phase 2 analysis engine

set -euo pipefail

SELF_IMPROVEMENT="/root/.openclaw/workspace/self-improvement"
ANALYZERS_DIR="$SELF_IMPROVEMENT/analyzers"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Self-Improvement Phase 2: Analysis Engine             ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

START_TIME=$(date +%s)

# Make all analyzers executable
chmod +x "$ANALYZERS_DIR"/*.sh

echo "Running analysis pipeline..."
echo ""

# 1. Failure Analyzer
echo "▶ Step 1/5: Failure Analyzer"
bash "$ANALYZERS_DIR/failure-analyzer.sh"
echo ""

# 2. Pattern Clusterer
echo "▶ Step 2/5: Pattern Clusterer"
bash "$ANALYZERS_DIR/pattern-clusterer.sh"
echo ""

# 3. Root Cause Mapper
echo "▶ Step 3/5: Root Cause Mapper"
bash "$ANALYZERS_DIR/root-cause-mapper.sh"
echo ""

# 4. Hypothesis Generator
echo "▶ Step 4/5: Hypothesis Generator"
bash "$ANALYZERS_DIR/hypothesis-generator.sh"
echo ""

# 5. Weekly Report
echo "▶ Step 5/5: Weekly Report Generator"
bash "$ANALYZERS_DIR/weekly-report.sh"
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Analysis Complete                                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Duration: ${DURATION}s"
echo ""
echo "Output files:"
echo "  - Failures:  analysis/failures/$(date +%Y-%m-%d).json"
echo "  - Patterns:  analysis/patterns.json"
echo "  - Heatmap:   analysis/component-heatmap.json"
echo "  - Hypotheses: analysis/hypotheses.json"
echo "  - Proposals: analysis/improvement-proposals.md"
echo "  - Report:    analysis/reports/weekly-$(date +%Y-%m-%d).md"
echo ""
echo "Next: Review analysis/reports/weekly-$(date +%Y-%m-%d).md"
