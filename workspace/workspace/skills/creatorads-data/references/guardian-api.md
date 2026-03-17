# Guardian API — Database Usage

Guardian API is the core content moderation and orchestration service. It connects to **two MySQL databases**: Creator Ads (db-maestro-prod) and Catalyst.

**Codebase**: `/Users/fonsecabc/brandlovrs/ai/guardian/guardian-api` (Golang, GORM)

## Databases
- **Creator Ads (Maestro)**: campaigns, moments, ads, actions, media_content, proofread_*, guardian_evals
- **Catalyst**: guidelines, guidelines_critiques, improved_guidelines, pronunciation_targets, pronunciation_gold_standards, guideline_pronunciation_targets, guardian_evals (catalyst copy)

## Key Queries

### LoadMediaForProofreading
Joins 6 tables to get full context for AI moderation:
```sql
SELECT c.brand_id, b.name as brand_name, c.id as campaign_id, c.title,
       m.id as moment_id, ad.id, a.id as action_id,
       mc.id as media_id, a.creator_id,
       COALESCE(mc.compressed_media_key, mc.media_url) as media_key
FROM media_content mc
INNER JOIN actions a ON a.id = mc.action_id
INNER JOIN ads ad ON ad.id = a.ad_id
INNER JOIN moments m ON m.id = ad.moment_id
INNER JOIN campaigns c ON c.id = m.campaign_id
INNER JOIN brands b ON b.id = c.brand_id
WHERE mc.id = ?
```

### GetCreatorsByCampaignIDAndApprovalStatus
Find creators with specific AI approval status for a campaign:
```sql
SELECT pm.creator_id
FROM proofread_medias pm
INNER JOIN actions act ON act.id = pm.action_id
INNER JOIN media_content mc ON mc.id = pm.media_id
WHERE pm.campaign_id = ? AND pm.brand_id = ?
  AND pm.is_approved = ? AND pm.deleted_at IS NULL
  AND act.approved_at IS NULL AND act.refused_at IS NULL
  AND act.deleted_at IS NULL AND mc.deleted_at IS NULL
GROUP BY pm.creator_id
```

### GetMediaForEval
Complex evaluation dataset selection with diversity scoring:
- Finds underrepresented guideline classifications
- Selects campaigns by diversity score
- Balances agreement/disagreement samples
- Uses subqueries to count evaluated medias and guidelines

### GetDeletedMediaFilesFromEndedCampaigns
Cleanup query for GCS storage (campaigns ended 90+ days ago):
```sql
SELECT mc.id, c.id, c.title, c.updated_at, mc.compressed_media_key, mc.media_url, mc.deleted_at
FROM media_content mc
INNER JOIN actions act ON mc.action_id = act.id
INNER JOIN ads a ON act.ad_id = a.id
INNER JOIN moments m ON a.moment_id = m.id
INNER JOIN campaigns c ON m.campaign_id = c.id
WHERE mc.deleted_at IS NOT NULL AND mc.storage_deleted_at IS NULL
  AND c.deleted_at IS NULL AND c.campaign_state_id = 4
  AND c.updated_at < NOW() - INTERVAL 90 DAY
ORDER BY c.updated_at ASC
```

### Proofread Creation (with distributed lock)
Uses MySQL `GET_LOCK()`/`RELEASE_LOCK()` for deadlock prevention when creating proofread_medias records.

### Caption Requirement Check
Checks if ad requires captions by looking at ads_attributes:
- Format attribute IDs for caption: 42 (Reels), 43 (Story), 48 (TikTok), 68 (YouTube Shorts)
- `assigned = true` means caption is required

## Entity Relationships Used

```
campaigns → moments → ads → actions → media_content
                                          ↓
                                    proofread_medias → proofread_guidelines
                                          ↓                    ↓
                                proofread_media_contest   proofread_pronunciation_results
                                proofread_medias_audio_quality
                                proofread_medias_songs_audit

guidelines (catalyst) → guideline_pronunciation_targets → pronunciation_targets → pronunciation_gold_standards
```

## Key Business Logic
- **Auto-refusal**: When `proofread_medias.is_approved = false`, Guardian can auto-refuse media by setting `media_content.is_refused_by_guardian = true`
- **Contest flow**: Creator contests via `proofread_media_contest` → analyst reviews → status becomes 'approved' or 'rejected'
- **Eval system**: `guardian_evals` tracks human feedback on individual guideline decisions; `guardian_media_evals` tracks overall media assessment
