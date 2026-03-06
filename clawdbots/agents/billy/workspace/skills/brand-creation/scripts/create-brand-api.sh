#!/bin/bash
# create-brand-api.sh - Create brand via user-management-api
# 
# Usage:
#   ./create-brand-api.sh "Brand Name" "Description" [defaultFeePercentage] [autoApproveGroups]
#
# Environment variables required:
#   USER_MGMT_API_URL - Base URL for user-management-api (e.g., https://user-management-api.brandlovers.ai)
#   USER_MGMT_API_TOKEN - Bearer token with platform admin permissions
#
# Example:
#   export USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"
#   export USER_MGMT_API_TOKEN="your-platform-admin-token"
#   ./create-brand-api.sh "Nike" "Sportswear brand" 5 true

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
error() { echo -e "${RED}❌ ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ️  $1${NC}"; }

# Validate environment variables
if [[ -z "${USER_MGMT_API_URL:-}" ]]; then
    error "USER_MGMT_API_URL not set"
    echo "  Set it with: export USER_MGMT_API_URL='https://user-management-api.brandlovers.ai'" >&2
    exit 1
fi

if [[ -z "${USER_MGMT_API_TOKEN:-}" ]]; then
    error "USER_MGMT_API_TOKEN not set"
    echo "  Set it with: export USER_MGMT_API_TOKEN='your-platform-admin-token'" >&2
    exit 1
fi

# Parse arguments
BRAND_NAME="${1:-}"
DESCRIPTION="${2:-}"
DEFAULT_FEE="${3:-5}"  # Default to 5% if not provided
AUTO_APPROVE="${4:-false}"  # Default to false if not provided

# Validate required arguments
if [[ -z "$BRAND_NAME" ]]; then
    error "Brand name is required"
    echo "Usage: $0 \"Brand Name\" \"Description\" [defaultFeePercentage] [autoApproveGroups]" >&2
    exit 1
fi

# Validate brand name length
if [[ ${#BRAND_NAME} -lt 1 || ${#BRAND_NAME} -gt 100 ]]; then
    error "Brand name must be between 1 and 100 characters"
    exit 1
fi

# Validate description length if provided
if [[ -n "$DESCRIPTION" && ${#DESCRIPTION} -gt 2048 ]]; then
    error "Description must be max 2048 characters"
    exit 1
fi

# Validate fee percentage
if [[ ! "$DEFAULT_FEE" =~ ^[0-9]+$ ]] || [[ "$DEFAULT_FEE" -lt 0 || "$DEFAULT_FEE" -gt 100 ]]; then
    error "defaultFeePercentage must be an integer between 0 and 100"
    exit 1
fi

# Generate brand_slug (alphanumeric only, lowercase, replace spaces with hyphens)
generate_slug() {
    local name="$1"
    # Convert to lowercase, replace spaces with hyphens, remove non-alphanumeric chars
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

BRAND_SLUG=$(generate_slug "$BRAND_NAME")

# Validate slug length
if [[ ${#BRAND_SLUG} -lt 1 || ${#BRAND_SLUG} -gt 150 ]]; then
    error "Generated brand_slug is invalid (length: ${#BRAND_SLUG})"
    error "Slug: $BRAND_SLUG"
    exit 1
fi

info "Creating brand:"
echo "  Name: $BRAND_NAME"
echo "  Slug: $BRAND_SLUG"
echo "  Description: ${DESCRIPTION:-<none>}"
echo "  Default Fee: ${DEFAULT_FEE}%"
echo "  Auto-approve Groups: $AUTO_APPROVE"
echo ""

# Build JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg name "$BRAND_NAME" \
    --arg slug "$BRAND_SLUG" \
    --arg desc "$DESCRIPTION" \
    --argjson fee "$DEFAULT_FEE" \
    --argjson auto "$AUTO_APPROVE" \
    '{
        name: $name,
        brand_slug: $slug,
        defaultFeePercentage: $fee,
        autoApproveGroups: $auto
    } + (if $desc != "" then {description: $desc} else {} end)'
)

# Make API request
info "Sending request to $USER_MGMT_API_URL/v1/brands..."

HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/brand-response.json \
    -X POST \
    "${USER_MGMT_API_URL}/v1/brands" \
    -H "Authorization: Bearer ${USER_MGMT_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

# Parse response
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    success "Brand created successfully!"
    echo ""
    
    # Pretty print response
    cat /tmp/brand-response.json | jq '.'
    
    # Extract key fields
    BRAND_ID=$(cat /tmp/brand-response.json | jq -r '.id // empty')
    
    if [[ -n "$BRAND_ID" ]]; then
        echo ""
        success "Brand ID: $BRAND_ID"
        success "Brand Slug: $BRAND_SLUG"
    fi
    
    exit 0
else
    error "Failed to create brand (HTTP $HTTP_CODE)"
    echo ""
    echo "Response:"
    cat /tmp/brand-response.json | jq '.' 2>/dev/null || cat /tmp/brand-response.json
    exit 1
fi
