#!/bin/bash
# Campaign Health Monitoring Script
# Detects submission drops, high rejection rates, and stalled campaigns

set -euo pipefail

# Configurable thresholds (can override via environment)
SUBMISSION_DROP_PCT="${HEALTH_SUBMISSION_DROP_PCT:-40}"
REJECTION_RATE_PCT="${HEALTH_REJECTION_RATE_PCT:-50}"
STALLED_DAYS="${HEALTH_STALLED_DAYS:-7}"
MIN_SUBMISSIONS="${HEALTH_MIN_SUBMISSIONS:-10}"

# Parse arguments
CAMPAIGN_ID=""
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
  case $1 in
    --id)
      CAMPAIGN_ID="$2"
      shift 2
      ;;
    --format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to run MySQL query
run_query() {
  local query="$1"
  mysql -N -e "$query" 2>/dev/null || echo ""
}

# Function to check submission rate drops
check_submission_drops() {
  local campaign_filter=""
  if [[ -n "$CAMPAIGN_ID" ]]; then
    campaign_filter="AND c.id = $CAMPAIGN_ID"
  fi

  local query="
WITH last_7d AS (
  SELECT 
    c.id AS campaign_id,
    c.title,
    COUNT(DISTINCT a.id) AS submissions
  FROM campaigns c
  LEFT JOIN actions a ON a.campaign_id = c.id 
    AND a.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  WHERE c.campaign_state_id = 2 $campaign_filter
  GROUP BY c.id, c.title
),
prior_7d AS (
  SELECT 
    c.id AS campaign_id,
    COUNT(DISTINCT a.id) AS submissions
  FROM campaigns c
  LEFT JOIN actions a ON a.campaign_id = c.id 
    AND a.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
    AND a.created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)
  WHERE c.campaign_state_id = 2 $campaign_filter
  GROUP BY c.id
)
SELECT 
  l.campaign_id,
  l.title,
  COALESCE(p.submissions, 0) AS prior_7d,
  l.submissions AS last_7d,
  ROUND((l.submissions - COALESCE(p.submissions, 0)) / NULLIF(COALESCE(p.submissions, 0), 0) * 100, 1) AS pct_change
FROM last_7d l
LEFT JOIN prior_7d p ON p.campaign_id = l.campaign_id
WHERE COALESCE(p.submissions, 0) > 0
  AND l.submissions < COALESCE(p.submissions, 0) * (1 - $SUBMISSION_DROP_PCT / 100.0)
ORDER BY pct_change ASC;
"
  run_query "$query"
}

