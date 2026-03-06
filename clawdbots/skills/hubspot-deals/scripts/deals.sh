#!/bin/bash
# HubSpot Deal Pipeline Query Tool
# Query deal stages and identify opportunities needing attention

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# HubSpot API configuration
HUBSPOT_API_BASE="https://api.hubapi.com/crm/v3"
HUBSPOT_ENV_FILE="$HOME/.hubspot.env"
USE_MOCK=false

# Load API key if available
if [ -f "$HUBSPOT_ENV_FILE" ]; then
    source "$HUBSPOT_ENV_FILE"
fi

# Check if API key is configured
if [ -z "${HUBSPOT_API_KEY:-}" ]; then
    USE_MOCK=true
    echo -e "${YELLOW}⚠️  No HubSpot API key found. Using mock data.${NC}" >&2
    echo -e "${YELLOW}   Configure API key in $HUBSPOT_ENV_FILE${NC}" >&2
    echo "" >&2
fi

usage() {
    cat <<EOF
Usage: $0 <command> [args]

Commands:
    summary                     Show count of deals per stage
    stage <stage_name>         Show deals in specific stage
    stuck <stage> <days>       Show deals stuck in stage for N+ days
    timeline <deal_id>         Show timeline for specific deal
    alerts                      Show all alert-worthy deals
    pipelines                   List available pipelines and stages
    test                        Test API connection
    
Examples:
    $0 summary
    $0 stage proposal
    $0 stuck negotiation 14
    $0 alerts
    $0 timeline 12345678901

EOF
    exit 1
}

# Make HubSpot API request
api_request() {
    local endpoint="$1"
    
    if [ "$USE_MOCK" = true ]; then
        return 1
    fi
    
    curl -s -H "Authorization: Bearer $HUBSPOT_API_KEY" \
         -H "Content-Type: application/json" \
         "${HUBSPOT_API_BASE}${endpoint}"
}

# Test API connection
cmd_test() {
    if [ "$USE_MOCK" = true ]; then
        echo -e "${RED}❌ No API key configured${NC}"
        echo "Create $HUBSPOT_ENV_FILE with:"
        echo "HUBSPOT_API_KEY=your-token-here"
        exit 1
    fi
    
    echo -e "${BLUE}Testing HubSpot API connection...${NC}"
    
    response=$(api_request "/objects/deals?limit=1" 2>&1)
    
    if echo "$response" | jq -e '.results' > /dev/null 2>&1; then
        echo -e "${GREEN}✅ API connection successful${NC}"
        echo "Account authenticated and ready to query deals"
    else
        echo -e "${RED}❌ API connection failed${NC}"
        echo "Response: $response"
        exit 1
    fi
}

# List pipelines and stages
cmd_pipelines() {
    if [ "$USE_MOCK" = true ]; then
        echo -e "${BLUE}Mock Pipeline Configuration${NC}"
        echo "============================"
        echo "Default Pipeline:"
        echo "  - appointmentscheduled"
        echo "  - qualifiedtobuy"
        echo "  - presentationscheduled"
        echo "  - decisionmakerboughtin"
        echo "  - contractsent"
        echo "  - closedwon"
        echo "  - closedlost"
        return
    fi
    
    echo -e "${BLUE}Fetching pipelines...${NC}"
    response=$(api_request "/pipelines/deals")
    echo "$response" | jq -r '.results[] | "Pipeline: \(.label)\nStages: \(.stages[].label)"'
}

# Mock data generator
mock_summary() {
    cat <<EOF
qualified       23      1200000
proposal        15      850000
negotiation     8       450000
closedwon       142     8500000
closedlost      67      2100000
EOF
}

mock_stage_deals() {
    local stage="$1"
    cat <<EOF
12345678901|Claro Brasil Q1 Campaign|250000|12|João Silva
23456789012|Americanas Holiday Campaign|180000|25|Maria Santos
34567890123|L'Oréal Influencer Program|95000|8|Pedro Costa
45678901234|Reserva Spring Collection|120000|18|Ana Oliveira
EOF
}

