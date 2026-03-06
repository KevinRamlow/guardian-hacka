#!/bin/bash
# Guardian Agreement Rate Monitor
# Calculate and track Guardian AI agreement rate with human reviewers

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
    overall <days>              Overall agreement rate for last N days
    by-brand <days> [brand_id]  Agreement rate by brand
    by-campaign <days> [cid]    Agreement rate by campaign
    alerts <threshold>          Show brands/campaigns below threshold
    trend <days>                Daily agreement rate trend
    
Examples:
    $0 overall 7
    $0 by-brand 7
    $0 by-brand 7 45
    $0 by-campaign 7
    $0 alerts 80
    $0 trend 14

EOF
    exit 1
}

# Overall: Calculate overall agreement rate
cmd_overall() {
    local days="$1"
    
    echo -e "${BLUE}Guardian Agreement Rate (Last $days Days)${NC}"
    echo "====================================="
    
    local result=$($MYSQL <<EOF
SELECT 
    COUNT(*) as total_evals,
    SUM(correct_answers) as total_correct,
    SUM(incorrect_answers) as total_incorrect,
    ROUND(100.0 * SUM(correct_answers) / (SUM(correct_answers) + SUM(incorrect_answers)), 1) as rate
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND deleted_at IS NULL
    AND correct_answers IS NOT NULL
    AND incorrect_answers IS NOT NULL;
EOF
)
    
    local evals=$(echo "$result" | cut -f1)
    local correct=$(echo "$result" | cut -f2)
    local incorrect=$(echo "$result" | cut -f3)
    local rate=$(echo "$result" | cut -f4)
    
    printf "Total Evaluations: %'d\n" "$evals"
    printf "Correct Answers:   %'d\n" "$correct"
    printf "Incorrect Answers: %'d\n" "$incorrect"
    printf "Agreement Rate:    ${GREEN}%s%%${NC}\n" "$rate"
    
    # Status indicator
    if (( $(echo "$rate < 75" | bc -l) )); then
        echo -e "${RED}⚠️  CRITICAL: Rate below 75%${NC}"
    elif (( $(echo "$rate < 80" | bc -l) )); then
        echo -e "${YELLOW}⚠️  WARNING: Rate below 80%${NC}"
    else
        echo -e "${GREEN}✅ Status: Good${NC}"
    fi
}

# By Brand: Agreement rate per brand
cmd_by_brand() {
    local days="$1"
    local brand_id="${2:-}"
    
    echo -e "${BLUE}Agreement Rate by Brand (Last $days Days)${NC}"
    echo "========================================"
    
    local where_clause="WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL
    AND pm.correct_answers IS NOT NULL
    AND pm.incorrect_answers IS NOT NULL"
    
    if [ -n "$brand_id" ]; then
        where_clause="$where_clause AND pm.brand_id = $brand_id"
    fi
    
    $MYSQL <<EOF
SELECT 
    pm.brand_id,
    b.name as brand_name,
    COUNT(*) as evals,
    SUM(pm.correct_answers) as correct,
    SUM(pm.incorrect_answers) as incorrect,
    ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate,
    CASE 
        WHEN ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) >= 80 THEN '✅ OK'
        WHEN ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) >= 75 THEN '⚠️  WARNING'
        ELSE '🚨 CRITICAL'
    END as status
FROM proofread_medias pm
INNER JOIN brands b ON b.id = pm.brand_id
$where_clause
GROUP BY pm.brand_id, b.name
HAVING COUNT(*) >= 10
ORDER BY rate ASC, evals DESC;
EOF
}

# By Campaign: Agreement rate per campaign
cmd_by_campaign() {
    local days="$1"
    local campaign_id="${2:-}"
    
    echo -e "${BLUE}Agreement Rate by Campaign (Last $days Days)${NC}"
    echo "=========================================="
    
    local where_clause="WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND pm.deleted_at IS NULL
    AND pm.correct_answers IS NOT NULL
    AND pm.incorrect_answers IS NOT NULL"
    
    if [ -n "$campaign_id" ]; then
        where_clause="$where_clause AND pm.campaign_id = $campaign_id"
    fi
    
    $MYSQL <<EOF
SELECT 
    pm.campaign_id,
    LEFT(c.title, 40) as campaign_title,
    COUNT(*) as evals,
    SUM(pm.correct_answers) as correct,
    SUM(pm.incorrect_answers) as incorrect,
    ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate,
    CASE 
        WHEN ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) >= 80 THEN '✅ OK'
        WHEN ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) >= 75 THEN '⚠️  WARNING'
        ELSE '🚨 CRITICAL'
    END as status
FROM proofread_medias pm
INNER JOIN campaigns c ON c.id = pm.campaign_id
$where_clause
GROUP BY pm.campaign_id, c.title
HAVING COUNT(*) >= 10
ORDER BY rate ASC, evals DESC;
EOF
}

