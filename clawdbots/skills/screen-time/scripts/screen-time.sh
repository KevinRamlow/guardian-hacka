#!/bin/bash
# Screen Time and View Retention Analytics
# Query sequential screen usage and content engagement metrics

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# MySQL connection (uses ~/.my.cnf)
MYSQL="mysql -N -B"

usage() {
    cat <<EOF
Usage: $0 <command> [args]

Commands:
    summary                     Overview of screen usage across campaigns
    distribution               Distribution of screen counts
    campaign <campaign_id>     Screen metrics for specific campaign
    top-campaigns <limit>      Top campaigns by multi-screen content
    creators <campaign_id>     Creators with multi-screen submissions
    
Examples:
    $0 summary
    $0 distribution
    $0 campaign 123
    $0 top-campaigns 10
    $0 creators 123

EOF
    exit 1
}

# Summary: Overview of screen usage
cmd_summary() {
    echo -e "${BLUE}Screen Time Analytics Summary${NC}"
    echo "=============================="
    echo ""
    
    echo -e "${GREEN}Overall Metrics:${NC}"
    $MYSQL <<EOF
SELECT 
    COUNT(DISTINCT c.id) as total_campaigns,
    COUNT(DISTINCT a.id) as total_ads,
    COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) as multi_screen_ads,
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) 
        / NULLIF(COUNT(DISTINCT a.id), 0), 
        2
    ) as multi_screen_percentage,
    ROUND(AVG(CASE WHEN a.number_of_sequential_screens IS NOT NULL THEN a.number_of_sequential_screens END), 2) as avg_screens_per_ad,
    MAX(a.number_of_sequential_screens) as max_screens
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
WHERE c.deleted_at IS NULL
    AND a.deleted_at IS NULL;
EOF

    echo ""
    echo -e "${GREEN}By Campaign State:${NC}"
    $MYSQL <<EOF
SELECT 
    cs.name as state,
    COUNT(DISTINCT a.id) as total_ads,
    COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) as multi_screen_ads,
    ROUND(AVG(CASE WHEN a.number_of_sequential_screens IS NOT NULL THEN a.number_of_sequential_screens END), 2) as avg_screens
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
WHERE c.deleted_at IS NULL
    AND a.deleted_at IS NULL
GROUP BY cs.name
ORDER BY FIELD(cs.name, 'draft', 'published', 'paused', 'finished');
EOF
}

# Distribution: Show distribution of screen counts
cmd_distribution() {
    echo -e "${BLUE}Screen Count Distribution${NC}"
    echo "========================="
    echo ""
    
    $MYSQL <<EOF
SELECT 
    COALESCE(a.number_of_sequential_screens, 1) as screens,
    COUNT(*) as ad_count,
    CONCAT(
        RPAD('█', 
            CAST(50.0 * COUNT(*) / (SELECT COUNT(*) FROM ads WHERE deleted_at IS NULL) AS SIGNED),
            '█'
        )
    ) as distribution
FROM ads a
WHERE a.deleted_at IS NULL
GROUP BY COALESCE(a.number_of_sequential_screens, 1)
ORDER BY screens ASC;
EOF

    echo ""
    echo -e "${GREEN}Screen Usage Ranges:${NC}"
    $MYSQL <<EOF
SELECT 
    CASE 
        WHEN COALESCE(a.number_of_sequential_screens, 1) = 1 THEN '1 screen (single)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 2 AND 3 THEN '2-3 screens (short)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 4 AND 6 THEN '4-6 screens (medium)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 7 AND 10 THEN '7-10 screens (long)'
        ELSE '10+ screens (extended)'
    END as screen_range,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM ads WHERE deleted_at IS NULL), 2) as percentage
FROM ads a
WHERE a.deleted_at IS NULL
GROUP BY 
    CASE 
        WHEN COALESCE(a.number_of_sequential_screens, 1) = 1 THEN '1 screen (single)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 2 AND 3 THEN '2-3 screens (short)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 4 AND 6 THEN '4-6 screens (medium)'
        WHEN COALESCE(a.number_of_sequential_screens, 1) BETWEEN 7 AND 10 THEN '7-10 screens (long)'
        ELSE '10+ screens (extended)'
    END
ORDER BY MIN(COALESCE(a.number_of_sequential_screens, 1));
EOF
}

# Campaign: Screen metrics for specific campaign
cmd_campaign() {
    local campaign_id="$1"
    
    echo -e "${BLUE}Screen Metrics for Campaign #$campaign_id${NC}"
    echo "=========================================="
    echo ""
    
    # Campaign info
    echo -e "${GREEN}Campaign Details:${NC}"
    $MYSQL <<EOF
SELECT 
    c.id,
    c.title,
    cs.name as state,
    COUNT(DISTINCT a.id) as total_ads,
    COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) as multi_screen_ads,
    ROUND(AVG(CASE WHEN a.number_of_sequential_screens IS NOT NULL THEN a.number_of_sequential_screens END), 2) as avg_screens,
    MAX(a.number_of_sequential_screens) as max_screens
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
WHERE c.id = $campaign_id
    AND c.deleted_at IS NULL
    AND a.deleted_at IS NULL
