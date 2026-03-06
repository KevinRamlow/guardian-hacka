#!/bin/bash
# Weekly Campaign Report Generator
# Aggregate campaign metrics over past N days (default 7)

set -euo pipefail

# Default parameters
DAYS=7
SLACK_FORMAT=false
SECTION="all"

# Colors for console output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# MySQL connection (uses ~/.my.cnf)
MYSQL="mysql -N -B"

usage() {
    cat <<EOF
Usage: $0 [days] [--slack] [--section <name>]

Options:
    days              Number of days to report (default: 7)
    --slack           Output Slack-friendly format (no colors)
    --section <name>  Show only specific section: new|completions|top|issues|all

Examples:
    $0                           # Last 7 days, console format
    $0 14                        # Last 14 days
    $0 --slack                   # Slack format
    $0 30 --slack                # Last 30 days, Slack format
    $0 --section issues          # Issues only
    $0 7 --section top --slack   # Top performers, Slack format

EOF
    exit 1
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --slack)
            SLACK_FORMAT=true
            shift
            ;;
        --section)
            SECTION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        [0-9]*)
            DAYS="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            ;;
    esac
done

# Calculate date range
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d "$DAYS days ago" +%Y-%m-%d)

# Helper: Print header
print_header() {
    local title="$1"
    if [ "$SLACK_FORMAT" = true ]; then
        echo ""
        echo "*${title}*"
    else
        echo -e "\n${BLUE}${BOLD}${title}${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# Helper: Print section title
print_section() {
    local emoji="$1"
    local title="$2"
    if [ "$SLACK_FORMAT" = true ]; then
        echo ""
        echo "*${emoji} ${title}*"
    else
        echo -e "\n${CYAN}${BOLD}${emoji} ${title}${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# Helper: Print bullet point
print_bullet() {
    local text="$1"
    if [ "$SLACK_FORMAT" = true ]; then
        echo "• ${text}"
    else
        echo -e "  ${GREEN}•${NC} ${text}"
    fi
}

# Helper: Print item with number
print_item() {
    local num="$1"
    local text="$2"
    if [ "$SLACK_FORMAT" = true ]; then
        echo "${num}. ${text}"
    else
        echo -e "  ${YELLOW}${num}.${NC} ${text}"
    fi
}

# Helper: Print alert item
print_alert() {
    local text="$1"
    if [ "$SLACK_FORMAT" = true ]; then
        echo "⚠️ ${text}"
    else
        echo -e "  ${RED}⚠️${NC}  ${text}"
    fi
}

# Main report header
print_report_header() {
    if [ "$SLACK_FORMAT" = true ]; then
        echo "*WEEKLY CAMPAIGN REPORT ($DAYS days)*"
        echo "_Period: $START_DATE to ${END_DATE}_"
    else
        echo -e "${BOLD}"
        echo "╔════════════════════════════════════════╗"
        echo "║   WEEKLY CAMPAIGN REPORT ($DAYS days)    "
        echo "║   Period: $START_DATE to $END_DATE    "
        echo "╚════════════════════════════════════════╝"
        echo -e "${NC}"
    fi
}

# Summary section
section_summary() {
    print_section "📊" "SUMMARY"
    
    # Get counts
    local new_count=$($MYSQL <<EOF
SELECT COUNT(*) 
FROM campaigns c
WHERE c.deleted_at IS NULL
    AND DATE(c.created_at) >= '$START_DATE'
    AND DATE(c.created_at) <= '$END_DATE';
EOF
)
    
    local completed_count=$($MYSQL <<EOF
SELECT COUNT(*)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'finished'
    AND DATE(c.updated_at) >= '$START_DATE'
    AND DATE(c.updated_at) <= '$END_DATE';
EOF
)
    
    local total_submissions=$($MYSQL <<EOF
SELECT COUNT(DISTINCT mc.id)
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads ad ON ad.moment_id = m.id
INNER JOIN actions a ON a.ad_id = ad.id
INNER JOIN media_content mc ON mc.action_id = a.id
WHERE c.deleted_at IS NULL
    AND DATE(mc.created_at) >= '$START_DATE'
    AND DATE(mc.created_at) <= '$END_DATE';
EOF
)
    
    local avg_approval=$($MYSQL <<EOF
SELECT COALESCE(
    ROUND(
        100.0 * SUM(CASE WHEN a.approved_at IS NOT NULL THEN 1 ELSE 0 END) / 
        NULLIF(SUM(CASE WHEN a.approved_at IS NOT NULL OR mc.refused_at IS NOT NULL THEN 1 ELSE 0 END), 0),
        1
    ),
    0
) as avg_rate
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads ad ON ad.moment_id = m.id
INNER JOIN actions a ON a.ad_id = ad.id
INNER JOIN media_content mc ON mc.action_id = a.id
WHERE c.deleted_at IS NULL
    AND DATE(mc.created_at) >= '$START_DATE'
    AND DATE(mc.created_at) <= '$END_DATE';
EOF
)
    
    print_bullet "New campaigns: ${new_count}"
    print_bullet "Completed campaigns: ${completed_count}"
    print_bullet "Total submissions: ${total_submissions}"
    print_bullet "Avg approval rate: ${avg_approval}%"
}

# New campaigns section
section_new() {
    print_section "🆕" "NEW CAMPAIGNS"
    
    local count=$($MYSQL <<EOF
SELECT COUNT(*) 
FROM campaigns c
WHERE c.deleted_at IS NULL
    AND DATE(c.created_at) >= '$START_DATE'
    AND DATE(c.created_at) <= '$END_DATE';
EOF
)
    
    if [ "$count" -eq 0 ]; then
        print_bullet "No new campaigns created in this period"
        return
    fi
    
    if [ "$SLACK_FORMAT" = true ]; then
        echo "($count campaigns)"
    else
        echo -e "  ${BOLD}Total: $count${NC}"
    fi
    
    while IFS=$'\t' read -r id title state created; do
        if [ "$SLACK_FORMAT" = true ]; then
            echo "• #${id} ${title} (${state}) - ${created}"
        else
            echo -e "  ${YELLOW}#${id}${NC} | ${title} | ${GREEN}${state}${NC} | ${created}"
        fi
    done < <($MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 40) as title,
    cs.name as state,
    DATE(c.created_at) as created
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND DATE(c.created_at) >= '$START_DATE'
    AND DATE(c.created_at) <= '$END_DATE'
ORDER BY c.created_at DESC
LIMIT 20;
EOF
)
}

# Completions section
section_completions() {
    print_section "✅" "COMPLETIONS"
    
    local count=$($MYSQL <<EOF
SELECT COUNT(*)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'finished'
    AND DATE(c.updated_at) >= '$START_DATE'
    AND DATE(c.updated_at) <= '$END_DATE';
EOF
)
    
    if [ "$count" -eq 0 ]; then
        print_bullet "No campaigns completed in this period"
        return
    fi
    
    if [ "$SLACK_FORMAT" = true ]; then
        echo "($count campaigns)"
    else
        echo -e "  ${BOLD}Total: $count${NC}"
    fi
    
    while IFS=$'\t' read -r id title subs approved rate days; do
        if [ "$SLACK_FORMAT" = true ]; then
            echo "• #${id} ${title} - ${subs} submissions, ${rate}% approved, ${days} days"
        else
            echo -e "  ${YELLOW}#${id}${NC} | ${title} | ${subs} subs | ${GREEN}${rate}%${NC} | ${days}d"
        fi
    done < <($MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 35) as title,
    COUNT(DISTINCT mc.id) as submissions,
    ROUND(100.0 * SUM(CASE WHEN a.approved_at IS NOT NULL THEN 1 ELSE 0 END) / 
        NULLIF(COUNT(DISTINCT mc.id), 0), 1) as approval_rate,
    DATEDIFF(c.updated_at, c.created_at) as duration_days
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads ad ON ad.moment_id = m.id
INNER JOIN actions a ON a.ad_id = ad.id
LEFT JOIN media_content mc ON mc.action_id = a.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'finished'
    AND DATE(c.updated_at) >= '$START_DATE'
    AND DATE(c.updated_at) <= '$END_DATE'
GROUP BY c.id, c.title, c.created_at, c.updated_at
ORDER BY c.updated_at DESC
LIMIT 20;
EOF
)
}

