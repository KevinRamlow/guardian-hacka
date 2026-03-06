#!/bin/bash
# Contest Analysis Tool
# Analyze creator contest patterns against Guardian moderation decisions

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
    overall <days>              Overall contest statistics
    by-brand <days> [brand_id]  Contest rate by brand
    by-campaign <days> [cid]    Contest rate by campaign
    status <days>               Contest status breakdown
    pending                     Show pending contests awaiting review
    top-brands <days> [limit]   Brands with most contests
    trend <days>                Daily contest trend
    
Examples:
    $0 overall 30
    $0 by-brand 30
    $0 by-brand 30 882
    $0 by-campaign 30
    $0 status 30
    $0 pending
    $0 top-brands 30 10
    $0 trend 14

EOF
    exit 1
}

# Overall: Calculate overall contest statistics
cmd_overall() {
    local days="$1"
    
    echo -e "${BLUE}Contest Analysis (Last $days Days)${NC}"
    echo "================================"
    echo ""
    
    local result=$($MYSQL <<EOF
SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) as approved,
    SUM(CASE WHEN status = 'reproved' THEN 1 ELSE 0 END) as reproved,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL;
EOF
)
    
    local total=$(echo "$result" | cut -f1)
    local approved=$(echo "$result" | cut -f2)
    local reproved=$(echo "$result" | cut -f3)
    local pending=$(echo "$result" | cut -f4)
    
    if [ "$total" -eq 0 ]; then
        echo "No contests found in the last $days days."
        return
    fi
    
    local approved_pct=$(awk "BEGIN {printf \"%.1f\", 100.0 * $approved / $total}")
    local reproved_pct=$(awk "BEGIN {printf \"%.1f\", 100.0 * $reproved / $total}")
    local pending_pct=$(awk "BEGIN {printf \"%.1f\", 100.0 * $pending / $total}")
    
    # Calculate approval rate (exclude pending)
    local resolved=$((approved + reproved))
    local approval_rate="N/A"
    if [ "$resolved" -gt 0 ]; then
        approval_rate=$(awk "BEGIN {printf \"%.1f\", 100.0 * $approved / $resolved}")
    fi
    
    printf "Total Contests:       %'d\n" "$total"
    printf "├─ Approved:          %'d (%s%%)\n" "$approved" "$approved_pct"
    printf "├─ Reproved:          %'d (%s%%)\n" "$reproved" "$reproved_pct"
    printf "└─ Pending:           %'d (%s%%)\n" "$pending" "$pending_pct"
    echo ""
    
    if [ "$resolved" -gt 0 ]; then
        printf "Contest Approval Rate: ${GREEN}%s%%${NC} (approved / (approved + reproved))\n" "$approval_rate"
        
        # Interpretation
        if (( $(echo "$approval_rate > 70" | bc -l) )); then
            echo -e "${YELLOW}⚠️  High approval rate suggests Guardian may be too strict${NC}"
        elif (( $(echo "$approval_rate < 40" | bc -l) )); then
            echo -e "${GREEN}✅ Low approval rate indicates good Guardian accuracy${NC}"
        else
            echo -e "ℹ️  Moderate approval rate — within normal range"
        fi
    fi
}

# By Brand: Contest rate per brand
cmd_by_brand() {
    local days="$1"
    local brand_id="${2:-}"
    
    echo -e "${BLUE}Contest Rate by Brand (Last $days Days)${NC}"
    echo "======================================"
    echo ""
    
    local where_clause="WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL"
    
    if [ -n "$brand_id" ]; then
        where_clause="$where_clause AND pm.brand_id = $brand_id"
    fi
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    pm.brand_id as 'Brand_ID',
    b.name as 'Brand_Name',
    COUNT(DISTINCT pmc.id) as 'Contests',
    SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) as 'Approved',
    SUM(CASE WHEN pmc.status = 'reproved' THEN 1 ELSE 0 END) as 'Reproved',
    SUM(CASE WHEN pmc.status = 'pending' THEN 1 ELSE 0 END) as 'Pending',
    CONCAT(
        ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1),
        '%'
    ) as 'Approval_Rate',
    CASE 
        WHEN ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1) > 70 THEN '⚠️  HIGH'
        WHEN ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1) < 40 THEN '✅ GOOD'
        ELSE 'OK'
    END as 'Status'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
INNER JOIN brands b ON pm.brand_id = b.id
$where_clause
GROUP BY pm.brand_id, b.name
HAVING COUNT(DISTINCT pmc.id) >= 5
ORDER BY COUNT(DISTINCT pmc.id) DESC;
EOF
}

# By Campaign: Contest rate per campaign
cmd_by_campaign() {
    local days="$1"
    local campaign_id="${2:-}"
    
    echo -e "${BLUE}Contest Rate by Campaign (Last $days Days)${NC}"
    echo "=========================================="
    echo ""
    
    local where_clause="WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL"
    
    if [ -n "$campaign_id" ]; then
        where_clause="$where_clause AND pm.campaign_id = $campaign_id"
    fi
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    pm.campaign_id as 'Campaign_ID',
    LEFT(c.title, 40) as 'Campaign_Title',
    COUNT(DISTINCT pmc.id) as 'Contests',
    SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) as 'Approved',
    SUM(CASE WHEN pmc.status = 'reproved' THEN 1 ELSE 0 END) as 'Reproved',
    SUM(CASE WHEN pmc.status = 'pending' THEN 1 ELSE 0 END) as 'Pending',
    CONCAT(
        ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1),
        '%'
    ) as 'Approval_Rate'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
