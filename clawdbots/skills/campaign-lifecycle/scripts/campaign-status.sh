#!/bin/bash
# Campaign Lifecycle Status Tracker
# Query campaign states and identify stuck/alert-worthy campaigns

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
    summary                     Show count of campaigns per state
    stuck <state> <days>       Show campaigns stuck in state for N+ days
    timeline <campaign_id>     Show timeline for specific campaign
    alerts                      Show all alert-worthy campaigns
    
Examples:
    $0 summary
    $0 stuck draft 30
    $0 stuck published 7
    $0 alerts
    $0 timeline 123

EOF
    exit 1
}

# Summary: Count campaigns by state
cmd_summary() {
    echo -e "${BLUE}Campaign Status Summary${NC}"
    echo "======================="
    
    $MYSQL <<EOF
SELECT 
    cs.name as state,
    COUNT(*) as count,
    CONCAT(
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1),
        '%'
    ) as percentage
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
GROUP BY cs.name
ORDER BY 
    FIELD(cs.name, 'draft', 'published', 'paused', 'finished');
EOF
}

# Stuck: Campaigns in a state for N+ days without updates
cmd_stuck() {
    local state="$1"
    local days="$2"
    
    echo -e "${YELLOW}Campaigns stuck in '$state' for $days+ days${NC}"
    echo "=========================================="
    
    $MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    DATEDIFF(NOW(), c.updated_at) as days_stuck,
    DATE_FORMAT(c.updated_at, '%Y-%m-%d') as last_update
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = '$state'
    AND DATEDIFF(NOW(), c.updated_at) >= $days
ORDER BY c.updated_at ASC
LIMIT 50;
EOF
}

# Timeline: Show campaign lifecycle events
cmd_timeline() {
    local campaign_id="$1"
    
    echo -e "${BLUE}Campaign Timeline: #$campaign_id${NC}"
    echo "==============================="
    
    # Get campaign basic info
    $MYSQL <<EOF
SELECT 
    CONCAT('Title: ', c.title) as info
FROM campaigns c
WHERE c.id = $campaign_id;
EOF
    
    echo ""
    echo -e "${GREEN}Lifecycle Events:${NC}"
    
    # Show key dates
    $MYSQL <<EOF
SELECT 
    DATE_FORMAT(c.created_at, '%Y-%m-%d %H:%i') as timestamp,
    'Created (draft)' as event,
    cs.name as current_state
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.id = $campaign_id

UNION ALL

SELECT 
    DATE_FORMAT(c.published_at, '%Y-%m-%d %H:%i') as timestamp,
    'Published' as event,
    '' as state
FROM campaigns c
WHERE c.id = $campaign_id
    AND c.published_at IS NOT NULL

UNION ALL

SELECT 
    DATE_FORMAT(c.updated_at, '%Y-%m-%d %H:%i') as timestamp,
    'Last Updated' as event,
    cs.name as current_state
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.id = $campaign_id

ORDER BY timestamp ASC;
EOF

    echo ""
    echo -e "${GREEN}Activity Stats:${NC}"
    
    # Show submission stats
    $MYSQL <<EOF
SELECT 
    COUNT(DISTINCT mc.id) as total_submissions,
    COUNT(DISTINCT CASE WHEN a.approved_at IS NOT NULL THEN mc.id END) as approved,
    COUNT(DISTINCT CASE WHEN mc.refused_at IS NOT NULL THEN mc.id END) as refused,
    COUNT(DISTINCT CASE 
        WHEN a.approved_at IS NULL AND mc.refused_at IS NULL 
        THEN mc.id 
    END) as pending
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads ad ON ad.moment_id = m.id
INNER JOIN actions a ON a.ad_id = ad.id
LEFT JOIN media_content mc ON mc.action_id = a.id
WHERE c.id = $campaign_id
    AND c.deleted_at IS NULL;
EOF
}

# Alerts: Show campaigns needing attention
cmd_alerts() {
    echo -e "${RED}⚠️  ALERTS - Campaigns Needing Attention${NC}"
    echo "========================================"
    echo ""
    
    echo -e "${RED}HIGH PRIORITY:${NC}"
    echo "Published campaigns with 0 submissions in 7+ days"
    echo "---------------------------------------------------"
    
    $MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    DATEDIFF(NOW(), c.updated_at) as days_published,
    COALESCE(submission_count, 0) as submissions
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
LEFT JOIN (
    SELECT 
        c2.id as campaign_id,
        COUNT(DISTINCT mc.id) as submission_count
    FROM campaigns c2
    INNER JOIN moments m ON m.campaign_id = c2.id
    INNER JOIN ads ad ON ad.moment_id = m.id
    INNER JOIN actions a ON a.ad_id = ad.id
    LEFT JOIN media_content mc ON mc.action_id = a.id
    WHERE c2.deleted_at IS NULL
    GROUP BY c2.id
) stats ON stats.campaign_id = c.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'published'
    AND DATEDIFF(NOW(), c.updated_at) >= 7
    AND COALESCE(submission_count, 0) = 0
ORDER BY days_published DESC
LIMIT 20;
EOF

    echo ""
    echo "Draft campaigns stuck >30 days"
    echo "--------------------------------"
    
    $MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    DATEDIFF(NOW(), c.created_at) as days_in_draft
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'draft'
    AND DATEDIFF(NOW(), c.created_at) >= 30
ORDER BY days_in_draft DESC
LIMIT 20;
EOF

    echo ""
    echo -e "${YELLOW}MEDIUM PRIORITY:${NC}"
    echo "Recently updated campaigns (potential review needed)"
    echo "----------------------------------------------------"
    
    $MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    cs.name as state,
    DATEDIFF(NOW(), c.updated_at) as days_since_update
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND DATEDIFF(NOW(), c.updated_at) BETWEEN 1 AND 3
    AND cs.name IN ('published', 'paused')
ORDER BY c.updated_at DESC
LIMIT 10;
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
        stuck)
            if [ $# -lt 2 ]; then
                echo "Error: stuck command requires <state> <days>"
                usage
            fi
            cmd_stuck "$1" "$2"
            ;;
        timeline)
            if [ $# -lt 1 ]; then
                echo "Error: timeline command requires <campaign_id>"
                usage
            fi
            cmd_timeline "$1"
            ;;
        alerts)
            cmd_alerts
            ;;
        *)
            echo "Error: Unknown command '$cmd'"
            usage
            ;;
    esac
}

main "$@"