# Alerts: Show brands/campaigns below threshold
cmd_alerts() {
    local threshold="${1:-80}"
    
    echo -e "${RED}⚠️  Agreement Rate Alerts (Threshold: ${threshold}%)${NC}"
    echo "================================================"
    echo ""
    
    # Check overall rate
    local overall_rate=$($MYSQL <<EOF
SELECT 
    ROUND(100.0 * SUM(correct_answers) / (SUM(correct_answers) + SUM(incorrect_answers)), 1) as rate
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    AND deleted_at IS NULL
    AND correct_answers IS NOT NULL
    AND incorrect_answers IS NOT NULL;
EOF
)
    
    if (( $(echo "$overall_rate < $threshold" | bc -l) )); then
        echo -e "${RED}HIGH PRIORITY: Overall rate ${overall_rate}% < ${threshold}%${NC}"
        echo ""
    fi
    
    # Brands below threshold
    echo -e "${YELLOW}Brands Below Threshold (Last 7 Days):${NC}"
    echo "--------------------------------------"
    
    local brands_count=$($MYSQL <<EOF
SELECT COUNT(*) FROM (
    SELECT 
        pm.brand_id,
        ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate
    FROM proofread_medias pm
    WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        AND pm.deleted_at IS NULL
        AND pm.correct_answers IS NOT NULL
        AND pm.incorrect_answers IS NOT NULL
    GROUP BY pm.brand_id
    HAVING COUNT(*) >= 10 AND rate < $threshold
) t;
EOF
)
    
    if [ "$brands_count" -gt 0 ]; then
        $MYSQL <<EOF
SELECT 
    pm.brand_id,
    b.name as brand_name,
    COUNT(*) as evals,
    ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate,
    CONCAT(
        ROUND($threshold - ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1), 1),
        'pp below'
    ) as gap
FROM proofread_medias pm
INNER JOIN brands b ON b.id = pm.brand_id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    AND pm.deleted_at IS NULL
    AND pm.correct_answers IS NOT NULL
    AND pm.incorrect_answers IS NOT NULL
GROUP BY pm.brand_id, b.name
HAVING COUNT(*) >= 10 
    AND ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) < $threshold
ORDER BY rate ASC
LIMIT 20;
EOF
    else
        echo "✅ All brands above threshold"
    fi
    
    echo ""
    echo -e "${YELLOW}Campaigns Below Threshold (Last 7 Days):${NC}"
    echo "----------------------------------------"
    
    local campaigns_count=$($MYSQL <<EOF
SELECT COUNT(*) FROM (
    SELECT 
        pm.campaign_id,
        ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate
    FROM proofread_medias pm
    WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        AND pm.deleted_at IS NULL
        AND pm.correct_answers IS NOT NULL
        AND pm.incorrect_answers IS NOT NULL
    GROUP BY pm.campaign_id
    HAVING COUNT(*) >= 10 AND rate < $threshold
) t;
EOF
)
    
    if [ "$campaigns_count" -gt 0 ]; then
        $MYSQL <<EOF
SELECT 
    pm.campaign_id,
    LEFT(c.title, 40) as campaign_title,
    COUNT(*) as evals,
    ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) as rate,
    CONCAT(
        ROUND($threshold - ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1), 1),
        'pp below'
    ) as gap
FROM proofread_medias pm
INNER JOIN campaigns c ON c.id = pm.campaign_id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    AND pm.deleted_at IS NULL
    AND pm.correct_answers IS NOT NULL
    AND pm.incorrect_answers IS NOT NULL
GROUP BY pm.campaign_id, c.title
HAVING COUNT(*) >= 10 
    AND ROUND(100.0 * SUM(pm.correct_answers) / (SUM(pm.correct_answers) + SUM(pm.incorrect_answers)), 1) < $threshold
ORDER BY rate ASC
LIMIT 20;
EOF
    else
        echo "✅ All campaigns above threshold"
    fi
}

# Trend: Daily agreement rate over time
cmd_trend() {
    local days="$1"
    
    echo -e "${BLUE}Daily Agreement Rate Trend (Last $days Days)${NC}"
    echo "==========================================="
    
    $MYSQL <<EOF
SELECT 
    DATE(created_at) as date,
    COUNT(*) as evals,
    SUM(correct_answers) as correct,
    SUM(incorrect_answers) as incorrect,
    ROUND(100.0 * SUM(correct_answers) / (SUM(correct_answers) + SUM(incorrect_answers)), 1) as rate
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
    AND deleted_at IS NULL
    AND correct_answers IS NOT NULL
    AND incorrect_answers IS NOT NULL
GROUP BY DATE(created_at)
ORDER BY date DESC;
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
        alerts)
            cmd_alerts "${1:-80}"
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
