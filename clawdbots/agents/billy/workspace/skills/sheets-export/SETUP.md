# Google Sheets Export - Setup Instructions

## Prerequisites

1. **gog CLI installed** — Already available on Billy VM
2. **Google OAuth credentials** — Already configured
3. **Sheets API access** — Needs one-time OAuth flow

## Setup on Billy VM (89.167.64.183)

Run this once after deploying the skill:

```bash
# SSH into Billy VM
ssh root@89.167.64.183

# Source gog environment
source /root/.openclaw/workspace/.env.gog

# Add sheets service (opens browser for OAuth)
gog auth add caio.fonseca@brandlovers.ai --services sheets

# Or update existing auth
gog auth update caio.fonseca@brandlovers.ai --add-services sheets
```

The OAuth flow will:
1. Open a browser window
2. Ask you to sign in with caio.fonseca@brandlovers.ai
3. Grant sheets access
4. Save the token

After this one-time setup, the skill will work automatically.

## Testing

After setup, test with:

```bash
echo -e "Campaign\tStatus\tTotal\nTest 1\tActive\t100" | \
  bash /root/.openclaw/workspace/skills/sheets-export/scripts/export-to-sheets.sh \
  --title "Billy Test Sheet" \
  --account caio.fonseca@brandlovers.ai
```

Expected output:
```
📊 Data: 2 rows, 3 columns
🔨 Creating Google Sheet: Billy Test Sheet
✅ Sheet created: <spreadsheet_id>
📤 Uploading data...
✅ Data uploaded
🔗 Sheet URL: https://docs.google.com/spreadsheets/d/<id>/edit
https://docs.google.com/spreadsheets/d/<id>/edit
```

## Permissions Note

Sheets created with this skill will be:
- Owned by: caio.fonseca@brandlovers.ai
- Private by default (only owner can access)
- Shareable via "Share" button in Google Sheets UI

To make sheets publicly shareable by default, we would need to:
1. Add Drive API permissions to gog auth
2. Use `gog drive` commands to set permissions
3. Or use Google Apps Script to auto-share on creation

For MVP, manual sharing via UI is acceptable.

## Deployment

After testing locally:

```bash
# Deploy to Billy VM
rsync -av /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/ \
  root@89.167.64.183:/root/.openclaw/workspace/skills/
```

## Troubleshooting

**Error: "No auth for sheets"**
- Run the OAuth setup above

**Error: "Failed to create spreadsheet"**
- Check gog auth list shows caio.fonseca@brandlovers.ai with sheets service
- Verify GOG_KEYRING_PASSWORD is set in .env.gog
- Try re-authenticating: `gog auth update caio.fonseca@brandlovers.ai --add-services sheets`

**Sheet created but can't access**
- The sheet is private to caio.fonseca@brandlovers.ai by default
- Open the URL while signed in to that account
- Click "Share" to make it viewable by others
