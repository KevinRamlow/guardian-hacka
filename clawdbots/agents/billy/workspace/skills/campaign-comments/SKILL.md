# Campaign Comments Skill

Export all moderation comments (refusal reasons & contest feedback) for a specific campaign to Google Sheets.

## When to Use
- "exporta os comentários da campanha X"
- "me manda os feedbacks de moderação da campanha Y"
- "preciso dos comentários de recusa da campanha Z"
- "quero ver todos os retornos da campanha W"
- Any request for campaign feedback, moderation comments, or refusal reasons export

## First-Time Setup (ONE-TIME)

Before Billy can auto-generate sheets, run this once:

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-comments
bash scripts/setup-auth.sh
```

This will:
1. Show a Google OAuth URL
2. Ask Caio to approve access to Google Sheets & Drive
3. Save credentials for future automated use

After setup, Billy can export sheets automatically without manual approval.

## What It Does

1. Queries MySQL for all moderation comments related to a campaign:
   - **Refusal reasons** from `media_content` (moderator feedback on rejected content)
   - **Contest reasons** from `proofread_media_contest` (creator disputes)
2. Exports results to a new Google Sheet
3. Shares the link in Slack

## Data Structure

The export includes:
- **Campaign info**: campaign name, brand
- **Content info**: action_id, media_content_id, media URL
- **Moderation data**: approval status, refusal reason, refused_by, refused_at
- **Contest data**: contest reason, decision reason, contest status
- **Metadata**: created dates, timestamps

## Query Logic

```sql
SELECT
    c.title AS campanha,
    b.name AS marca,
    a.id AS action_id,
    mc.id AS media_content_id,
    mc.media_url,
    pm.is_approved,
    mc.refusal_reason AS comentario_recusa,
    mc.refused_by,
    mc.refused_at,
    pmc.reason AS motivo_contestacao,
    pmc.decision_reason AS decisao_contestacao,
    pmc.status AS status_contestacao,
    mc.created_at,
    pmc.created_at AS contestado_em
FROM campaigns c
JOIN actions a ON a.ad_id IN (
    SELECT id FROM ads WHERE campaign_id = c.id
)
JOIN proofread_medias pm ON pm.action_id = a.id
JOIN media_content mc ON mc.action_id = a.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = CAMPAIGN_ID
  AND (mc.refusal_reason IS NOT NULL OR pmc.reason IS NOT NULL)
ORDER BY mc.created_at DESC;
```

## Usage

**Main command** (after setup):
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-comments
bash scripts/export-campaign-comments.sh <campaign_id_or_name>
```

Examples:
```bash
bash scripts/export-campaign-comments.sh 500239
bash scripts/export-campaign-comments.sh "VITAMIN C12"
```

**Fallback (CSV only)** if Google Sheets auth fails:
```bash
bash scripts/export-campaign-comments-csv.sh <campaign_id_or_name>
```
Returns a local CSV file path (manual upload needed).

## Output

Google Sheets URL with shareable link (anyone with link can view).

## Safety

- READ ONLY queries
- Always exports to Google Sheets (NEVER local files)
- Sheet title: "Campaign Comments - {campaign_name} - {date}"
- Auto-shared with "anyone with link can view" permissions
