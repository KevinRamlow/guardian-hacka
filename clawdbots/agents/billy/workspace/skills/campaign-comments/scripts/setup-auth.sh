#!/bin/bash
# One-time setup: Authorize Google Sheets API access
# Run this manually once, then Billy can use export-campaign-comments.sh automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Billy - Google Sheets Authorization Setup"
echo "=========================================="
echo ""
echo "This is a ONE-TIME setup to authorize Billy to create Google Sheets."
echo "After this, Billy can export campaign comments automatically."
echo ""

# Create a dummy spreadsheet to trigger OAuth
TEMP_JSON="/tmp/auth-test-$$.json"
echo '[["Test"], ["Data"]]' > "$TEMP_JSON"

python3 "$SCRIPT_DIR/sheets_uploader.py" "Billy Auth Test" "$TEMP_JSON"

rm -f "$TEMP_JSON"

echo ""
echo "✅ Authorization complete!"
echo "Billy can now create Google Sheets automatically."
