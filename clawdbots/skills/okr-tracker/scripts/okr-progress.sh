#!/bin/bash
# OKR Progress Tracker
# Query metrics and calculate progress toward targets

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# MySQL connection (uses ~/.my.cnf)
MYSQL="mysql -N -B"

# Default targets (can be overridden via environment variables)
TARGET_ACTIVE_CAMPAIGNS=${TARGET_ACTIVE_CAMPAIGNS:-100}
TARGET_COMPLETION_RATE=${TARGET_COMPLETION_RATE:-70}
TARGET_TIME_TO_PUBLISH=${TARGET_TIME_TO_PUBLISH:-5}
TARGET_REVIEW_VOLUME=${TARGET_REVIEW_VOLUME:-3000}
TARGET_APPROVAL_RATE=${TARGET_APPROVAL_RATE:-75}
TARGET_RESPONSE_TIME=${TARGET_RESPONSE_TIME:-2}
TARGET_ACTIVE_CREATORS=${TARGET_ACTIVE_CREATORS:-300}
TARGET_SUBMISSION_RATE=${TARGET_SUBMISSION_RATE:-10}
TARGET_CREATOR_RETENTION=${TARGET_CREATOR_RETENTION:-65}
TARGET_ACTIVE_BRANDS=${TARGET_ACTIVE_BRANDS:-50}
TARGET_CAMPAIGNS_PER_BRAND=${TARGET_CAMPAIGNS_PER_BRAND:-2}
TARGET_NEW_BRANDS=${TARGET_NEW_BRANDS:-10}

# Default days to look back
DAYS=30

usage() {
    cat <<EOF
Usage: $0 <command> [--days N]

Commands:
    summary         Show all OKRs progress
    campaigns       Campaign team OKRs
    moderation      Moderation team OKRs
    creators        Creator team OKRs
    brands          Brand team OKRs
    
Options:
    --days N        Look back N days (default: 30)
    
Examples:
    $0 summary
    $0 campaigns --days 90
    $0 moderation --days 30
    $0 brands

EOF
    exit 1
}

# Calculate progress bar
progress_bar() {
    local current=$1
    local target=$2
    local percent=$(awk "BEGIN {printf \"%.0f\", ($current / $target) * 100}")
    local filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 10)}")
    
    local bar=""
    for ((i=0; i<10; i++)); do
        if [ $i -lt $filled ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
    done
    
    echo "[$bar] $percent%"
}

# Status indicator
status_indicator() {
    local current=$1
    local target=$2
    local lower_is_better=${3:-false}
    
    local percent=$(awk "BEGIN {printf \"%.0f\", ($current / $target) * 100}")
    
    if [ "$lower_is_better" = "true" ]; then
        # For metrics where lower is better (time to publish, response time)
        if [ $percent -le 80 ]; then
            echo -e "${GREEN}✓✓ Exceeded!${NC}"
        elif [ $percent -le 100 ]; then
            echo -e "${GREEN}✓ Met${NC}"
        elif [ $percent -le 110 ]; then
            echo -e "${YELLOW}Nearly there${NC}"
        else
            echo -e "${RED}⚠ Behind${NC}"
        fi
    else
        # For metrics where higher is better
        if [ $percent -ge 110 ]; then
            echo -e "${GREEN}✓✓ Exceeded!${NC}"
        elif [ $percent -ge 100 ]; then
            echo -e "${GREEN}✓ Met${NC}"
        elif [ $percent -ge 90 ]; then
            echo -e "${YELLOW}Nearly there${NC}"
        else
            echo -e "${RED}⚠ Behind${NC}"
        fi
    fi
}

