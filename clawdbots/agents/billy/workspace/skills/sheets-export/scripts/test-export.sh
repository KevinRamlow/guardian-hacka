#!/bin/bash
# Test the Google Sheets export skill
# Run this after OAuth setup to verify everything works

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/export-to-sheets.sh"

# Source gog environment
if [[ -f /root/.openclaw/workspace/.env.gog ]]; then
    source /root/.openclaw/workspace/.env.gog
fi

echo "🧪 Testing Google Sheets Export Skill"
echo ""

# Test 1: Simple TSV export
echo "Test 1: Simple TSV export"
TEST_DATA="Campaign\tStatus\tTotal\tApproval Rate
Campaign A\tActive\t1234\t87.5%
Campaign B\tPaused\t567\t91.2%
Campaign C\tActive\t890\t78.3%"

echo "Creating test sheet..."
SHEET_URL=$(echo -e "$TEST_DATA" | bash "$EXPORT_SCRIPT" --title "Billy Test - $(date +%Y-%m-%d-%H%M%S)")

if [[ -n "$SHEET_URL" && "$SHEET_URL" == https://docs.google.com/spreadsheets/* ]]; then
    echo "✅ Test 1 passed"
    echo "   URL: $SHEET_URL"
else
    echo "❌ Test 1 failed"
    echo "   Expected Google Sheets URL, got: $SHEET_URL"
    exit 1
fi

echo ""

# Test 2: MySQL export (if MySQL is available)
if command -v mysql &> /dev/null; then
    echo "Test 2: MySQL export"
    
    QUERY="SELECT 'Campaign 1' AS name, 'Active' AS status, 100 AS total
           UNION ALL
           SELECT 'Campaign 2', 'Paused', 200
           UNION ALL
           SELECT 'Campaign 3', 'Active', 300"
    
    echo "Running MySQL query and exporting..."
    SHEET_URL=$(mysql -N -e "$QUERY" | bash "$EXPORT_SCRIPT" --title "Billy MySQL Test - $(date +%Y-%m-%d-%H%M%S)")
    
    if [[ -n "$SHEET_URL" && "$SHEET_URL" == https://docs.google.com/spreadsheets/* ]]; then
        echo "✅ Test 2 passed"
        echo "   URL: $SHEET_URL"
    else
        echo "❌ Test 2 failed"
        echo "   Expected Google Sheets URL, got: $SHEET_URL"
        exit 1
    fi
else
    echo "⏭️  Test 2 skipped (MySQL not available)"
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "🎉 Google Sheets export skill is ready to use"
