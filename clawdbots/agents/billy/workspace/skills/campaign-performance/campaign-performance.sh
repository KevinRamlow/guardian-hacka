#!/bin/bash
# Campaign Performance Dashboard
# Usage: ./campaign-performance.sh --id 1234 [--export-sheets] [--format slack|json]

set -euo pipefail

# Default values
CAMPAIGN_ID=""
CAMPAIGN_NAME=""
EXPORT_SHEETS=false
FORMAT="slack"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)
      CAMPAIGN_ID="$2"
      shift 2
      ;;
    --name)
      CAMPAIGN_NAME="$2"
      shift 2
      ;;
    --export-sheets)
      EXPORT_SHEETS=true
      shift
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate input
if [[ -z "$CAMPAIGN_ID" && -z "$CAMPAIGN_NAME" ]]; then
  echo "Error: Must provide --id or --name"
  exit 1
fi

# Build WHERE clause
if [[ -n "$CAMPAIGN_ID" ]]; then
  WHERE_CLAUSE="c.id = $CAMPAIGN_ID"
  SEARCH_PARAM="$CAMPAIGN_ID"
else
  WHERE_CLAUSE="c.title LIKE '%$CAMPAIGN_NAME%'"
  SEARCH_PARAM="%$CAMPAIGN_NAME%"
fi

# Query 1: Revenue metrics
read -r -d '' REVENUE_QUERY <<'EOF' || true
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  b.name AS brand_name,
  c.budget,
  COALESCE(COUNT(DISTINCT cph.id), 0) AS total_payments,
  COALESCE(COUNT(DISTINCT cph.creator_id), 0) AS paid_creators,
  COALESCE(ROUND(SUM(cph.value), 2), 0) AS total_revenue_net,
  COALESCE(ROUND(SUM(cph.gross_value), 2), 0) AS total_revenue_gross,
  COALESCE(ROUND(AVG(cph.value), 2), 0) AS avg_payment,
  COALESCE(cph.value_currency, 'BRL') AS currency,
  COALESCE(SUM(cph.payment_status = 'complete'), 0) AS payments_complete,
  COALESCE(SUM(cph.payment_status = 'partial'), 0) AS payments_partial,
  COALESCE(SUM(cph.payment_status = 'in_process'), 0) AS payments_in_process
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE __WHERE__
GROUP BY c.id, c.title, b.name, c.budget, cph.value_currency
LIMIT 1;
EOF

REVENUE_QUERY="${REVENUE_QUERY//__WHERE__/$WHERE_CLAUSE}"

# Query 2: Engagement metrics
read -r -d '' ENGAGEMENT_QUERY <<'EOF' || true
SELECT 
  c.id AS campaign_id,
  COALESCE(COUNT(DISTINCT pm.creator_id), 0) AS total_creators,
  COALESCE(COUNT(DISTINCT pm.id), 0) AS total_content,
  COALESCE(SUM(pm.is_approved = 1), 0) AS approved,
  COALESCE(SUM(pm.is_approved = 0), 0) AS refused,
  COALESCE(ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1), 0) AS approval_rate,
  COALESCE(COUNT(DISTINCT pmc.id), 0) AS contests,
  COALESCE(ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1), 0) AS contest_rate
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE __WHERE__
GROUP BY c.id
LIMIT 1;
EOF

ENGAGEMENT_QUERY="${ENGAGEMENT_QUERY//__WHERE__/$WHERE_CLAUSE}"

# Query 3: Platform average (last 30 days)
read -r -d '' PLATFORM_AVG_QUERY <<'EOF' || true
SELECT 
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS platform_avg_approval
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL;
EOF

# Execute queries
REVENUE_DATA=$(mysql -N -e "$REVENUE_QUERY")
ENGAGEMENT_DATA=$(mysql -N -e "$ENGAGEMENT_QUERY")
PLATFORM_AVG=$(mysql -N -e "$PLATFORM_AVG_QUERY")

# Check if campaign was found
if [[ -z "$REVENUE_DATA" ]]; then
  echo "Error: Campaign not found with search: $SEARCH_PARAM"
  exit 1
fi

# Parse revenue data
IFS=$'\t' read -r CAMPAIGN_ID CAMPAIGN_NAME BRAND_NAME BUDGET TOTAL_PAYMENTS PAID_CREATORS \
  REVENUE_NET REVENUE_GROSS AVG_PAYMENT CURRENCY PAYMENTS_COMPLETE PAYMENTS_PARTIAL PAYMENTS_IN_PROCESS \
  <<< "$REVENUE_DATA"

# Parse engagement data
IFS=$'\t' read -r _ TOTAL_CREATORS TOTAL_CONTENT APPROVED REFUSED APPROVAL_RATE CONTESTS CONTEST_RATE \
  <<< "$ENGAGEMENT_DATA"

# Calculate ROI
if [[ $(echo "$BUDGET > 0" | bc -l) -eq 1 ]]; then
  ROI=$(echo "scale=1; ($REVENUE_NET / $BUDGET) * 100" | bc -l)
  BUDGET_USED_PCT=$(echo "scale=1; ($REVENUE_NET / $BUDGET) * 100" | bc -l)
else
  ROI="N/A"
  BUDGET_USED_PCT="N/A"
