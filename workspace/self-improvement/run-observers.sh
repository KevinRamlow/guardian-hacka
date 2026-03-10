#!/bin/bash
# run-observers.sh - Master runner for all observation scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBSERVERS_DIR="$SCRIPT_DIR/observers"
LOG_FILE="$SCRIPT_DIR/metrics/observer-runs.log"

echo "========================================" | tee -a "$LOG_FILE"
echo "Observer Run: $(date -u +%Y-%m-%d\ %H:%M:%S) UTC" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Make all scripts executable
chmod +x "$OBSERVERS_DIR"/*.sh

FAILED=0

# Run conversation scorer
echo "" | tee -a "$LOG_FILE"
echo "[1/4] Running conversation-scorer.sh..." | tee -a "$LOG_FILE"
if bash "$OBSERVERS_DIR/conversation-scorer.sh" 2>&1 | tee -a "$LOG_FILE"; then
  echo "✅ conversation-scorer.sh completed" | tee -a "$LOG_FILE"
else
  echo "❌ conversation-scorer.sh failed (exit $?)" | tee -a "$LOG_FILE"
  FAILED=$((FAILED + 1))
fi

# Run task tracker
echo "" | tee -a "$LOG_FILE"
echo "[2/4] Running task-tracker.sh..." | tee -a "$LOG_FILE"
if bash "$OBSERVERS_DIR/task-tracker.sh" 2>&1 | tee -a "$LOG_FILE"; then
  echo "✅ task-tracker.sh completed" | tee -a "$LOG_FILE"
else
  echo "❌ task-tracker.sh failed (exit $?)" | tee -a "$LOG_FILE"
  FAILED=$((FAILED + 1))
fi

# Run cost tracker
echo "" | tee -a "$LOG_FILE"
echo "[3/4] Running cost-tracker.sh..." | tee -a "$LOG_FILE"
if bash "$OBSERVERS_DIR/cost-tracker.sh" 2>&1 | tee -a "$LOG_FILE"; then
  echo "✅ cost-tracker.sh completed" | tee -a "$LOG_FILE"
else
  echo "❌ cost-tracker.sh failed (exit $?)" | tee -a "$LOG_FILE"
  FAILED=$((FAILED + 1))
fi

# Run aggregator
echo "" | tee -a "$LOG_FILE"
echo "[4/4] Running aggregate-scorecard.sh..." | tee -a "$LOG_FILE"
if bash "$OBSERVERS_DIR/aggregate-scorecard.sh" 2>&1 | tee -a "$LOG_FILE"; then
  echo "✅ aggregate-scorecard.sh completed" | tee -a "$LOG_FILE"
else
  echo "❌ aggregate-scorecard.sh failed (exit $?)" | tee -a "$LOG_FILE"
  FAILED=$((FAILED + 1))
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All observers completed successfully" | tee -a "$LOG_FILE"
  exit 0
else
  echo "⚠️  $FAILED observer(s) failed" | tee -a "$LOG_FILE"
  exit 1
fi