# Function to check high rejection rates
check_high_rejection() {
  local campaign_filter=""
  if [[ -n "$CAMPAIGN_ID" ]]; then
    campaign_filter="AND c.id = $CAMPAIGN_ID"
  fi

  local query="
SELECT 
  c.id AS campaign_id,
  c.title,
  COUNT(DISTINCT pm.id) AS total_moderated,
  SUM(pm.is_approved = 1) AS approved,
  SUM(pm.is_approved = 0) AS rejected,
  ROUND(SUM(pm.is_approved = 0) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS rejection_rate
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
WHERE c.campaign_state_id = 2 $campaign_filter
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title
HAVING total_moderated >= $MIN_SUBMISSIONS
  AND rejection_rate >= $REJECTION_RATE_PCT
ORDER BY rejection_rate DESC;
"
  run_query "$query"
}

# Function to check stalled campaigns
check_stalled_campaigns() {
  local campaign_filter=""
  if [[ -n "$CAMPAIGN_ID" ]]; then
    campaign_filter="AND c.id = $CAMPAIGN_ID"
  fi

  local query="
SELECT 
  c.id AS campaign_id,
  c.title,
  COALESCE(DATE_FORMAT(MAX(a.created_at), '%d/%m/%Y'), 'nunca') AS last_submission,
  COALESCE(DATEDIFF(NOW(), MAX(a.created_at)), 999) AS days_since_last
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
WHERE c.campaign_state_id = 2 $campaign_filter
GROUP BY c.id, c.title
HAVING last_submission = 'nunca' OR days_since_last >= $STALLED_DAYS
ORDER BY days_since_last DESC;
"
  run_query "$query"
}

# Collect results
submission_drops=$(check_submission_drops)
high_rejection=$(check_high_rejection)
stalled=$(check_stalled_campaigns)

# Count issues
drop_count=0
[[ -n "$submission_drops" ]] && drop_count=$(echo "$submission_drops" | wc -l)

rejection_count=0
[[ -n "$high_rejection" ]] && rejection_count=$(echo "$high_rejection" | wc -l)

stalled_count=0
[[ -n "$stalled" ]] && stalled_count=$(echo "$stalled" | wc -l)

total_issues=$((drop_count + rejection_count + stalled_count))

# Output format
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # JSON output for automation
  echo "{"
  echo "  \"total_issues\": $total_issues,"
  echo "  \"submission_drops\": ["
  if [[ -n "$submission_drops" ]]; then
    echo "$submission_drops" | while IFS=$'\t' read -r id title prior last pct; do
      echo "    {\"id\": $id, \"title\": \"$title\", \"prior_7d\": $prior, \"last_7d\": $last, \"pct_change\": $pct},"
    done | sed '$ s/,$//'
  fi
  echo "  ],"
  echo "  \"high_rejection\": ["
  if [[ -n "$high_rejection" ]]; then
    echo "$high_rejection" | while IFS=$'\t' read -r id title total approved rejected rate; do
      echo "    {\"id\": $id, \"title\": \"$title\", \"total\": $total, \"approved\": $approved, \"rejected\": $rejected, \"rate\": $rate},"
    done | sed '$ s/,$//'
  fi
  echo "  ],"
  echo "  \"stalled\": ["
  if [[ -n "$stalled" ]]; then
    echo "$stalled" | while IFS=$'\t' read -r id title last_sub days; do
      echo "    {\"id\": $id, \"title\": \"$title\", \"last_submission\": \"$last_sub\", \"days_since\": $days},"
    done | sed '$ s/,$//'
  fi
  echo "  ]"
  echo "}"
else
  # Text output for human consumption
  echo "🩺 Campaign Health Check — $total_issues alerta(s) encontrado(s)"
  echo ""

  if [[ -n "$submission_drops" ]]; then
    echo "⚠️ QUEDAS DE SUBMISSÃO (últimos 7d vs 7d anteriores, >$SUBMISSION_DROP_PCT%)"
    echo "$submission_drops" | while IFS=$'\t' read -r id title prior last pct; do
      echo "• Campanha \"$title\" (ID: $id) — queda de ${pct#-}% ($prior → $last submissões)"
    done
    echo ""
  fi

  if [[ -n "$high_rejection" ]]; then
    echo "🚨 ALTAS TAXAS DE REJEIÇÃO (>$REJECTION_RATE_PCT% nos últimos 30d)"
    echo "$high_rejection" | while IFS=$'\t' read -r id title total approved rejected rate; do
      echo "• Campanha \"$title\" (ID: $id) — $rate% rejeição ($approved aprovados, $rejected recusados)"
    done
    echo ""
  fi

  if [[ -n "$stalled" ]]; then
    echo "⏸️ CAMPANHAS PARADAS (sem submissões há >$STALLED_DAYS dias)"
    echo "$stalled" | while IFS=$'\t' read -r id title last_sub days; do
      if [[ "$last_sub" == "nunca" ]]; then
        echo "• Campanha \"$title\" (ID: $id) — nunca recebeu submissões"
      else
        echo "• Campanha \"$title\" (ID: $id) — $days dias sem submissões (última: $last_sub)"
      fi
    done
    echo ""
  fi

  if [[ $total_issues -eq 0 ]]; then
    echo "✅ Todas as campanhas ativas estão saudáveis — sem anomalias detectadas."
  fi
fi