fi

# Format currency
format_currency() {
  local amount=$1
  local curr=$2
  if [[ "$curr" == "BRL" ]]; then
    # BRL format: R$ 1.403.500,00
    printf "%.2f" "$amount" | awk '{
      # Split into integer and decimal
      split($0, parts, ".");
      integer = parts[1];
      decimal = parts[2];
      
      # Add thousand separators to integer part
      len = length(integer);
      result = "";
      for (i = len; i > 0; i--) {
        result = substr(integer, i, 1) result;
        if ((len - i + 1) % 3 == 0 && i > 1) result = "." result;
      }
      
      print "R$ " result "," decimal;
    }'
  else
    # USD format: $1,403,500.00
    printf "$%'.2f" "$amount"
  fi
}

REVENUE_NET_FORMATTED=$(format_currency "$REVENUE_NET" "$CURRENCY")
REVENUE_GROSS_FORMATTED=$(format_currency "$REVENUE_GROSS" "$CURRENCY")
AVG_PAYMENT_FORMATTED=$(format_currency "$AVG_PAYMENT" "$CURRENCY")
BUDGET_FORMATTED=$(format_currency "$BUDGET" "$CURRENCY")

# Calculate approval rate difference
APPROVAL_DIFF=$(echo "scale=1; $APPROVAL_RATE - $PLATFORM_AVG" | bc -l)
if (( $(echo "$APPROVAL_DIFF > 0" | bc -l) )); then
  APPROVAL_INDICATOR="✅"
  APPROVAL_DIFF_TEXT="+${APPROVAL_DIFF}pp"
elif (( $(echo "$APPROVAL_DIFF < 0" | bc -l) )); then
  APPROVAL_INDICATOR="⚠️"
  APPROVAL_DIFF_TEXT="${APPROVAL_DIFF}pp"
else
  APPROVAL_INDICATOR="➖"
  APPROVAL_DIFF_TEXT="0pp"
fi

# Output format
if [[ "$FORMAT" == "json" ]]; then
  # JSON output
  cat <<JSON
{
  "campaign_id": $CAMPAIGN_ID,
  "campaign_name": "$CAMPAIGN_NAME",
  "brand_name": "$BRAND_NAME",
  "revenue": {
    "net": $REVENUE_NET,
    "gross": $REVENUE_GROSS,
    "currency": "$CURRENCY",
    "paid_creators": $PAID_CREATORS,
    "avg_payment": $AVG_PAYMENT,
    "total_payments": $TOTAL_PAYMENTS,
    "payments_complete": $PAYMENTS_COMPLETE,
    "payments_partial": $PAYMENTS_PARTIAL,
    "payments_in_process": $PAYMENTS_IN_PROCESS
  },
  "engagement": {
    "total_creators": $TOTAL_CREATORS,
    "total_content": $TOTAL_CONTENT,
    "approved": $APPROVED,
    "refused": $REFUSED,
    "approval_rate": $APPROVAL_RATE,
    "contests": $CONTESTS,
    "contest_rate": $CONTEST_RATE
  },
  "roi": {
    "budget": $BUDGET,
    "roi_percentage": "$ROI",
    "budget_used_percentage": "$BUDGET_USED_PCT"
  },
  "platform_comparison": {
    "platform_avg_approval": $PLATFORM_AVG,
    "difference": $APPROVAL_DIFF
  }
}
JSON
else
  # Slack format
  cat <<SLACK
📊 *Dashboard: $CAMPAIGN_NAME*
_Marca: ${BRAND_NAME}_

💰 *REVENUE / GMV*
• Total Pago: $REVENUE_NET_FORMATTED (net) | $REVENUE_GROSS_FORMATTED (gross)
• Creators Pagos: $PAID_CREATORS
• Pagamento Médio: $AVG_PAYMENT_FORMATTED
• Status Pagamentos: $PAYMENTS_COMPLETE completos, $PAYMENTS_PARTIAL parciais, $PAYMENTS_IN_PROCESS em processo

📈 *ENGAGEMENT*
• Conteúdos: $TOTAL_CONTENT submetidos
• Aprovação: ${APPROVAL_RATE}% ($APPROVED aprovados, $REFUSED recusados)
• Contestações: $CONTESTS (${CONTEST_RATE}% do total)
• Creators Ativos: $TOTAL_CREATORS

💡 *ROI*
• Budget: $BUDGET_FORMATTED
• Gasto Real: $REVENUE_NET_FORMATTED (${BUDGET_USED_PCT}% do budget)
• ROI: ${ROI}%

📊 *vs Média da Plataforma (30d)*
• Aprovação Campanha: ${APPROVAL_RATE}%
• Aprovação Plataforma: ${PLATFORM_AVG}%
• Diferença: $APPROVAL_DIFF_TEXT $APPROVAL_INDICATOR
SLACK

  # Add Google Sheets link if export requested
  if [[ "$EXPORT_SHEETS" == "true" ]]; then
    echo ""
    echo "🔗 *Exportando para Google Sheets...*"
    # Call export script
    SHEETS_LINK=$(bash "$(dirname "$0")/export-sheets.sh" "$CAMPAIGN_ID")
    echo "📄 Ver detalhes: $SHEETS_LINK"
  fi
fi
