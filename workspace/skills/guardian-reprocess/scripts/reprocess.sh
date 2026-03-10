#!/usr/bin/env bash
# Guardian Media Reprocess Script
# Triggers reprocessing via Guardian API backoffice endpoint
#
# Usage:
#   ./reprocess.sh <media_id> [media_id2 ...]
#   ./reprocess.sh 61520 61487
#   ./reprocess.sh --check 61520        # Check status only
#   ./reprocess.sh --find-orphans       # Find unprocessed media
#   ./reprocess.sh --dry-run 61520      # Show what would be sent without sending

set -euo pipefail

# --- Config ---
export PATH="/opt/google-cloud-sdk/bin:$PATH"
KUBE_NS="prod"
GUARDIAN_API_URL="${GUARDIAN_API_URL:-http://guardian-api.prod.svc/v1}"
GUARDIAN_AUTH_TOKEN="${GUARDIAN_AUTH_TOKEN:-}"
PROCESSING_LEVEL="${PROCESSING_LEVEL:-auto}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_blue()  { echo -e "${BLUE}[INFO]${NC} $1"; }

# --- Functions ---

get_media_info() {
    local media_id="$1"
    mysql --batch --raw --silent --skip-column-names -e "
        SELECT mc.id, COALESCE(mc.media_url, 'NULL'), COALESCE(mc.compressed_media_key, 'NULL'), COALESCE(mc.approved_at, 'NULL'), COALESCE(mc.refused_at, 'NULL')
        FROM media_content mc
        WHERE mc.id = $media_id
    " 2>/dev/null
}

get_proofread_status() {
    local media_id="$1"
    mysql --batch --raw --silent --skip-column-names -e "
        SELECT pm.id, pm.created_at
        FROM proofread_medias pm
        WHERE pm.media_id = $media_id
        ORDER BY pm.created_at DESC
        LIMIT 1
    " 2>/dev/null
}

check_media() {
    local media_id="$1"
    log_blue "=== Media $media_id ==="

    local info
    info=$(get_media_info "$media_id")
    if [ -z "$info" ]; then
        log_error "Media $media_id not found in media_content"
        return 1
    fi

    IFS=$'\t' read -r id media_url compressed_key approved refused <<< "$info"

    echo "  media_url:            ${media_url:-NULL}"
    echo "  compressed_media_key: ${compressed_key:-NULL}"
    echo "  approved_at:          ${approved:-NULL}"
    echo "  refused_at:           ${refused:-NULL}"

    local pm_info
    pm_info=$(get_proofread_status "$media_id")
    if [ -z "$pm_info" ]; then
        echo "  proofread_medias:     NONE (orphaned ⚠️)"
    else
        IFS=$'\t' read -r pm_id pm_created <<< "$pm_info"
        echo "  proofread_media_id:   $pm_id"
        echo "  proofread_created:    $pm_created ✅"
    fi
}

find_orphans() {
    local hours="${1:-24}"
    log_info "Finding unprocessed media from last ${hours}h..."

    mysql --batch -e "
        SELECT mc.id, mc.created_at, mc.compressed_media_key IS NOT NULL as compressed,
               TIMESTAMPDIFF(HOUR, mc.created_at, NOW()) as hours_old
        FROM media_content mc
        LEFT JOIN proofread_medias pm ON pm.media_id = mc.id
        WHERE pm.id IS NULL
          AND mc.approved_at IS NULL
          AND mc.refused_at IS NULL
          AND mc.deleted_at IS NULL
          AND mc.created_at >= DATE_SUB(NOW(), INTERVAL $hours HOUR)
        ORDER BY mc.created_at DESC
    " 2>/dev/null
}

