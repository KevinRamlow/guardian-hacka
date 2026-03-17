#!/bin/bash
# Guardian eval status monitor
# Usage: bash scripts/guardian-eval-status.sh

PID=$(cat /tmp/guardian-eval.pid 2>/dev/null)

if [ -z "$PID" ] || ! ps -p $PID > /dev/null 2>&1; then
  echo "❌ No eval running (no valid PID found)"
  
  # Check if recently completed
  LATEST_RUN=$(ls -td ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_* 2>/dev/null | head -1)
  if [ -n "$LATEST_RUN" ] && [ -f "$LATEST_RUN/progress_meta.json" ]; then
    STATUS=$(jq -r '.status // "unknown"' "$LATEST_RUN/progress_meta.json")
    if [ "$STATUS" = "completed" ]; then
      echo ""
      echo "ℹ️  Latest run completed: $(basename $LATEST_RUN)"
      ACCURACY=$(jq -r '.metrics.overall.answer.exact // "N/A"' "$LATEST_RUN/metrics.json" 2>/dev/null)
      echo "   Accuracy: $ACCURACY"
    fi
  fi
  exit 1
fi

# Find run dir
RUN_DIR=$(ls -td ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_* 2>/dev/null | head -1)

if [ -z "$RUN_DIR" ] || [ ! -f "$RUN_DIR/progress_meta.json" ]; then
  ELAPSED=$(ps -p $PID -o etime= | xargs)
  echo "⚠️  Eval running (PID $PID, elapsed: $ELAPSED) but no progress file found yet"
  echo "   Wait a few seconds for eval to initialize..."
  exit 0
fi

# Show progress
echo "✓ Eval running: PID $PID"
echo ""

# Parse progress
COMPLETED=$(jq -r '.completed // 0' "$RUN_DIR/progress_meta.json")
TOTAL=$(jq -r '.total // 0' "$RUN_DIR/progress_meta.json")
STATUS=$(jq -r '.status // "unknown"' "$RUN_DIR/progress_meta.json")

if [ "$TOTAL" -gt 0 ]; then
  PERCENT=$((COMPLETED * 100 / TOTAL))
  echo "Progress: $COMPLETED/$TOTAL ($PERCENT%)"
else
  echo "Progress: initializing..."
fi

echo "Status: $STATUS"
echo "Run dir: $(basename $RUN_DIR)"
echo ""

# Show recent activity
echo "Recent activity (last 5 test cases):"
tail -5 "$RUN_DIR/progress.jsonl" 2>/dev/null | jq -r '
  "  test_idx=\(.test_idx) | score=\(.aggregate_score) | latency=\(.latency|floor)s"
' || echo "  (no results yet)"

# Show errors if any
ERROR_COUNT=$(grep -c '"error":' "$RUN_DIR/progress.jsonl" 2>/dev/null || echo 0)
if [ "$ERROR_COUNT" -gt 0 ]; then
  echo ""
  echo "⚠️  Errors: $ERROR_COUNT"
  echo "Recent errors:"
  grep '"error":' "$RUN_DIR/progress.jsonl" | tail -3 | jq -r '
    "  test_idx=\(.test_idx) | \(.error)"
  '
fi

# Show elapsed time and ETA
ELAPSED=$(ps -p $PID -o etime= | xargs)
echo ""
echo "Elapsed: $ELAPSED"

if [ "$COMPLETED" -gt 5 ] && [ "$TOTAL" -gt 0 ]; then
  # Rough ETA calculation
  START_TIME=$(jq -r '.start_time // empty' "$RUN_DIR/progress_meta.json")
  if [ -n "$START_TIME" ]; then
    NOW=$(date +%s)
    START_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${START_TIME:0:19}" +%s 2>/dev/null || echo $NOW)
    ELAPSED_S=$((NOW - START_TS))
    AVG_PER_CASE=$((ELAPSED_S / COMPLETED))
    REMAINING=$((TOTAL - COMPLETED))
    ETA_S=$((REMAINING * AVG_PER_CASE))
    ETA_MIN=$((ETA_S / 60))
    echo "ETA: ~${ETA_MIN}min (avg ${AVG_PER_CASE}s/case)"
  fi
fi