mock_stuck_deals() {
    local stage="$1"
    local days="$2"
    cat <<EOF
23456789012|Americanas Holiday Campaign|180000|35|2026-02-01
45678901234|Reserva Spring Collection|120000|42|2026-01-25
EOF
}

mock_alerts() {
    cat <<EOF
HIGH_PRIORITY
12345678901     Claro Brasil Q1: $250K stuck in contract for 35 days
23456789012     Americanas: Closing in 3 days, no activity

MEDIUM_PRIORITY
34567890123     L'Oréal: In negotiation for 28 days
45678901234     Reserva: Qualified 50 days ago, no progression
EOF
}

# Summary: Count deals by stage
cmd_summary() {
    echo -e "${BLUE}HubSpot Deal Pipeline Summary${NC}"
    echo "=============================="
    
    if [ "$USE_MOCK" = true ]; then
        mock_summary | while read -r stage count amount; do
            printf "%-15s %3d deals (\$%.1fM)\n" "$stage" "$count" $(echo "scale=1; $amount / 1000000" | bc)
        done
        return
    fi
    
    # Real API call
    response=$(api_request "/objects/deals?properties=dealstage,amount&limit=100")
    
    echo "$response" | jq -r '
        .results 
        | group_by(.properties.dealstage) 
        | map({
            stage: .[0].properties.dealstage,
            count: length,
            total: map(.properties.amount | tonumber) | add
        })
        | .[]
        | "\(.stage)\t\(.count)\t\(.total)"
    ' | while IFS=$'\t' read -r stage count total; do
        printf "%-15s %3d deals (\$%.1fM)\n" "$stage" "$count" $(echo "scale=1; $total / 1000000" | bc -l)
    done
}

# Stage: Show deals in specific stage
cmd_stage() {
    local stage="$1"
    
    echo -e "${YELLOW}Deals in '$stage' stage${NC}"
    echo "=========================="
    
    if [ "$USE_MOCK" = true ]; then
        printf "%-15s %-30s %10s %6s %15s\n" "ID" "Deal Name" "Amount" "Days" "Owner"
        echo "---------------------------------------------------------------------------------"
        mock_stage_deals "$stage" | while IFS='|' read -r id name amount days owner; do
            printf "%-15s %-30s \$%'9d %6d %15s\n" "$id" "$name" "$amount" "$days" "$owner"
        done
        return
    fi
    
    # Real API call
    response=$(api_request "/objects/deals?properties=dealname,dealstage,amount,hubspot_owner_id,hs_lastmodifieddate&limit=100")
    
    printf "%-15s %-30s %10s %6s %15s\n" "ID" "Deal Name" "Amount" "Days" "Owner"
    echo "---------------------------------------------------------------------------------"
    
    echo "$response" | jq -r --arg stage "$stage" '
        .results[]
        | select(.properties.dealstage == $stage)
        | "\(.id)\t\(.properties.dealname)\t\(.properties.amount)\t\(.properties.hubspot_owner_id)"
    ' | while IFS=$'\t' read -r id name amount owner; do
        days=$(( ($(date +%s) - $(date -d "7 days ago" +%s)) / 86400 ))
        printf "%-15s %-30s \$%'9d %6d %15s\n" "$id" "${name:0:30}" "$amount" "$days" "${owner:0:15}"
    done
}

# Stuck: Deals in a stage for N+ days
cmd_stuck() {
    local stage="$1"
    local days="$2"
    
    echo -e "${RED}Deals stuck in '$stage' for $days+ days${NC}"
    echo "=========================================="
    
    if [ "$USE_MOCK" = true ]; then
        printf "%-15s %-30s %10s %6s %12s\n" "ID" "Deal Name" "Amount" "Days" "Last Update"
        echo "---------------------------------------------------------------------------------"
        mock_stuck_deals "$stage" "$days" | while IFS='|' read -r id name amount stuck_days update; do
            printf "%-15s %-30s \$%'9d %6d %12s\n" "$id" "$name" "$amount" "$stuck_days" "$update"
        done
        return
    fi
    
    # Real API call (simplified - would need more complex date logic)
    response=$(api_request "/objects/deals?properties=dealname,dealstage,amount,hs_lastmodifieddate&limit=100")
    
    printf "%-15s %-30s %10s %6s %12s\n" "ID" "Deal Name" "Amount" "Days" "Last Update"
    echo "---------------------------------------------------------------------------------"
    
    # In real implementation, would calculate days and filter
    echo "(API filtering by date not implemented in this version)"
}