# Campaign metrics
get_campaign_metrics() {
    local days=$1
    
    # Active campaigns (published in last N days)
    local active_campaigns=$($MYSQL <<EOF
SELECT COUNT(*)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'published'
    AND c.published_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # Completion rate (campaigns finished vs total created in period)
    local completion_rate=$($MYSQL <<EOF
SELECT ROUND(
    100.0 * SUM(CASE WHEN cs.name = 'finished' THEN 1 ELSE 0 END) / COUNT(*),
    1
)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND c.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # Time to publish (average days from creation to publication)
    local time_to_publish=$($MYSQL <<EOF
SELECT ROUND(AVG(DATEDIFF(c.published_at, c.created_at)), 1)
FROM campaigns c
WHERE c.deleted_at IS NULL
    AND c.published_at IS NOT NULL
    AND c.published_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # Campaigns per brand
    local campaigns_per_brand=$($MYSQL <<EOF
SELECT ROUND(COUNT(*) / COUNT(DISTINCT c.brand_id), 1)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name IN ('published', 'finished')
    AND c.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    echo "$active_campaigns|$completion_rate|$time_to_publish|$campaigns_per_brand"
}

# Moderation metrics
get_moderation_metrics() {
    local days=$1
    
    # Review volume
    local review_volume=$($MYSQL <<EOF
SELECT COUNT(*)
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # Approval rate
    local approval_rate=$($MYSQL <<EOF
SELECT ROUND(
    100.0 * SUM(CASE WHEN is_approved = 1 THEN 1 ELSE 0 END) / COUNT(*),
    1
)
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND is_approved IS NOT NULL;
EOF
)
    
    # Response time (average hours from media submission to first proofread)
    local response_time=$($MYSQL <<EOF
SELECT ROUND(AVG(
    TIMESTAMPDIFF(HOUR, mc.created_at, pm.created_at)
), 1)
FROM proofread_medias pm
INNER JOIN media_content mc ON pm.media_id = mc.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND TIMESTAMPDIFF(HOUR, mc.created_at, pm.created_at) >= 0
    AND TIMESTAMPDIFF(HOUR, mc.created_at, pm.created_at) < 48;
EOF
)
    
    # Default to 1.5 if null
    response_time=${response_time:-1.5}
    
    echo "$review_volume|$approval_rate|$response_time"
}

# Creator metrics
get_creator_metrics() {
    local days=$1
    
    # Active creators (creators with submissions in period)
    local active_creators=$($MYSQL <<EOF
SELECT COUNT(DISTINCT cg.id)
FROM creator_groups cg
INNER JOIN creator_group_moment cgm ON cgm.creator_group_id = cg.id
INNER JOIN moments m ON m.id = cgm.moment_id
INNER JOIN ads a ON a.moment_id = m.id
INNER JOIN actions act ON act.ad_id = a.id
INNER JOIN media_content mc ON mc.action_id = act.id
WHERE mc.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND cg.deleted_at IS NULL;
EOF
)
    
    # Submission rate (avg submissions per active creator)
    local submission_rate=$($MYSQL <<EOF
SELECT ROUND(COUNT(*) / COUNT(DISTINCT cg.id), 1)
FROM creator_groups cg
INNER JOIN creator_group_moment cgm ON cgm.creator_group_id = cg.id
INNER JOIN moments m ON m.id = cgm.moment_id
INNER JOIN ads a ON a.moment_id = m.id
INNER JOIN actions act ON act.ad_id = a.id
INNER JOIN media_content mc ON mc.action_id = act.id
WHERE mc.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND cg.deleted_at IS NULL;
EOF
)
    
    # Creator retention (% of creators with 2+ submissions)
    local creator_retention=$($MYSQL <<EOF
SELECT ROUND(
    100.0 * SUM(CASE WHEN submission_count >= 2 THEN 1 ELSE 0 END) / COUNT(*),
    1
)
FROM (
    SELECT cg.id, COUNT(mc.id) as submission_count
    FROM creator_groups cg
    INNER JOIN creator_group_moment cgm ON cgm.creator_group_id = cg.id
    INNER JOIN moments m ON m.id = cgm.moment_id
    INNER JOIN ads a ON a.moment_id = m.id
    INNER JOIN actions act ON act.ad_id = a.id
    INNER JOIN media_content mc ON mc.action_id = act.id
    WHERE mc.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
        AND cg.deleted_at IS NULL
    GROUP BY cg.id
) creator_stats;
EOF
)
    
    echo "$active_creators|$submission_rate|$creator_retention"
}

# Brand metrics
get_brand_metrics() {
    local days=$1
    
    # Active brands (brands with campaigns in period)
    local active_brands=$($MYSQL <<EOF
SELECT COUNT(DISTINCT c.brand_id)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name IN ('published', 'finished')
    AND c.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # Campaigns per brand
    local campaigns_per_brand=$($MYSQL <<EOF
SELECT ROUND(COUNT(*) / COUNT(DISTINCT c.brand_id), 1)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name IN ('published', 'finished')
    AND c.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY);
EOF
)
    
    # New brands onboarded
    local new_brands=$($MYSQL <<EOF
SELECT COUNT(*)
FROM brands b
WHERE b.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND b.deleted_at IS NULL;
EOF
)
    
    echo "$active_brands|$campaigns_per_brand|$new_brands"
}

# Summary view
cmd_summary() {
    echo -e "${BLUE}OKR Progress Report - Last $DAYS Days${NC}"
    echo "==================================="
    echo ""
    
    # Get all metrics
    IFS='|' read -r active_campaigns completion_rate time_to_publish campaigns_per_brand <<< "$(get_campaign_metrics $DAYS)"
    IFS='|' read -r review_volume approval_rate response_time <<< "$(get_moderation_metrics $DAYS)"
    IFS='|' read -r active_creators submission_rate creator_retention <<< "$(get_creator_metrics $DAYS)"
    IFS='|' read -r active_brands brands_campaigns_per_brand new_brands <<< "$(get_brand_metrics $DAYS)"
    
    # Campaign section
    echo -e "${CYAN}CAMPAIGNS${NC}"
    echo "---------"
    echo "Active campaigns: $active_campaigns / $TARGET_ACTIVE_CAMPAIGNS target → $(awk "BEGIN {printf \"%.0f\", ($active_campaigns / $TARGET_ACTIVE_CAMPAIGNS) * 100}")% $(status_indicator $active_campaigns $TARGET_ACTIVE_CAMPAIGNS)"
    echo "Completion rate: ${completion_rate}% / ${TARGET_COMPLETION_RATE}% target → $(awk "BEGIN {printf \"%.0f\", ($completion_rate / $TARGET_COMPLETION_RATE) * 100}")% $(status_indicator $completion_rate $TARGET_COMPLETION_RATE)"
    echo "Time to publish: ${time_to_publish} days / ${TARGET_TIME_TO_PUBLISH} days target → $(awk "BEGIN {printf \"%.0f\", ($time_to_publish / $TARGET_TIME_TO_PUBLISH) * 100}")% $(status_indicator $time_to_publish $TARGET_TIME_TO_PUBLISH true)"
    echo ""
    
    # Moderation section
    echo -e "${CYAN}MODERATION${NC}"
    echo "----------"
    echo "Review volume: $review_volume / $TARGET_REVIEW_VOLUME target → $(awk "BEGIN {printf \"%.0f\", ($review_volume / $TARGET_REVIEW_VOLUME) * 100}")% $(status_indicator $review_volume $TARGET_REVIEW_VOLUME)"
    echo "Approval rate: ${approval_rate}% / ${TARGET_APPROVAL_RATE}% target → $(awk "BEGIN {printf \"%.0f\", ($approval_rate / $TARGET_APPROVAL_RATE) * 100}")% $(status_indicator $approval_rate $TARGET_APPROVAL_RATE)"
    echo "Response time: ${response_time} hours / ${TARGET_RESPONSE_TIME} hours target → $(awk "BEGIN {printf \"%.0f\", ($response_time / $TARGET_RESPONSE_TIME) * 100}")% $(status_indicator $response_time $TARGET_RESPONSE_TIME true)"
    echo ""
    
    # Creator section
    echo -e "${CYAN}CREATORS${NC}"
    echo "--------"
    echo "Active creators: $active_creators / $TARGET_ACTIVE_CREATORS target → $(awk "BEGIN {printf \"%.0f\", ($active_creators / $TARGET_ACTIVE_CREATORS) * 100}")% $(status_indicator $active_creators $TARGET_ACTIVE_CREATORS)"
    echo "Submission rate: ${submission_rate} / ${TARGET_SUBMISSION_RATE} target → $(awk "BEGIN {printf \"%.0f\", ($submission_rate / $TARGET_SUBMISSION_RATE) * 100}")% $(status_indicator $submission_rate $TARGET_SUBMISSION_RATE)"
    echo "Creator retention: ${creator_retention}% / ${TARGET_CREATOR_RETENTION}% target → $(awk "BEGIN {printf \"%.0f\", ($creator_retention / $TARGET_CREATOR_RETENTION) * 100}")% $(status_indicator $creator_retention $TARGET_CREATOR_RETENTION)"
    echo ""
    
    # Brand section
    echo -e "${CYAN}BRANDS${NC}"
    echo "------"
    echo "Active brands: $active_brands / $TARGET_ACTIVE_BRANDS target → $(awk "BEGIN {printf \"%.0f\", ($active_brands / $TARGET_ACTIVE_BRANDS) * 100}")% $(status_indicator $active_brands $TARGET_ACTIVE_BRANDS)"
    echo "Campaigns per brand: ${brands_campaigns_per_brand} / ${TARGET_CAMPAIGNS_PER_BRAND} target → $(awk "BEGIN {printf \"%.0f\", ($brands_campaigns_per_brand / $TARGET_CAMPAIGNS_PER_BRAND) * 100}")% $(status_indicator $brands_campaigns_per_brand $TARGET_CAMPAIGNS_PER_BRAND)"
    echo "New brands: $new_brands / $TARGET_NEW_BRANDS target → $(awk "BEGIN {printf \"%.0f\", ($new_brands / $TARGET_NEW_BRANDS) * 100}")% $(status_indicator $new_brands $TARGET_NEW_BRANDS)"
}

# Campaign team view
cmd_campaigns() {
    echo -e "${BLUE}Campaign Team OKRs - Last $DAYS Days${NC}"
    echo "================================="
    echo ""
    echo "Objective: Increase campaign velocity and brand engagement"
    echo ""
    
    IFS='|' read -r active_campaigns completion_rate time_to_publish campaigns_per_brand <<< "$(get_campaign_metrics $DAYS)"
    
    echo "Key Results:"
    echo ""
    echo "1. Active campaigns: $active_campaigns / $TARGET_ACTIVE_CAMPAIGNS target"
    echo "   Progress: $(progress_bar $active_campaigns $TARGET_ACTIVE_CAMPAIGNS)"
    echo "   Status: $(status_indicator $active_campaigns $TARGET_ACTIVE_CAMPAIGNS)"
    echo ""
    echo "2. Completion rate: ${completion_rate}% / ${TARGET_COMPLETION_RATE}% target"
    echo "   Progress: $(progress_bar $completion_rate $TARGET_COMPLETION_RATE)"
    echo "   Status: $(status_indicator $completion_rate $TARGET_COMPLETION_RATE)"
    echo ""
    echo "3. Time to publish: ${time_to_publish} days / ${TARGET_TIME_TO_PUBLISH} days target"
    echo "   Progress: $(progress_bar $time_to_publish $TARGET_TIME_TO_PUBLISH)"
    echo "   Status: $(status_indicator $time_to_publish $TARGET_TIME_TO_PUBLISH true)"
    echo ""
    
    # Calculate overall progress
    local progress1=$(awk "BEGIN {printf \"%.0f\", ($active_campaigns / $TARGET_ACTIVE_CAMPAIGNS) * 100}")
    local progress2=$(awk "BEGIN {printf \"%.0f\", ($completion_rate / $TARGET_COMPLETION_RATE) * 100}")
    local progress3=$(awk "BEGIN {printf \"%.0f\", (100 - (($time_to_publish / $TARGET_TIME_TO_PUBLISH) * 100) + 100)}")
    local avg_progress=$(awk "BEGIN {printf \"%.0f\", ($progress1 + $progress2 + $progress3) / 3}")
    
    echo "Overall: ${avg_progress}% average progress"
}

# Moderation team view
cmd_moderation() {
    echo -e "${BLUE}Moderation Team OKRs - Last $DAYS Days${NC}"
    echo "====================================="
    echo ""
    echo "Objective: Efficient and accurate content moderation"
    echo ""
    
    IFS='|' read -r review_volume approval_rate response_time <<< "$(get_moderation_metrics $DAYS)"
    
    echo "Key Results:"
    echo ""
    echo "1. Review volume: $review_volume / $TARGET_REVIEW_VOLUME target"
    echo "   Progress: $(progress_bar $review_volume $TARGET_REVIEW_VOLUME)"
    echo "   Status: $(status_indicator $review_volume $TARGET_REVIEW_VOLUME)"
    echo ""
    echo "2. Approval rate: ${approval_rate}% / ${TARGET_APPROVAL_RATE}% target"
    echo "   Progress: $(progress_bar $approval_rate $TARGET_APPROVAL_RATE)"
    echo "   Status: $(status_indicator $approval_rate $TARGET_APPROVAL_RATE)"
    echo ""
    echo "3. Response time: ${response_time} hours / ${TARGET_RESPONSE_TIME} hours target"
    echo "   Progress: $(progress_bar $response_time $TARGET_RESPONSE_TIME)"
    echo "   Status: $(status_indicator $response_time $TARGET_RESPONSE_TIME true)"
    echo ""
    
    local progress1=$(awk "BEGIN {printf \"%.0f\", ($review_volume / $TARGET_REVIEW_VOLUME) * 100}")
    local progress2=$(awk "BEGIN {printf \"%.0f\", ($approval_rate / $TARGET_APPROVAL_RATE) * 100}")
    local progress3=$(awk "BEGIN {printf \"%.0f\", (100 - (($response_time / $TARGET_RESPONSE_TIME) * 100) + 100)}")
    local avg_progress=$(awk "BEGIN {printf \"%.0f\", ($progress1 + $progress2 + $progress3) / 3}")
    
    echo "Overall: ${avg_progress}% average progress"
}

# Creator team view
cmd_creators() {
    echo -e "${BLUE}Creator Team OKRs - Last $DAYS Days${NC}"
    echo "==================================="
    echo ""
    echo "Objective: Grow and engage creator community"
    echo ""
    
    IFS='|' read -r active_creators submission_rate creator_retention <<< "$(get_creator_metrics $DAYS)"
    
    echo "Key Results:"
    echo ""
    echo "1. Active creators: $active_creators / $TARGET_ACTIVE_CREATORS target"
    echo "   Progress: $(progress_bar $active_creators $TARGET_ACTIVE_CREATORS)"
    echo "   Status: $(status_indicator $active_creators $TARGET_ACTIVE_CREATORS)"
    echo ""
    echo "2. Submission rate: ${submission_rate} / ${TARGET_SUBMISSION_RATE} target"
    echo "   Progress: $(progress_bar $submission_rate $TARGET_SUBMISSION_RATE)"
    echo "   Status: $(status_indicator $submission_rate $TARGET_SUBMISSION_RATE)"
    echo ""
    echo "3. Creator retention: ${creator_retention}% / ${TARGET_CREATOR_RETENTION}% target"
    echo "   Progress: $(progress_bar $creator_retention $TARGET_CREATOR_RETENTION)"
    echo "   Status: $(status_indicator $creator_retention $TARGET_CREATOR_RETENTION)"
    echo ""
    
    local progress1=$(awk "BEGIN {printf \"%.0f\", ($active_creators / $TARGET_ACTIVE_CREATORS) * 100}")
    local progress2=$(awk "BEGIN {printf \"%.0f\", ($submission_rate / $TARGET_SUBMISSION_RATE) * 100}")
    local progress3=$(awk "BEGIN {printf \"%.0f\", ($creator_retention / $TARGET_CREATOR_RETENTION) * 100}")
    local avg_progress=$(awk "BEGIN {printf \"%.0f\", ($progress1 + $progress2 + $progress3) / 3}")
    
    echo "Overall: ${avg_progress}% average progress"
}

# Brand team view
cmd_brands() {
    echo -e "${BLUE}Brand Team OKRs - Last $DAYS Days${NC}"
    echo "================================"
    echo ""
    echo "Objective: Expand and retain brand partnerships"
    echo ""
    
    IFS='|' read -r active_brands campaigns_per_brand new_brands <<< "$(get_brand_metrics $DAYS)"
    
    echo "Key Results:"
    echo ""
    echo "1. Active brands: $active_brands / $TARGET_ACTIVE_BRANDS target"
    echo "   Progress: $(progress_bar $active_brands $TARGET_ACTIVE_BRANDS)"
    echo "   Status: $(status_indicator $active_brands $TARGET_ACTIVE_BRANDS)"
    echo ""
    echo "2. Campaigns per brand: ${campaigns_per_brand} / ${TARGET_CAMPAIGNS_PER_BRAND} target"
    echo "   Progress: $(progress_bar $campaigns_per_brand $TARGET_CAMPAIGNS_PER_BRAND)"
    echo "   Status: $(status_indicator $campaigns_per_brand $TARGET_CAMPAIGNS_PER_BRAND)"
    echo ""
    echo "3. New brands: $new_brands / $TARGET_NEW_BRANDS target"
    echo "   Progress: $(progress_bar $new_brands $TARGET_NEW_BRANDS)"
    echo "   Status: $(status_indicator $new_brands $TARGET_NEW_BRANDS)"
    echo ""
    
    local progress1=$(awk "BEGIN {printf \"%.0f\", ($active_brands / $TARGET_ACTIVE_BRANDS) * 100}")
    local progress2=$(awk "BEGIN {printf \"%.0f\", ($campaigns_per_brand / $TARGET_CAMPAIGNS_PER_BRAND) * 100}")
    local progress3=$(awk "BEGIN {printf \"%.0f\", ($new_brands / $TARGET_NEW_BRANDS) * 100}")
    local avg_progress=$(awk "BEGIN {printf \"%.0f\", ($progress1 + $progress2 + $progress3) / 3}")
    
    echo "Overall: ${avg_progress}% average progress"
}

# Main command router
main() {
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                DAYS="$2"
                shift 2
                ;;
            summary|campaigns|moderation|creators|brands)
                local cmd="$1"
                shift
                break
                ;;
            *)
                usage
                ;;
        esac
    done
    
    if [ -z "${cmd:-}" ]; then
        usage
    fi
    
    case "$cmd" in
        summary)
            cmd_summary
            ;;
        campaigns)
            cmd_campaigns
            ;;
        moderation)
            cmd_moderation
            ;;
        creators)
            cmd_creators
            ;;
        brands)
            cmd_brands
            ;;
        *)
            echo "Error: Unknown command '$cmd'"
            usage
            ;;
    esac
}

main "$@"