# Top performers section
section_top() {
    print_section "🏆" "TOP PERFORMERS (by submissions)"
    
    local count=0
    while IFS=$'\t' read -r id title subs approved rate; do
        count=$((count + 1))
        if [ "$SLACK_FORMAT" = true ]; then
            echo "${count}. #${id} ${title} - ${subs} submissions (${rate}% approved)"
        else
            echo -e "  ${YELLOW}${count}.${NC} ${BOLD}#${id}${NC} | ${title} | ${subs} subs | ${GREEN}${rate}%${NC}"
        fi
    done < <($MYSQL <<EOF
SELECT 
    c.id,
    LEFT(c.title, 35) as title,
    COUNT(DISTINCT mc.id) as submissions,
    COUNT(DISTINCT CASE WHEN a.approved_at IS NOT NULL THEN mc.id END) as approved,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.approved_at IS NOT NULL THEN mc.id END) / 
        NULLIF(COUNT(DISTINCT mc.id), 0), 1) as approval_rate
FROM campaigns c
INNER JOIN moments m ON m.campaign_id = c.id
INNER JOIN ads ad ON ad.moment_id = m.id
INNER JOIN actions a ON a.ad_id = ad.id
INNER JOIN media_content mc ON mc.action_id = a.id
WHERE c.deleted_at IS NULL
    AND DATE(mc.created_at) >= '$START_DATE'
    AND DATE(mc.created_at) <= '$END_DATE'