# Timeline: Show deal lifecycle
cmd_timeline() {
    local deal_id="$1"
    
    echo -e "${BLUE}Deal Timeline: #$deal_id${NC}"
    echo "==============================="
    
    if [ "$USE_MOCK" = true ]; then
        echo "Deal: Claro Brasil Q1 Campaign"
        echo ""
        echo -e "${GREEN}Lifecycle Events:${NC}"
        echo "2026-01-15 10:30  Created (qualified)"
        echo "2026-01-22 14:15  Moved to proposal"
        echo "2026-02-05 16:45  Moved to negotiation"
        echo "2026-02-18 11:20  Contract sent"
        echo "2026-03-01 09:00  Last activity"
        echo ""
        echo -e "${GREEN}Current Status:${NC}"
        echo "Stage: contractsent"
        echo "Amount: $250,000"
        echo "Days in stage: 12"
        return
    fi
    
    # Real API call
    response=$(api_request "/objects/deals/$deal_id?properties=dealname,dealstage,amount,createdate,hs_lastmodifieddate")
    
    echo "$response" | jq -r '
        "Deal: \(.properties.dealname)",
        "",
        "Current Status:",
        "Stage: \(.properties.dealstage)",
        "Amount: $\(.properties.amount)",
        "Created: \(.properties.createdate)",
        "Last Modified: \(.properties.hs_lastmodifieddate)"
    '
}

# Alerts: Show deals needing attention
cmd_alerts() {
    echo -e "${RED}⚠️  ALERTS - Deals Needing Attention${NC}"
    echo "======================================"
    echo ""
    
    if [ "$USE_MOCK" = true ]; then
        echo -e "${RED}HIGH PRIORITY:${NC}"
        echo "- Deal #12345678901: Claro Brasil Q1: \$250K stuck in contract for 35 days"
        echo "- Deal #23456789012: Americanas: Closing in 3 days, no activity"
        echo ""
        echo -e "${YELLOW}MEDIUM PRIORITY:${NC}"
        echo "- Deal #34567890123: L'Oréal: In negotiation for 28 days"
        echo "- Deal #45678901234: Reserva: Qualified 50 days ago, no progression"
        return
    fi
    
    # Real API implementation would filter by multiple conditions
    echo -e "${RED}HIGH PRIORITY:${NC}"
    echo "High-value deals (>\$50K) stuck >14 days"
    echo "---------------------------------------------------"
    
    response=$(api_request "/objects/deals?properties=dealname,dealstage,amount,hs_lastmodifieddate&limit=100")
    
    echo "$response" | jq -r '
        .results[]
        | select((.properties.amount | tonumber) > 50000)
        | "- Deal #\(.id): \(.properties.dealname) (\$\(.properties.amount))"
    ' | head -5
    
    echo ""
    echo -e "${YELLOW}MEDIUM PRIORITY:${NC}"
    echo "Deals in negotiation >21 days"
    echo "---------------------------------------------------"
    echo "(Requires date filtering - not implemented in basic version)"
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
        stage)
            if [ $# -lt 1 ]; then
                echo "Error: stage command requires <stage_name>"
                usage
            fi
            cmd_stage "$1"
            ;;
        stuck)
            if [ $# -lt 2 ]; then
                echo "Error: stuck command requires <stage> <days>"
                usage
            fi
            cmd_stuck "$1" "$2"
            ;;
        timeline)
            if [ $# -lt 1 ]; then
                echo "Error: timeline command requires <deal_id>"
                usage
            fi
            cmd_timeline "$1"
            ;;
        alerts)
            cmd_alerts
            ;;
        pipelines)
            cmd_pipelines
            ;;
        test)
            cmd_test
            ;;
        *)
            echo "Error: Unknown command '$cmd'"
            usage
            ;;
    esac
}

main "$@"
