# Guardian Database Expert

Complete knowledge base for `db-maestro-prod` MySQL (111 tables, ~1.95M rows) powering Brandlovrs CreatorAds + Guardian.

## Domain Hierarchy

```
Organization → Brand → Campaign → Moment → Ad → Action → MediaContent
                                   ↓          ↓
                             CreatorGroup → CreatorGroupInvite
                                   ↓
                             Guidelines → ProofreadMedias → ProofreadGuidelines
```

## Core Business Flow

1. Brand creates Campaign with Moments and Ads
2. Creators invited to CreatorGroups, submit MediaContent through Actions
3. Guardian moderates → creates ProofreadMedias + ProofreadGuidelines
4. Brand approves/refuses → tracked in MediaContent and Actions

## Key Guardian Tables

| Table | Rows | Purpose |
|-------|------|---------|
| `proofread_medias` | ~57K | Guardian's final decision per media |
| `proofread_guidelines` | ~711K | Per-guideline evaluation |
| `media_content` | ~55K | Content submissions with brand decision |
| `actions` | ~50K | Creator actions with brand approval |
| `guidelines` | ~7.8K | Campaign guidelines |
| `proofread_media_contest` | ~664 | Creator appeals |

## Key Decision Fields

**Guardian**: `proofread_medias.is_approved` (boolean)

**Brand** (derived):
```sql
CASE
  WHEN mc.refused_at IS NOT NULL THEN FALSE
  WHEN a.approved_at IS NOT NULL THEN TRUE
  ELSE NULL
END
```

**Agentic model**: `JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output')`

**Classifications**: GENERAL_GUIDELINE, CAPTIONS_GUIDELINE, VIDEO_DURATION_GUIDELINE, TIME_CONSTRAINTS_GUIDELINE, PRONUNCIATION_GUIDELINE, QUALITY_GUIDELINE, BRAND_SAFETY_GUIDELINE

## Standard Joins

```sql
-- Media → Campaign chain
FROM media_content mc
INNER JOIN actions a ON a.id = mc.action_id
INNER JOIN ads ad ON ad.id = a.ad_id
INNER JOIN moments m ON m.id = ad.moment_id
INNER JOIN campaigns c ON c.id = m.campaign_id
INNER JOIN brands b ON b.id = c.brand_id

-- Guardian moderation chain
FROM proofread_medias gpm
INNER JOIN media_content mc ON gpm.media_id = mc.id
INNER JOIN actions a ON mc.action_id = a.id
INNER JOIN campaigns c ON c.id = gpm.campaign_id
```

## Standard Filters

```sql
LOWER(c.title) NOT LIKE '%teste%'              -- Exclude test campaigns
AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)  -- Only with brand decisions
AND table.deleted_at IS NULL                    -- Soft delete awareness
AND gpm.created_at >= '2026-02-04 14:18:50'    -- Since agentic deploy
```

## Agreement Rate Query

```sql
SELECT
  ROUND(100.0 * SUM(CASE WHEN t.is_agentic AND t.matches THEN 1 ELSE 0 END) /
    NULLIF(SUM(CASE WHEN t.is_agentic THEN 1 ELSE 0 END), 0), 2) AS agentic_agreement,
  ROUND(100.0 * SUM(CASE WHEN NOT t.is_agentic AND t.matches THEN 1 ELSE 0 END) /
    NULLIF(SUM(CASE WHEN NOT t.is_agentic THEN 1 ELSE 0 END), 0), 2) AS old_agreement
FROM (
  SELECT
    JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output') AS is_agentic,
    gpm.is_approved = CASE WHEN mc.refused_at IS NOT NULL THEN FALSE WHEN a.approved_at IS NOT NULL THEN TRUE ELSE NULL END AS matches
  FROM proofread_medias gpm
  INNER JOIN media_content mc ON gpm.media_id = mc.id
  INNER JOIN actions a ON mc.action_id = a.id
  INNER JOIN campaigns c ON c.id = gpm.campaign_id
  WHERE LOWER(c.title) NOT LIKE '%teste%'
    AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)
    AND gpm.created_at >= '2026-02-04 14:18:50'
) t;
```

## Service Interaction

- **guardian-api** (Go/GORM): Primary consumer — reads/writes most tables, distributed locks for proofread creation
- **guardian-agents-api** (Python): Read-only MySQL + BigQuery vector search (tolerance/error patterns)
- **guardian-ads-treatment** (Go): Minimal — only writes `compressed_media_key` to media_content

## BigQuery Tables (`guardian` dataset)

- `tolerance_patterns`: Clustered tolerance from brand overrules (vector search, cosine, threshold=0.4)
- `error_patterns`: Clustered error patterns with correction guidance
- `error_signals`: Raw error signals from contests/refusals
- `rejected_guidelines_with_disagreement`: Unique guidelines with rejection cases
- `guidelines_critiques_gold_standards`: Gold dataset for critique eval

## Conventions

1. Soft deletes: `deleted_at IS NULL` on most tables
2. Two user tables: `user` (internal, 50 rows) vs `users` (brand users, 1141 rows)
3. Campaign hierarchy: campaigns → moments → ads → actions → media_content
4. Guidelines hierarchy: campaign-level > moment-level > ad-level
5. JSON columns: `metadata` on proofread_medias/proofread_guidelines