GROUP BY c.id, c.title
HAVING submissions > 0
ORDER BY submissions DESC, approval_rate DESC
LIMIT 10;
EOF
)
}

# Issues section
section_issues() {
    print_section "⚠️" "ISSUES & ALERTS"
    
    # Published with 0 submissions >7 days
    local stuck_published=$($MYSQL <<EOF
SELECT COUNT(*)
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
    AND COALESCE(submission_count, 0) = 0;
EOF
)
    
    # Stuck drafts >30 days
    local stuck_drafts=$($MYSQL <<EOF
SELECT COUNT(*)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'draft'
    AND DATEDIFF(NOW(), c.created_at) >= 30;
EOF
)
    
    # Low approval rate (<50%)
    local low_approval=$($MYSQL <<EOF
SELECT COUNT(*)
FROM (
    SELECT 
        c.id,
        COUNT(DISTINCT mc.id) as submissions,
        ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.approved_at IS NOT NULL THEN mc.id END) / 
            NULLIF(COUNT(DISTINCT mc.id), 0), 1) as approval_rate
    FROM campaigns c
    INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
    INNER JOIN moments m ON m.campaign_id = c.id
    INNER JOIN ads ad ON ad.moment_id = m.id
    INNER JOIN actions a ON a.ad_id = ad.id
    INNER JOIN media_content mc ON mc.action_id = a.id
    WHERE c.deleted_at IS NULL
        AND cs.name = 'published'
        AND DATE(mc.created_at) >= '$START_DATE'
        AND DATE(mc.created_at) <= '$END_DATE'
    GROUP BY c.id
    HAVING submissions >= 5 AND approval_rate < 50
) sub;
EOF
)
    
    # Recently paused
    local paused=$($MYSQL <<EOF
SELECT COUNT(*)
FROM campaigns c
INNER JOIN campaign_states cs ON c.campaign_state_id = cs.id
WHERE c.deleted_at IS NULL
    AND cs.name = 'paused'
    AND DATE(c.updated_at) >= '$START_DATE'
    AND DATE(c.updated_at) <= '$END_DATE';
EOF
)
    
    local has_issues=false
    
    if [ "$stuck_published" -gt 0 ]; then
        print_alert "${stuck_published} published campaigns with 0 submissions (>7 days)"
        has_issues=true
    fi
    
    if [ "$stuck_drafts" -gt 0 ]; then
        print_alert "${stuck_drafts} draft campaigns stuck >30 days"
        has_issues=true
    fi
    
    if [ "$low_approval" -gt 0 ]; then
        print_alert "${low_approval} campaigns with approval rate <50%"
        has_issues=true
    fi
    
    if [ "$paused" -gt 0 ]; then
        print_alert "${paused} campaigns paused this period"
        has_issues=true
    fi
    
    if [ "$has_issues" = false ]; then
        print_bullet "No major issues detected! 🎉"
    fi
}

# Main execution
main() {
    case "$SECTION" in
        all)
            print_report_header
            section_summary
            section_new
            section_completions
            section_top
            section_issues
            ;;
        summary)
            section_summary
            ;;
        new)
            section_new
            ;;
        completions)
            section_completions
            ;;
        top)
            section_top
            ;;
        issues)
            section_issues
            ;;
        *)
            echo "Error: Unknown section '$SECTION'"
            echo "Valid sections: all, summary, new, completions, top, issues"
            exit 1
            ;;
    esac
    
    # Final newline
    echo ""
}

main
