#!/bin/bash
# Export campaign performance to Google Sheets
# Usage: ./export-sheets.sh <campaign_id>

set -euo pipefail

CAMPAIGN_ID="$1"

if [[ -z "$CAMPAIGN_ID" ]]; then
  echo "Error: Campaign ID required"
  exit 1
fi

# Get campaign name and basic data
CAMPAIGN_DATA=$(mysql -N -e "SELECT c.title, b.name FROM campaigns c JOIN brands b ON c.brand_id = b.id WHERE c.id = $CAMPAIGN_ID LIMIT 1;")
IFS=$'\t' read -r CAMPAIGN_NAME BRAND_NAME <<< "$CAMPAIGN_DATA"

if [[ -z "$CAMPAIGN_NAME" ]]; then
  echo "Error: Campaign $CAMPAIGN_ID not found"
  exit 1
fi

# Sheet title
SHEET_TITLE="Campaign Performance: $CAMPAIGN_NAME"

# Create temporary CSV files for each sheet
TMPDIR=$(mktemp -d)
SUMMARY_CSV="$TMPDIR/summary.csv"
REVENUE_CSV="$TMPDIR/revenue.csv"
CONTENT_CSV="$TMPDIR/content.csv"
CREATORS_CSV="$TMPDIR/creators.csv"

# Summary sheet - key metrics
cat > "$SUMMARY_CSV" <<EOF
Métrica,Valor
Campanha,$CAMPAIGN_NAME
Marca,$BRAND_NAME
Campaign ID,$CAMPAIGN_ID
EOF

# Get revenue data
mysql -e "
SELECT 
  'Total Pago (Net)' AS metric,
  CONCAT(COALESCE(cph.value_currency, 'BRL'), ' ', COALESCE(ROUND(SUM(cph.value), 2), 0)) AS value
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.id = $CAMPAIGN_ID
GROUP BY cph.value_currency
UNION ALL
SELECT 'Total Pago (Gross)', CONCAT(COALESCE(cph.value_currency, 'BRL'), ' ', COALESCE(ROUND(SUM(cph.gross_value), 2), 0))
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.id = $CAMPAIGN_ID
GROUP BY cph.value_currency
UNION ALL
SELECT 'Creators Pagos', CAST(COALESCE(COUNT(DISTINCT cph.creator_id), 0) AS CHAR)
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.id = $CAMPAIGN_ID
UNION ALL
SELECT 'Budget', CONCAT('BRL ', c.budget)
FROM campaigns c
WHERE c.id = $CAMPAIGN_ID
UNION ALL
SELECT 'Conteúdos Submetidos', CAST(COALESCE(COUNT(DISTINCT pm.id), 0) AS CHAR)
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
WHERE c.id = $CAMPAIGN_ID
UNION ALL
SELECT 'Taxa de Aprovação (%)', CAST(COALESCE(ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1), 0) AS CHAR)
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
WHERE c.id = $CAMPAIGN_ID
UNION ALL
SELECT 'Creators Ativos', CAST(COALESCE(COUNT(DISTINCT pm.creator_id), 0) AS CHAR)
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
WHERE c.id = $CAMPAIGN_ID;
" | tail -n +2 >> "$SUMMARY_CSV"

# Revenue details - payment history
mysql -e "
SELECT 
  cph.id AS 'Payment ID',
  cph.creator_id AS 'Creator ID',
  ROUND(cph.value, 2) AS 'Valor Net',
  ROUND(cph.gross_value, 2) AS 'Valor Gross',
  cph.value_currency AS 'Moeda',
  cph.payment_status AS 'Status',
  cph.date_of_transaction AS 'Data'
FROM creator_payment_history cph
WHERE cph.campaign_id = $CAMPAIGN_ID
ORDER BY cph.date_of_transaction DESC;
" | sed 's/\t/,/g' > "$REVENUE_CSV"

# Content details - moderation results
mysql -e "
SELECT 
  pm.id AS 'Moderation ID',
  pm.creator_id AS 'Creator ID',
  CASE WHEN pm.is_approved = 1 THEN 'Aprovado' ELSE 'Recusado' END AS 'Status',
  ROUND(pm.adherence, 2) AS 'Aderência',
  pm.created_at AS 'Data Moderação'
FROM proofread_medias pm
WHERE pm.campaign_id = $CAMPAIGN_ID
  AND pm.deleted_at IS NULL
ORDER BY pm.created_at DESC
LIMIT 1000;
" | sed 's/\t/,/g' > "$CONTENT_CSV"

# Creator breakdown - per-creator stats
mysql -e "
SELECT 
  pm.creator_id AS 'Creator ID',
  COUNT(pm.id) AS 'Conteúdos',
  SUM(pm.is_approved = 1) AS 'Aprovados',
  SUM(pm.is_approved = 0) AS 'Recusados',
  ROUND(SUM(pm.is_approved = 1) / COUNT(pm.id) * 100, 1) AS 'Taxa Aprovação (%)',
  COALESCE(ROUND(SUM(cph.value), 2), 0) AS 'Total Pago',
  COALESCE(cph.value_currency, 'N/A') AS 'Moeda'
FROM proofread_medias pm
LEFT JOIN creator_payment_history cph ON cph.creator_id = pm.creator_id AND cph.campaign_id = pm.campaign_id
WHERE pm.campaign_id = $CAMPAIGN_ID
  AND pm.deleted_at IS NULL
GROUP BY pm.creator_id, cph.value_currency
ORDER BY COUNT(pm.id) DESC
LIMIT 500;
" | sed 's/\t/,/g' > "$CREATORS_CSV"

# Create Google Sheet (using gog if available, otherwise placeholder)
if command -v gog &> /dev/null && [[ -f /root/.openclaw/workspace/.env.gog ]]; then
  # Source gog env
  source /root/.openclaw/workspace/.env.gog
  
  # Create sheet
  SHEET_ID=$(gog sheets create --title "$SHEET_TITLE" --share anyone --role reader | grep -oP 'https://docs.google.com/spreadsheets/d/\K[^/]+')
  
  # Import CSVs
  gog sheets import --sheet-id "$SHEET_ID" --sheet-name "Summary" --csv "$SUMMARY_CSV"
  gog sheets import --sheet-id "$SHEET_ID" --sheet-name "Revenue Details" --csv "$REVENUE_CSV"
  gog sheets import --sheet-id "$SHEET_ID" --sheet-name "Content Details" --csv "$CONTENT_CSV"
  gog sheets import --sheet-id "$SHEET_ID" --sheet-name "Creator Breakdown" --csv "$CREATORS_CSV"
  
  # Return shareable link
  echo "https://docs.google.com/spreadsheets/d/$SHEET_ID/edit"
else
  # Fallback - save CSVs locally and notify
  OUTPUT_DIR="$HOME/campaign-reports/$CAMPAIGN_ID"
  mkdir -p "$OUTPUT_DIR"
  cp "$SUMMARY_CSV" "$OUTPUT_DIR/summary.csv"
  cp "$REVENUE_CSV" "$OUTPUT_DIR/revenue.csv"
  cp "$CONTENT_CSV" "$OUTPUT_DIR/content.csv"
  cp "$CREATORS_CSV" "$OUTPUT_DIR/creators.csv"
  
  echo "⚠️  Google Sheets export not available (gog not configured)"
  echo "📁 CSV files saved to: $OUTPUT_DIR"
  echo "file://$OUTPUT_DIR/summary.csv"
fi

# Cleanup
rm -rf "$TMPDIR"
