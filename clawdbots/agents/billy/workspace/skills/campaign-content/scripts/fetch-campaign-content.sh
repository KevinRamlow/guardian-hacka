#!/bin/bash
# Campaign Content Fetcher
# Usage: ./fetch-campaign-content.sh CAMPAIGN_ID [approved|rejected|pending|all] [--script]
#
# Examples:
#   ./fetch-campaign-content.sh 123 approved
#   ./fetch-campaign-content.sh 456 rejected
#   ./fetch-campaign-content.sh 789 all --script

set -e

CAMPAIGN_ID="$1"
STATUS="${2:-all}"
GENERATE_SCRIPT="${3}"

# Validate inputs
if [ -z "$CAMPAIGN_ID" ]; then
    echo "❌ Error: Campaign ID required"
    echo "Usage: $0 CAMPAIGN_ID [approved|rejected|pending|all] [--script]"
    exit 1
fi

# Validate campaign ID is numeric
if ! [[ "$CAMPAIGN_ID" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: Campaign ID must be numeric"
    exit 1
fi

# Check if campaign exists and get details
CAMPAIGN_INFO=$(mysql -N -e "
SELECT c.id, c.title, c.campaign_state_id
FROM campaigns c
WHERE c.id = $CAMPAIGN_ID
LIMIT 1;
" 2>/dev/null)

if [ -z "$CAMPAIGN_INFO" ]; then
    echo "❌ Error: Campaign ID $CAMPAIGN_ID not found"
    exit 1
fi

CAMPAIGN_TITLE=$(echo "$CAMPAIGN_INFO" | cut -f2)
CAMPAIGN_STATE=$(echo "$CAMPAIGN_INFO" | cut -f3)

# Build status filter and query
STATUS_LABEL=""
QUERY=""

case "$STATUS" in
    "approved"|"aprovados")
        STATUS_LABEL="Aprovados"
        QUERY="
SELECT 
    mc.id AS media_id,
    mc.media_url,
    mc.thumb_url,
    mc.mime_type,
    1 AS approval_status,
    pm.created_at AS timestamp
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = $CAMPAIGN_ID
  AND pm.is_approved = 1
  AND mc.deleted_at IS NULL
ORDER BY timestamp DESC
LIMIT 1000;
"
        ;;
    "rejected"|"recusados")
        STATUS_LABEL="Recusados"
        QUERY="
SELECT 
    mc.id AS media_id,
    mc.media_url,
    mc.thumb_url,
    mc.mime_type,
    0 AS approval_status,
    pm.created_at AS timestamp
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = $CAMPAIGN_ID
  AND pm.is_approved = 0
  AND mc.deleted_at IS NULL
ORDER BY timestamp DESC
LIMIT 1000;
"
        ;;
    "pending"|"pendentes")
        STATUS_LABEL="Pendentes"
        QUERY="
SELECT 
    mc.id AS media_id,
    mc.media_url,
    mc.thumb_url,
    mc.mime_type,
    -1 AS approval_status,
    mc.created_at AS timestamp
FROM media_content mc
JOIN actions a ON a.id = mc.action_id
JOIN ads ad ON ad.id = a.ad_id
JOIN moments m ON m.id = ad.moment_id
LEFT JOIN proofread_medias pm ON pm.media_id = mc.id
WHERE m.campaign_id = $CAMPAIGN_ID
  AND pm.id IS NULL
  AND mc.deleted_at IS NULL
ORDER BY timestamp DESC
LIMIT 1000;
"
        ;;
    "all"|"todos")
        STATUS_LABEL="Todos"
        QUERY="
SELECT 
    mc.id AS media_id,
    mc.media_url,
    mc.thumb_url,
    mc.mime_type,
    COALESCE(pm.is_approved, -1) AS approval_status,
    COALESCE(pm.created_at, mc.created_at) AS timestamp
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id
LEFT JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = $CAMPAIGN_ID
  AND mc.deleted_at IS NULL
ORDER BY timestamp DESC
LIMIT 1000;
"
        ;;
    *)
        echo "❌ Error: Invalid status '$STATUS'"
        echo "Valid options: approved, rejected, pending, all"
        exit 1
        ;;
esac

# Execute query and store results
RESULTS=$(mysql -N -e "$QUERY" 2>/dev/null)

if [ -z "$RESULTS" ]; then
    echo "⚠️  Nenhum conteúdo encontrado com status '$STATUS_LABEL'"
    echo ""
    echo "📊 Campanha: $CAMPAIGN_TITLE (ID: $CAMPAIGN_ID)"
    echo "Status: $CAMPAIGN_STATE"
    exit 0
fi

# Count results
TOTAL_COUNT=$(echo "$RESULTS" | wc -l)

# Parse results into arrays
declare -a MEDIA_IDS
declare -a MEDIA_URLS
declare -a THUMBNAILS
declare -a MIME_TYPES
declare -a APPROVAL_STATUSES

while IFS=$'\t' read -r media_id media_url thumbnail mime_type approval timestamp; do
    MEDIA_IDS+=("$media_id")
    MEDIA_URLS+=("$media_url")
    THUMBNAILS+=("$thumbnail")
    MIME_TYPES+=("$mime_type")
    APPROVAL_STATUSES+=("$approval")
done <<< "$RESULTS"

# Generate output
echo "📊 Campanha: $CAMPAIGN_TITLE (ID: $CAMPAIGN_ID)"
echo "Status: $CAMPAIGN_STATE"
echo ""
echo "✅ Encontrados: $TOTAL_COUNT conteúdos ($STATUS_LABEL)"
echo ""

