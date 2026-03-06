#!/bin/bash
# Export data to Google Sheets
# Usage: export-to-sheets.sh --title "Sheet Title" [--file input.tsv] [--account email@example.com]

set -euo pipefail

# Defaults
TITLE=""
INPUT_FILE=""
ACCOUNT="${GOG_ACCOUNT:-caio.fonseca@brandlovers.ai}"
SHEET_NAME="Data"

# Source gog environment
if [[ -f /root/.openclaw/workspace/.env.gog ]]; then
    source /root/.openclaw/workspace/.env.gog
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --file)
            INPUT_FILE="$2"
            shift 2
            ;;
        --account)
            ACCOUNT="$2"
            shift 2
            ;;
        --sheet-name)
            SHEET_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate title
if [[ -z "$TITLE" ]]; then
    echo "Error: --title is required" >&2
    exit 1
fi

# Read input data
if [[ -n "$INPUT_FILE" ]]; then
    DATA=$(cat "$INPUT_FILE")
else
    DATA=$(cat)
fi

# Check if data is empty
if [[ -z "$DATA" ]]; then
    echo "Error: No data to export" >&2
    exit 1
fi

# Convert TSV/CSV to JSON 2D array
# Detect delimiter (tab or comma)
if echo "$DATA" | head -1 | grep -q $'\t'; then
    DELIMITER=$'\t'
else
    DELIMITER=','
fi

# Convert to JSON using Python (more reliable than jq for this)
VALUES_JSON=$(python3 -c "
import sys
import json
import csv
from io import StringIO

data = '''$DATA'''
reader = csv.reader(StringIO(data), delimiter='$DELIMITER')
rows = list(reader)
print(json.dumps(rows))
")

# Count rows and columns
ROW_COUNT=$(echo "$VALUES_JSON" | jq 'length')
COL_COUNT=$(echo "$VALUES_JSON" | jq '.[0] | length')

echo "📊 Data: $ROW_COUNT rows, $COL_COUNT columns" >&2

# Warn if too many rows
if [[ $ROW_COUNT -gt 1000 ]]; then
    echo "⚠️  Warning: Exporting $ROW_COUNT rows (this may take a moment)" >&2
fi

# Create new Google Sheet
echo "🔨 Creating Google Sheet: $TITLE" >&2
CREATE_RESULT=$(gog sheets create "$TITLE" \
    --account "$ACCOUNT" \
    --sheets "$SHEET_NAME" \
    --json \
    --no-input)

# Extract spreadsheet ID
SPREADSHEET_ID=$(echo "$CREATE_RESULT" | jq -r '.spreadsheetId')
SHEET_URL="https://docs.google.com/spreadsheets/d/${SPREADSHEET_ID}/edit"

if [[ -z "$SPREADSHEET_ID" || "$SPREADSHEET_ID" == "null" ]]; then
    echo "Error: Failed to create spreadsheet" >&2
    echo "$CREATE_RESULT" >&2
    exit 1
fi

echo "✅ Sheet created: $SPREADSHEET_ID" >&2

# Upload data
echo "📤 Uploading data..." >&2
RANGE="${SHEET_NAME}!A1"

gog sheets update "$SPREADSHEET_ID" "$RANGE" \
    --account "$ACCOUNT" \
    --values-json "$VALUES_JSON" \
    --input USER_ENTERED \
    --no-input > /dev/null 2>&1

echo "✅ Data uploaded" >&2

# Format headers (bold, freeze first row)
# Note: gog sheets format is limited, so we'll skip advanced formatting for now
# Future enhancement: use Google Sheets API directly for better formatting

# Make shareable (anyone with link can view)
# Note: gog doesn't have a share command, but sheets are private by default
# The owner (caio.fonseca@brandlovrs.com) can manually share or we can use Drive API
echo "🔗 Sheet URL: $SHEET_URL" >&2

# Return just the URL for easy parsing
echo "$SHEET_URL"
