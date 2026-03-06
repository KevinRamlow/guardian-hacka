# Campaign Comments Export — Billy Skill

**Status:** ✅ Built and ready for setup  
**Linear:** CAI-74  
**Date:** 2026-03-06

## What It Does

Automatically exports all moderation comments (refusal reasons + contest feedback) for any campaign to a shareable Google Sheet.

**Replaces:** 92 manual export requests over 2 months

## Setup Required (ONE-TIME)

Billy needs Google Sheets API authorization. **Run this once as Caio:**

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-comments
bash scripts/setup-auth.sh
```

This will:
1. Display a Google OAuth URL
2. Ask you to approve access (Google Sheets + Drive)
3. Save credentials at `.google_sheets_token.json`
4. Create a test sheet to verify it works

**After setup:** Billy can export sheets automatically without human approval.

## Usage

Billy can now respond to:
- "exporta os comentários da campanha 500239"
- "me manda os feedbacks da campanha VITAMIN C12"
- "preciso dos comentários de recusa da campanha X"

### Manual Command

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-comments
bash scripts/export-campaign-comments.sh <campaign_id_or_name>
```

Examples:
```bash
bash scripts/export-campaign-comments.sh 500239
bash scripts/export-campaign-comments.sh "VITAMIN C12"
```

**Output:** Google Sheets shareable URL (anyone with link can view)

## Data Exported

- Campaign name & brand
- Action ID, Media Content ID, Media URL
- Approval status
- Refusal reason (moderator comments)
- Refused by (user ID), refused at (timestamp)
- Contest reason (creator dispute)
- Contest decision & status
- Created/contested timestamps

## Files Created

- `SKILL.md` — Skill documentation
- `scripts/export-campaign-comments.sh` — Main export script (MySQL → Google Sheets)
- `scripts/export-campaign-comments-csv.sh` — Fallback CSV-only export
- `scripts/sheets_uploader.py` — Python Google Sheets API uploader
- `scripts/setup-auth.sh` — One-time OAuth setup
- `.google_sheets_token.json` — Saved credentials (created during setup)

## Technical Details

- **Data source:** MySQL (`db-maestro-prod`)
- **Tables:** campaigns, brands, proofread_medias, actions, media_content, proofread_media_contest
- **Google API:** Sheets v4 + Drive v3 (OAuth 2.0)
- **Permissions:** Sheets created with "anyone with link can view"
- **Sheet title format:** `Campaign Comments - {campaign_name} - {date}`

## Testing

After setup, test with:
```bash
bash scripts/export-campaign-comments.sh 500239
```

Should output a Google Sheets URL.

## Integration with Billy

Billy's SOUL.md and skills loader will automatically detect this skill based on:
- Location: `skills/campaign-comments/`
- Trigger phrases in `SKILL.md`
- Billy's skill scanning on startup

No code changes needed to Billy's core.

## Fallback (No Auth)

If Google Sheets auth fails or isn't set up:
```bash
bash scripts/export-campaign-comments-csv.sh 500239
```

Returns local CSV file path (manual upload to Google Sheets needed).