# Show first 20 URLs
DISPLAY_LIMIT=20
if [ "$TOTAL_COUNT" -le "$DISPLAY_LIMIT" ]; then
    DISPLAY_LIMIT=$TOTAL_COUNT
fi

echo "📥 Download links (primeiros $DISPLAY_LIMIT):"
echo ""

for i in $(seq 0 $((DISPLAY_LIMIT - 1))); do
    url="${MEDIA_URLS[$i]}"
    mime_type="${MIME_TYPES[$i]}"
    approval="${APPROVAL_STATUSES[$i]}"
    
    # Format media type from mime_type
    case "$mime_type" in
        video/*|*video*) type_icon="🎥" ;;
        image/*|*image*) type_icon="🖼️" ;;
        *) type_icon="📄" ;;
    esac
    
    # Format approval status
    status_icon=""
    if [ "$approval" = "1" ]; then
        status_icon="✅"
    elif [ "$approval" = "0" ]; then
        status_icon="❌"
    else
        status_icon="⏳"
    fi
    
    printf "%3d. %s %s %s\n" $((i + 1)) "$status_icon" "$type_icon" "$url"
done

if [ "$TOTAL_COUNT" -gt "$DISPLAY_LIMIT" ]; then
    echo ""
    echo "... e mais $((TOTAL_COUNT - DISPLAY_LIMIT)) arquivos"
fi

echo ""

# Generate download script if requested
if [ "$GENERATE_SCRIPT" = "--script" ] || [ "$TOTAL_COUNT" -gt 10 ]; then
    SCRIPT_NAME="download-campaign-${CAMPAIGN_ID}-${STATUS}.sh"
    
    cat > "$SCRIPT_NAME" << EOF
#!/bin/bash
# Download $STATUS_LABEL content from campaign "$CAMPAIGN_TITLE"
# Generated by Billy on $(date -u '+%Y-%m-%d %H:%M UTC')
# Total files: $TOTAL_COUNT

set -e

# Create output directory
OUTPUT_DIR="campaign-${CAMPAIGN_ID}-${STATUS}"
mkdir -p "\$OUTPUT_DIR"
cd "\$OUTPUT_DIR"

echo "📥 Downloading $TOTAL_COUNT files to \$(pwd)..."
echo ""

# Download all files
EOF

    for i in $(seq 0 $((TOTAL_COUNT - 1))); do
        url="${MEDIA_URLS[$i]}"
        media_id="${MEDIA_IDS[$i]}"
        mime_type="${MIME_TYPES[$i]}"
        
        # Determine file extension from mime_type
        case "$mime_type" in
            video/*|*video*) ext="mp4" ;;
            image/jpeg|*jpeg*) ext="jpg" ;;
            image/png|*png*) ext="png" ;;
            image/*|*image*) ext="jpg" ;;
            *) ext="bin" ;;
        esac
        
        echo "wget -q \"$url\" -O \"media-${media_id}.${ext}\" && echo \"✓ Downloaded media-${media_id}.${ext}\"" >> "$SCRIPT_NAME"
    done
    
    cat >> "$SCRIPT_NAME" << EOF

echo ""
echo "✅ Download complete! $TOTAL_COUNT files saved to \$(pwd)"
EOF

    chmod +x "$SCRIPT_NAME"
    
    echo "💡 Dica: Script de download gerado!"
    echo "   Execute: ./$SCRIPT_NAME"
    echo ""
fi

# Summary statistics
VIDEO_COUNT=$(echo "$RESULTS" | awk -F'\t' '$4 ~ /video/' | wc -l)
IMAGE_COUNT=$(echo "$RESULTS" | awk -F'\t' '$4 ~ /image/' | wc -l)

echo "📈 Estatísticas:"
echo "   Total: $TOTAL_COUNT"
echo "   Vídeos: $VIDEO_COUNT"
echo "   Imagens: $IMAGE_COUNT"

# JSON output for Billy integration (optional)
if [ "$GENERATE_SCRIPT" = "--json" ]; then
    echo ""
    echo '{'
    echo "  \"campaign_id\": $CAMPAIGN_ID,"
    echo "  \"campaign_title\": \"$CAMPAIGN_TITLE\","
    echo "  \"campaign_state\": \"$CAMPAIGN_STATE\","
    echo "  \"status_filter\": \"$STATUS\","
    echo "  \"total_count\": $TOTAL_COUNT,"
    echo "  \"video_count\": $VIDEO_COUNT,"
    echo "  \"image_count\": $IMAGE_COUNT,"
    echo '  "urls": ['
    
    for i in $(seq 0 $((TOTAL_COUNT - 1))); do
        url="${MEDIA_URLS[$i]}"
        media_id="${MEDIA_IDS[$i]}"
        mime_type="${MIME_TYPES[$i]}"
        approval="${APPROVAL_STATUSES[$i]}"
        
        comma=","
        if [ $i -eq $((TOTAL_COUNT - 1)) ]; then
            comma=""
        fi
        
        echo "    {"
        echo "      \"media_id\": $media_id,"
        echo "      \"url\": \"$url\","
        echo "      \"mime_type\": \"$mime_type\","
        echo "      \"is_approved\": $([ "$approval" = "1" ] && echo "true" || ([ "$approval" = "0" ] && echo "false" || echo "null"))"
        echo "    }$comma"
    done
    
    echo '  ]'
    echo '}'
fi

exit 0