call_guardian_api() {
    local media_ids="$1"
    local dry_run="${2:-false}"
    
    if [ -z "$GUARDIAN_AUTH_TOKEN" ]; then
        log_error "GUARDIAN_AUTH_TOKEN not set. Export it before running."
        log_error "Example: export GUARDIAN_AUTH_TOKEN='Bearer eyJ...'"
        return 1
    fi

    local payload
    payload=$(cat <<EOF
{
  "mediaIDs": "$media_ids",
  "processingLevel": "$PROCESSING_LEVEL"
}
EOF
)

    log_info "Calling Guardian API: POST $GUARDIAN_API_URL/backoffice/reprocess-media"
    log_info "Processing level: $PROCESSING_LEVEL"
    log_info "Media IDs: $media_ids"

    if [ "$dry_run" = "true" ]; then
        log_warn "DRY RUN — would send:"
        echo "$payload" | python3 -m json.tool 2>/dev/null || echo "$payload"
        return 0
    fi

    # Call via kubectl exec from guardian-api pod (internal network access)
    local pod
    pod=$(kubectl get pods -n "$KUBE_NS" -l app=guardian-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod" ]; then
        log_error "No guardian-api pod found in namespace $KUBE_NS"
        return 1
    fi

    local response
    response=$(kubectl exec -n "$KUBE_NS" "$pod" -- sh -c "
        curl -s -X POST '$GUARDIAN_API_URL/backoffice/reprocess-media' \
             -H 'Content-Type: application/json' \
             -H 'Authorization: $GUARDIAN_AUTH_TOKEN' \
             -d '$payload'
    " 2>&1)

    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Failed to call API: $response"
        return 1
    fi

    # Check response
    if echo "$response" | grep -q '"message"'; then
        log_info "✅ API Response: $response"
        return 0
    else
        log_error "❌ Unexpected response: $response"
        return 1
    fi
}

reprocess_media() {
    local media_ids="$1"
    local dry_run="${2:-false}"

    # Validate each media exists
    IFS=',' read -ra ids <<< "$media_ids"
    for media_id in "${ids[@]}"; do
        media_id=$(echo "$media_id" | xargs) # trim whitespace
        
        if ! [[ "$media_id" =~ ^[0-9]+$ ]]; then
            log_error "Invalid media ID: $media_id (must be numeric)"
            return 1
        fi

        local info
        info=$(get_media_info "$media_id")
        if [ -z "$info" ]; then
            log_error "Media $media_id not found"
            return 1
        fi

        IFS=$'\t' read -r id media_url compressed_key approved refused <<< "$info"

        if [ "$approved" != "NULL" ] && [ -n "$approved" ]; then
            log_warn "Media $media_id already approved at $approved"
        fi

        if [ "$refused" != "NULL" ] && [ -n "$refused" ]; then
            log_warn "Media $media_id already refused at $refused"
        fi
    done

    # Call Guardian API
    call_guardian_api "$media_ids" "$dry_run"
}

show_usage() {
    cat <<EOF
Guardian Media Reprocess Tool (API-based)

Usage:
  $(basename "$0") <media_id> [media_id2 ...]   Reprocess one or more media
  $(basename "$0") --check <media_id>            Check media status
  $(basename "$0") --find-orphans [hours]        Find unprocessed media (default: 24h)
  $(basename "$0") --dry-run <media_id> [...]    Show what would be sent
  $(basename "$0") -h|--help                     Show this help

Environment Variables:
  GUARDIAN_AUTH_TOKEN    Bearer token for Guardian API (REQUIRED)
                         Example: export GUARDIAN_AUTH_TOKEN='Bearer eyJ...'
  GUARDIAN_API_URL       Guardian API base URL (default: http://guardian-api.prod.svc/v1)
  PROCESSING_LEVEL       Processing level: auto|guardian|ads_treatment (default: auto)

How it works:
  1. Calls Guardian API POST /v1/backoffice/reprocess-media
  2. API accepts mediaIDs as comma-separated string
  3. API handles routing based on processingLevel:
     - auto: automatically routes based on compressed_media_key
     - guardian: send directly to Guardian queue
     - ads_treatment: send to compression queue first

Requires:
  - kubectl configured with GKE cluster access
  - MySQL access (via cloud-sql-proxy)
  - GUARDIAN_AUTH_TOKEN env var set

Examples:
  # Set auth token first
  export GUARDIAN_AUTH_TOKEN='Bearer eyJhbGc...'

  # Reprocess media
  ./reprocess.sh 61520 61487

  # Check status
  ./reprocess.sh --check 61520

  # Find orphans
  ./reprocess.sh --find-orphans 48

  # Dry run
  ./reprocess.sh --dry-run 61520
EOF
}

# --- Main ---

DRY_RUN=false

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    --check)
        shift
        for id in "$@"; do
            check_media "$id"
        done
        exit 0
        ;;
    --find-orphans)
        shift
        find_orphans "${1:-24}"
        exit 0
        ;;
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    "")
        show_usage
        exit 1
        ;;
esac

if [ $# -eq 0 ]; then
    log_error "No media IDs provided"
    show_usage
    exit 1
fi

# Validate all media IDs
for media_id in "$@"; do
    if ! [[ "$media_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid media ID: $media_id (must be numeric)"
        exit 1
    fi
done

# Build comma-separated list
MEDIA_IDS=$(IFS=,; echo "$*")

echo ""
for media_id in "$@"; do
    check_media "$media_id"
    echo ""
done

if reprocess_media "$MEDIA_IDS" "$DRY_RUN"; then
    log_info "✅ Reprocess request sent successfully"
    exit 0
else
    log_error "❌ Reprocess request failed"
    exit 1
fi