GROUP BY c.id, c.title, cs.name;
EOF

    echo ""
    echo -e "${GREEN}Ads by Screen Count:${NC}"
    $MYSQL <<EOF
SELECT 
    a.id as ad_id,
    LEFT(a.title, 40) as ad_title,
    COALESCE(a.number_of_sequential_screens, 1) as screens,
    COUNT(DISTINCT ac.id) as submissions
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
LEFT JOIN actions ac ON ac.ad_id = a.id
WHERE c.id = $campaign_id
    AND c.deleted_at IS NULL
    AND a.deleted_at IS NULL
GROUP BY a.id, a.title, a.number_of_sequential_screens
ORDER BY COALESCE(a.number_of_sequential_screens, 1) DESC;
EOF

    echo ""
    echo -e "${GREEN}Screen Distribution:${NC}"
    $MYSQL <<EOF
SELECT 
    COALESCE(a.number_of_sequential_screens, 1) as screens,
    COUNT(*) as count
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
WHERE c.id = $campaign_id
    AND c.deleted_at IS NULL
    AND a.deleted_at IS NULL
GROUP BY COALESCE(a.number_of_sequential_screens, 1)
ORDER BY screens DESC;
EOF
}

# Top Campaigns: Campaigns with most multi-screen content
cmd_top_campaigns() {
    local limit="${1:-10}"
    
    echo -e "${BLUE}Top $limit Campaigns by Multi-Screen Usage${NC}"
    echo "==========================================="
    echo ""
    
    $MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    cs.name as state,
    COUNT(DISTINCT a.id) as total_ads,
    COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) as multi_screen_ads,
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) 
        / NULLIF(COUNT(DISTINCT a.id), 0), 
        2
    ) as multi_screen_pct,
    ROUND(AVG(CASE WHEN a.number_of_sequential_screens IS NOT NULL THEN a.number_of_sequential_screens END), 2) as avg_screens
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
WHERE c.deleted_at IS NULL
    AND a.deleted_at IS NULL
GROUP BY c.id, c.title, cs.name
HAVING COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN a.id END) > 0
ORDER BY multi_screen_ads DESC, avg_screens DESC
LIMIT $limit;
EOF
}

# Creators: Creators with multi-screen submissions for a campaign
cmd_creators() {
    local campaign_id="$1"
    
    echo -e "${BLUE}Creators with Multi-Screen Content - Campaign #$campaign_id${NC}"
    echo "============================================================="
    echo ""
    
    $MYSQL <<EOF
SELECT 
    u.id as creator_id,
    u.name as creator_name,
    COUNT(DISTINCT ac.id) as total_actions,
    COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN ac.id END) as multi_screen_actions,
    COUNT(DISTINCT mc.id) as media_submissions,
    ROUND(AVG(CASE WHEN a.number_of_sequential_screens IS NOT NULL THEN a.number_of_sequential_screens END), 2) as avg_screens
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads a ON a.moment_id = m.id
INNER JOIN actions ac ON ac.ad_id = a.id
LEFT JOIN media_content mc ON mc.action_id = ac.id
INNER JOIN user u ON u.id = ac.creator_id
WHERE c.id = $campaign_id
    AND c.deleted_at IS NULL
    AND a.deleted_at IS NULL
    AND ac.deleted_at IS NULL
GROUP BY u.id, u.name
HAVING COUNT(DISTINCT CASE WHEN a.number_of_sequential_screens > 1 THEN ac.id END) > 0
ORDER BY multi_screen_actions DESC, avg_screens DESC;
EOF
}

# Main command router
main() {
    if [ $# -lt 1 ]; then
        usage
    fi
    
    local cmd="$1"
    shift
    
    case "$cmd" in
        summary)
            cmd_summary
            ;;
        distribution)
            cmd_distribution
            ;;
        campaign)
            if [ $# -lt 1 ]; then
                echo "Error: campaign command requires <campaign_id>"
                usage
            fi
            cmd_campaign "$1"
            ;;
        top-campaigns)
            local limit="${1:-10}"
            cmd_top_campaigns "$limit"
            ;;
        creators)
            if [ $# -lt 1 ]; then
                echo "Error: creators command requires <campaign_id>"
                usage
            fi
            cmd_creators "$1"
            ;;
        *)
            echo "Error: Unknown command '$cmd'"
            usage
            ;;
    esac
}

main "$@"