INNER JOIN campaigns c ON pm.campaign_id = c.id
$where_clause
GROUP BY pm.campaign_id, c.title
HAVING COUNT(DISTINCT pmc.id) >= 5
ORDER BY COUNT(DISTINCT pmc.id) DESC;
EOF
}

# Status: Contest status breakdown
cmd_status() {
    local days="$1"
    
    echo -e "${BLUE}Contest Status Breakdown (Last $days Days)${NC}"
    echo "=========================================="
    echo ""
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    pmc.status as 'Status',
    COUNT(*) as 'Count',
    CONCAT(ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM proofread_media_contest pmc2 
        INNER JOIN proofread_medias pm2 ON pmc2.proofread_media_id = pm2.id 
        WHERE pm2.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY) 
        AND pm2.deleted_at IS NULL), 1), '%') as 'Percentage'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL
GROUP BY pmc.status
ORDER BY COUNT(*) DESC;
EOF
}

# Pending: Show pending contests awaiting review
cmd_pending() {
    echo -e "${YELLOW}Pending Contests Awaiting Review${NC}"
    echo "================================="
    echo ""
    
    local count=$($MYSQL <<EOF
SELECT COUNT(*) 
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
WHERE pmc.status = 'pending'
    AND pm.deleted_at IS NULL;
EOF
)
    
    echo "Total Pending: $count contests"
    echo ""
    
    if [ "$count" -eq 0 ]; then
        echo "✅ No pending contests"
        return
    fi
    
    echo "Recent Pending (Last 20):"
    echo ""
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    pmc.id as 'Contest_ID',
    pm.brand_id as 'Brand_ID',
    b.name as 'Brand_Name',
    pmc.created_at as 'Created_At',
    CONCAT(DATEDIFF(NOW(), pmc.created_at), ' days') as 'Days_Pending',
    LEFT(pmc.reason, 50) as 'Reason_Preview'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
INNER JOIN brands b ON pm.brand_id = b.id
WHERE pmc.status = 'pending'
    AND pm.deleted_at IS NULL
ORDER BY pmc.created_at ASC
LIMIT 20;
EOF
    
    if [ "$count" -gt 50 ]; then
        echo ""
        echo -e "${RED}⚠️  High pending backlog ($count contests) — need faster review${NC}"
    fi
}

# Top Brands: Brands with most contests
cmd_top_brands() {
    local days="$1"
    local limit="${2:-10}"
    
    echo -e "${BLUE}Top $limit Brands with Most Contests (Last $days Days)${NC}"
    echo "================================================"
    echo ""
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    pm.brand_id as 'Brand_ID',
    b.name as 'Brand_Name',
    COUNT(DISTINCT pmc.id) as 'Total_Contests',
    SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) as 'Approved',
    SUM(CASE WHEN pmc.status = 'reproved' THEN 1 ELSE 0 END) as 'Reproved',
    SUM(CASE WHEN pmc.status = 'pending' THEN 1 ELSE 0 END) as 'Pending',
    CONCAT(
        ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1),
        '%'
    ) as 'Approval_Rate'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
INNER JOIN brands b ON pm.brand_id = b.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL
GROUP BY pm.brand_id, b.name
ORDER BY COUNT(DISTINCT pmc.id) DESC
LIMIT $limit;
EOF
}

# Trend: Daily contest trend over time
cmd_trend() {
    local days="$1"
    
    echo -e "${BLUE}Daily Contest Trend (Last $days Days)${NC}"
    echo "====================================="
    echo ""
    
    $MYSQL <<EOF | column -t -s $'\t'
SELECT 
    DATE(pm.created_at) as 'Date',
    COUNT(DISTINCT pmc.id) as 'Contests',
    SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) as 'Approved',
    SUM(CASE WHEN pmc.status = 'reproved' THEN 1 ELSE 0 END) as 'Reproved',
    SUM(CASE WHEN pmc.status = 'pending' THEN 1 ELSE 0 END) as 'Pending',
    CONCAT(
        ROUND(100.0 * SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN pmc.status IN ('approved', 'reproved') THEN 1 ELSE 0 END), 0), 
            1),
        '%'
    ) as 'Approval_%'
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL
GROUP BY DATE(pm.created_at)
ORDER BY DATE(pm.created_at) DESC;
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
        overall)
            if [ $# -lt 1 ]; then
                echo "Error: overall command requires <days>"
                usage
            fi
            cmd_overall "$1"
            ;;
        by-brand)
            if [ $# -lt 1 ]; then
                echo "Error: by-brand command requires <days>"
                usage
            fi
            cmd_by_brand "$@"
            ;;
        by-campaign)
            if [ $# -lt 1 ]; then
                echo "Error: by-campaign command requires <days>"
                usage
            fi
            cmd_by_campaign "$@"
            ;;
        status)
            if [ $# -lt 1 ]; then
                echo "Error: status command requires <days>"
                usage
            fi
            cmd_status "$1"
            ;;
        pending)
            cmd_pending
            ;;
        top-brands)
            if [ $# -lt 1 ]; then
                echo "Error: top-brands command requires <days>"
                usage
            fi
            cmd_top_brands "$@"
            ;;
        trend)
            if [ $# -lt 1 ]; then
                echo "Error: trend command requires <days>"
                usage
            fi
            cmd_trend "$1"
            ;;
        *)
            echo "Error: Unknown command '$cmd'"
            usage
            ;;
    esac
}

main "$@"
