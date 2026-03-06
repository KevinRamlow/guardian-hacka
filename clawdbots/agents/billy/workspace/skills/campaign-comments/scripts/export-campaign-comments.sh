#!/bin/bash
# Export campaign moderation comments to Google Sheets

set -e

CAMPAIGN_INPUT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$CAMPAIGN_INPUT" ]; then
    echo "Usage: $0 <campaign_id_or_name>"
    exit 1
fi

# Determine if input is ID or name
if [[ "$CAMPAIGN_INPUT" =~ ^[0-9]+$ ]]; then
    CAMPAIGN_ID="$CAMPAIGN_INPUT"
    CAMPAIGN_NAME=$(mysql -N -e "SELECT title FROM \`db-maestro-prod\`.campaigns WHERE id = $CAMPAIGN_ID;")
    if [ -z "$CAMPAIGN_NAME" ]; then
        echo "❌ Campaign ID $CAMPAIGN_ID not found"
        exit 1
    fi
else
    CAMPAIGN_NAME="$CAMPAIGN_INPUT"
    CAMPAIGN_ID=$(mysql -N -e "SELECT id FROM \`db-maestro-prod\`.campaigns WHERE title LIKE '%$CAMPAIGN_NAME%' LIMIT 1;")
    if [ -z "$CAMPAIGN_ID" ]; then
        echo "❌ Campaign '$CAMPAIGN_NAME' not found"
        exit 1
    fi
    CAMPAIGN_NAME=$(mysql -N -e "SELECT title FROM \`db-maestro-prod\`.campaigns WHERE id = $CAMPAIGN_ID;")
fi

echo "📊 Exporting comments for campaign: $CAMPAIGN_NAME (ID: $CAMPAIGN_ID)"

# Query and count
COMMENT_COUNT=$(mysql -N -e "
SELECT COUNT(*)
FROM \`db-maestro-prod\`.campaigns c
JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id
JOIN \`db-maestro-prod\`.actions a ON a.id = pm.action_id
JOIN \`db-maestro-prod\`.media_content mc ON mc.action_id = a.id
LEFT JOIN \`db-maestro-prod\`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = $CAMPAIGN_ID
  AND (mc.refusal_reason IS NOT NULL OR pmc.reason IS NOT NULL);
")

if [ "$COMMENT_COUNT" -eq 0 ]; then
    echo "⚠️  No comments found for this campaign"
    exit 0
fi

echo "📝 Found $COMMENT_COUNT comments"

# Create temp JSON file
TEMP_JSON="/tmp/campaign-comments-${CAMPAIGN_ID}-$(date +%s).json"

# Export data and convert to JSON
echo "📊 Fetching data from MySQL..."
mysql -e "
SELECT 
    c.title AS 'Campanha',
    b.name AS 'Marca',
    a.id AS 'Action ID',
    mc.id AS 'Media Content ID',
    mc.media_url AS 'Media URL',
    CASE 
        WHEN pm.is_approved = 1 THEN 'Aprovado'
        WHEN pm.is_approved = 0 THEN 'Recusado'
        ELSE 'Pendente'
    END AS 'Status',
    COALESCE(mc.refusal_reason, '') AS 'Comentário de Recusa',
    COALESCE(mc.refused_by, '') AS 'Recusado Por (User ID)',
    COALESCE(mc.refused_at, '') AS 'Recusado Em',
    COALESCE(pmc.reason, '') AS 'Motivo da Contestação',
    COALESCE(pmc.decision_reason, '') AS 'Decisão da Contestação',
    COALESCE(pmc.status, '') AS 'Status da Contestação',
    mc.created_at AS 'Criado Em',
    COALESCE(pmc.created_at, '') AS 'Contestado Em'
FROM \`db-maestro-prod\`.campaigns c
JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id
JOIN \`db-maestro-prod\`.actions a ON a.id = pm.action_id
JOIN \`db-maestro-prod\`.media_content mc ON mc.action_id = a.id
LEFT JOIN \`db-maestro-prod\`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = $CAMPAIGN_ID
  AND (mc.refusal_reason IS NOT NULL OR pmc.reason IS NOT NULL)
ORDER BY mc.created_at DESC;
" | python3 -c "
import sys
import csv
import json

# Read TSV from MySQL
reader = csv.DictReader(sys.stdin, delimiter='\t')
rows = []

# Add headers as first row
if reader.fieldnames:
    rows.append(list(reader.fieldnames))

# Add data rows
for row in reader:
    rows.append([str(row.get(field, '') or '') for field in reader.fieldnames])

# Output as JSON
print(json.dumps(rows))
" > "$TEMP_JSON"

ROW_COUNT=$(cat "$TEMP_JSON" | jq 'length')
echo "📊 Prepared $ROW_COUNT rows (including header)"

# Create Google Sheet
SHEET_TITLE="Campaign Comments - $CAMPAIGN_NAME - $(date +%Y-%m-%d)"
echo "📄 Creating Google Sheet: $SHEET_TITLE"
echo ""

# Run Python uploader
python3 "$SCRIPT_DIR/sheets_uploader.py" "$SHEET_TITLE" "$TEMP_JSON"

# Cleanup
rm -f "$TEMP_JSON"
