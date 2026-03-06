#!/bin/bash
# Export campaign moderation comments to CSV (fallback when Sheets auth not available)

set -e

CAMPAIGN_INPUT="$1"

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

# Create CSV output
OUTPUT_CSV="/tmp/campaign-comments-${CAMPAIGN_ID}-$(date +%Y%m%d-%H%M%S).csv"

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
    mc.refusal_reason AS 'Comentário de Recusa',
    mc.refused_by AS 'Recusado Por (User ID)',
    mc.refused_at AS 'Recusado Em',
    pmc.reason AS 'Motivo da Contestação',
    pmc.decision_reason AS 'Decisão da Contestação',
    pmc.status AS 'Status da Contestação',
    mc.created_at AS 'Criado Em',
    pmc.created_at AS 'Contestado Em'
FROM \`db-maestro-prod\`.campaigns c
JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id
JOIN \`db-maestro-prod\`.actions a ON a.id = pm.action_id
JOIN \`db-maestro-prod\`.media_content mc ON mc.action_id = a.id
LEFT JOIN \`db-maestro-prod\`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = $CAMPAIGN_ID
  AND (mc.refusal_reason IS NOT NULL OR pmc.reason IS NOT NULL)
ORDER BY mc.created_at DESC;
" > "$OUTPUT_CSV"

echo "✅ Export complete!"
echo "📁 CSV file: $OUTPUT_CSV"
echo ""
echo "To upload to Google Sheets:"
echo "1. Go to https://sheets.google.com"
echo "2. File → Import → Upload"
echo "3. Select: $OUTPUT_CSV"
echo ""
echo "$OUTPUT_CSV"
