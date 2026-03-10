#!/bin/bash
# aggregate-scorecard.sh - Aggregate all metrics into daily scorecard with trends

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$BASE_DIR/metrics"
DAILY_SCORES_DIR="$METRICS_DIR/daily-scores"

TODAY=$(date -u +%Y-%m-%d)
TODAY_FILE="$DAILY_SCORES_DIR/$TODAY.json"
SCORECARD_FILE="$METRICS_DIR/daily-scorecard.json"
TRENDS_FILE="$METRICS_DIR/trends.json"

echo "[aggregate-scorecard] Aggregating metrics for $TODAY..."

if [[ ! -f "$TODAY_FILE" ]]; then
  echo "[aggregate-scorecard] ERROR: No daily scores file found for $TODAY"
  exit 1
fi

# Read today's scores
TODAY_DATA=$(cat "$TODAY_FILE")

# Calculate 7-day rolling averages
echo "[aggregate-scorecard] Calculating 7-day rolling averages..."

DATES=()
for i in {0..6}; do
  DATE=$(date -u -v-${i}d +%Y-%m-%d)
  DATES+=("$DATE")
done

# Initialize accumulators
TASK_COMPLETION_SUM=0
RESPONSE_SPEED_SUM=0
COMMUNICATION_SUM=0
AUTONOMY_SUM=0
PROACTIVENESS_SUM=0
COMPLETED_TASKS_SUM=0
COST_SUM=0
COUNT=0

for DATE in "${DATES[@]}"; do
  FILE="$DAILY_SCORES_DIR/$DATE.json"
  if [[ -f "$FILE" ]]; then
    TASK_COMPLETION=$(jq -r '.conversation_quality.task_completion // 0' "$FILE")
    RESPONSE_SPEED=$(jq -r '.conversation_quality.response_speed // 0' "$FILE")
    COMMUNICATION=$(jq -r '.conversation_quality.communication_quality // 0' "$FILE")
    AUTONOMY=$(jq -r '.conversation_quality.autonomy // 0' "$FILE")
    PROACTIVENESS=$(jq -r '.conversation_quality.proactiveness // 0' "$FILE")
    COMPLETED=$(jq -r '.task_metrics.completed_today // 0' "$FILE")
    COST=$(jq -r '.cost_metrics.estimated_cost_usd // 0' "$FILE")
    
    TASK_COMPLETION_SUM=$(echo "$TASK_COMPLETION_SUM + $TASK_COMPLETION" | bc)
    RESPONSE_SPEED_SUM=$(echo "$RESPONSE_SPEED_SUM + $RESPONSE_SPEED" | bc)
    COMMUNICATION_SUM=$(echo "$COMMUNICATION_SUM + $COMMUNICATION" | bc)
    AUTONOMY_SUM=$(echo "$AUTONOMY_SUM + $AUTONOMY" | bc)
    PROACTIVENESS_SUM=$(echo "$PROACTIVENESS_SUM + $PROACTIVENESS" | bc)
    COMPLETED_TASKS_SUM=$(echo "$COMPLETED_TASKS_SUM + $COMPLETED" | bc)
    COST_SUM=$(echo "$COST_SUM + $COST" | bc)
    COUNT=$((COUNT + 1))
  fi
done

if [[ $COUNT -gt 0 ]]; then
  AVG_TASK_COMPLETION=$(echo "scale=2; $TASK_COMPLETION_SUM / $COUNT" | bc)
  AVG_RESPONSE_SPEED=$(echo "scale=2; $RESPONSE_SPEED_SUM / $COUNT" | bc)
  AVG_COMMUNICATION=$(echo "scale=2; $COMMUNICATION_SUM / $COUNT" | bc)
  AVG_AUTONOMY=$(echo "scale=2; $AUTONOMY_SUM / $COUNT" | bc)
  AVG_PROACTIVENESS=$(echo "scale=2; $PROACTIVENESS_SUM / $COUNT" | bc)
  AVG_COMPLETED=$(echo "scale=2; $COMPLETED_TASKS_SUM / $COUNT" | bc)
  AVG_COST=$(echo "scale=4; $COST_SUM / $COUNT" | bc)
else
  AVG_TASK_COMPLETION=0
  AVG_RESPONSE_SPEED=0
  AVG_COMMUNICATION=0
  AVG_AUTONOMY=0
  AVG_PROACTIVENESS=0
  AVG_COMPLETED=0
  AVG_COST=0
fi

# Detect anomalies (>2 std dev from rolling average)
echo "[aggregate-scorecard] Detecting anomalies..."

ANOMALIES=[]
TODAY_TASK_COMPLETION=$(echo "$TODAY_DATA" | jq -r '.conversation_quality.task_completion // 0')
TODAY_RESPONSE_SPEED=$(echo "$TODAY_DATA" | jq -r '.conversation_quality.response_speed // 0')

# Simple anomaly detection: if today's score differs by >2 from 7d average
TASK_DIFF=$(echo "$TODAY_TASK_COMPLETION - $AVG_TASK_COMPLETION" | bc | awk '{print ($1<0)?-$1:$1}')
if (( $(echo "$TASK_DIFF > 2" | bc -l) )); then
  ANOMALIES=$(echo "$ANOMALIES" | jq '. + ["task_completion: today='$TODAY_TASK_COMPLETION' vs 7d_avg='$AVG_TASK_COMPLETION'"]')
fi

SPEED_DIFF=$(echo "$TODAY_RESPONSE_SPEED - $AVG_RESPONSE_SPEED" | bc | awk '{print ($1<0)?-$1:$1}')
if (( $(echo "$SPEED_DIFF > 2" | bc -l) )); then
  ANOMALIES=$(echo "$ANOMALIES" | jq '. + ["response_speed: today='$TODAY_RESPONSE_SPEED' vs 7d_avg='$AVG_RESPONSE_SPEED'"]')
fi

# Write daily scorecard
cat > "$SCORECARD_FILE" <<EOF
{
  "date": "$TODAY",
  "current": $(cat "$TODAY_FILE"),
  "rolling_7d": {
    "task_completion": $AVG_TASK_COMPLETION,
    "response_speed": $AVG_RESPONSE_SPEED,
    "communication_quality": $AVG_COMMUNICATION,
    "autonomy": $AVG_AUTONOMY,
    "proactiveness": $AVG_PROACTIVENESS,
    "completed_tasks_per_day": $AVG_COMPLETED,
    "cost_per_day_usd": $AVG_COST
  },
  "anomalies": $ANOMALIES
}
EOF

# Write trends file
cat > "$TRENDS_FILE" <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "period": "7_days",
  "averages": {
    "task_completion": $AVG_TASK_COMPLETION,
    "response_speed": $AVG_RESPONSE_SPEED,
    "communication_quality": $AVG_COMMUNICATION,
    "autonomy": $AVG_AUTONOMY,
    "proactiveness": $AVG_PROACTIVENESS,
    "completed_tasks_per_day": $AVG_COMPLETED,
    "cost_per_day_usd": $AVG_COST
  }
}
EOF

echo "[aggregate-scorecard] ✅ Scorecard written to $SCORECARD_FILE"
echo "[aggregate-scorecard] ✅ Trends written to $TRENDS_FILE"
cat "$SCORECARD_FILE" | jq .
