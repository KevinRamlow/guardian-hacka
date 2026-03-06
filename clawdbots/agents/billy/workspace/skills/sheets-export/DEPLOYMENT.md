# Deployment Guide — sheets-export skill for Billy

## Pre-Deployment Checklist

- [x] Skill structure created
- [x] SKILL.md documentation written
- [x] Export script (export-to-sheets.sh) implemented
- [x] Test script created
- [x] README and SETUP docs written
- [ ] OAuth setup on Billy VM (requires browser/manual step)
- [ ] Test on Billy VM after OAuth
- [ ] Deploy to Billy VM

## Deployment Steps

### 1. Deploy the skill to Billy VM

```bash
# From main workspace (local)
rsync -av /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/sheets-export/ \
  root@89.167.64.183:/root/.openclaw/workspace/skills/sheets-export/
```

### 2. SSH into Billy VM and setup OAuth

```bash
# SSH to Billy
ssh root@89.167.64.183

# Source gog environment
source /root/.openclaw/workspace/.env.gog

# Check current auth
gog auth list

# Add sheets service (opens browser for OAuth)
gog auth add caio.fonseca@brandlovers.ai --services sheets
# OR if account already exists:
gog auth update caio.fonseca@brandlovers.ai --add-services sheets
```

**Note:** This requires browser access. If Billy VM is headless, you may need to:
- Run this from a machine with a browser (laptop/workstation)
- Use SSH tunnel for browser OAuth
- Or use service account auth instead

### 3. Test the skill on Billy VM

```bash
# On Billy VM
cd /root/.openclaw/workspace/skills/sheets-export

# Run test script
bash scripts/test-export.sh

# Or manual test
echo -e "Campaign\tStatus\nTest\tActive" | \
  bash scripts/export-to-sheets.sh --title "Billy Deploy Test"
```

Expected output:
```
📊 Data: 2 rows, 2 columns
🔨 Creating Google Sheet: Billy Deploy Test
✅ Sheet created: <spreadsheet_id>
📤 Uploading data...
✅ Data uploaded
🔗 Sheet URL: https://docs.google.com/spreadsheets/d/<id>/edit
```

### 4. Verify in Billy's skill list

```bash
# On Billy VM
ls -la /root/.openclaw/workspace/skills/

# Should show:
# sheets-export/
```

### 5. Test with Billy agent

Start a conversation with Billy and ask:
> "exporta os dados das campanhas ativas pra uma planilha"

Billy should:
1. Run the campaign query (via data-query skill)
2. Pipe results to sheets-export skill
3. Return Google Sheets URL with confirmation message

## Post-Deployment

- [ ] Verify Billy can create sheets successfully
- [ ] Test with real campaign data
- [ ] Monitor logs for errors
- [ ] Update Billy's capabilities documentation

## Rollback

If deployment fails:

```bash
# On Billy VM
rm -rf /root/.openclaw/workspace/skills/sheets-export/
```

## OAuth Alternative (Service Account)

If browser OAuth is problematic, consider using a service account:

1. Create service account in GCP
2. Download JSON key
3. Use `gog auth service-account set` instead

See: https://gogcli.sh/docs/auth/service-accounts

## Future Improvements

After initial deployment works:

- [ ] Add auto-share permissions (Drive API)
- [ ] Add formatting (bold headers, freeze rows)
- [ ] Add color coding for values
- [ ] Support for charts/visualizations
- [ ] Integration with other Billy skills
