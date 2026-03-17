# Common Queries Reference

Frequently used SQL queries for data investigation and analytics across the CreatorAds platform.
All queries target **db-maestro-prod** unless noted otherwise.

## Campaign Metrics

### Campaign Overview with Creator Counts
```sql
SELECT c.id, c.title, cs.name as state, b.name as brand,
       COUNT(DISTINCT cgi.creator_id) as total_creators,
       SUM(CASE WHEN cgi.status = 'participating' THEN 1 ELSE 0 END) as participating,
       SUM(CASE WHEN cgi.status IN ('paid','paid_partial') THEN 1 ELSE 0 END) as paid
FROM campaigns c
INNER JOIN campaign_states cs ON cs.id = c.campaign_state_id
INNER JOIN brands b ON b.id = c.brand_id
LEFT JOIN creator_group_invites cgi ON cgi.campaign_id = c.id AND cgi.deleted_at IS NULL
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.title, cs.name, b.name
ORDER BY c.id DESC;
```

### Campaign Budget vs Spent
```sql
SELECT c.id, c.title, c.budget,
       COALESCE(SUM(cgi.reward_value), 0) as committed_budget,
       COUNT(DISTINCT CASE WHEN cgi.status IN ('participating','paid','paid_partial','pending_payment') THEN cgi.creator_id END) as active_creators
FROM campaigns c
LEFT JOIN creator_group_invites cgi ON cgi.campaign_id = c.id
  AND cgi.status IN ('participating','paid','paid_partial','pending_payment')
  AND cgi.deleted_at IS NULL
WHERE c.id = ?
GROUP BY c.id;
```

### Active Campaigns with Content Stats
```sql
SELECT c.id, c.title, b.name as brand,
       COUNT(DISTINCT act.id) as total_actions,
       COUNT(DISTINCT mc.id) as total_media,
       COUNT(DISTINCT CASE WHEN mc.approved_at IS NOT NULL THEN mc.id END) as approved_media,
       COUNT(DISTINCT CASE WHEN mc.refused_at IS NOT NULL THEN mc.id END) as refused_media,
       COUNT(DISTINCT CASE WHEN mc.is_refused_by_guardian = 1 THEN mc.id END) as guardian_refused
FROM campaigns c
INNER JOIN brands b ON b.id = c.brand_id
INNER JOIN moments m ON m.campaign_id = c.id AND m.deleted_at IS NULL
INNER JOIN ads a ON a.moment_id = m.id AND a.deleted_at IS NULL
LEFT JOIN actions act ON act.ad_id = a.id AND act.deleted_at IS NULL
LEFT JOIN media_content mc ON mc.action_id = act.id AND mc.deleted_at IS NULL
WHERE c.campaign_state_id = 2 AND c.deleted_at IS NULL
GROUP BY c.id, c.title, b.name;
```

## Guardian Moderation Analytics

### Guardian Accuracy by Brand (agreement with brand decisions)
```sql
SELECT pm.brand_id, b.name as brand,
       COUNT(*) as total_medias,
       SUM(CASE WHEN pm.is_approved = 1 AND mc.approved_at IS NOT NULL THEN 1
                WHEN pm.is_approved = 0 AND mc.refused_at IS NOT NULL THEN 1
                ELSE 0 END) as agreements,
       ROUND(
         SUM(CASE WHEN pm.is_approved = 1 AND mc.approved_at IS NOT NULL THEN 1
                  WHEN pm.is_approved = 0 AND mc.refused_at IS NOT NULL THEN 1
                  ELSE 0 END) * 100.0 / COUNT(*), 2
       ) as agreement_rate
FROM proofread_medias pm
INNER JOIN media_content mc ON mc.id = pm.media_id AND mc.deleted_at IS NULL
INNER JOIN brands b ON b.id = pm.brand_id
INNER JOIN actions a ON a.id = pm.action_id AND a.deleted_at IS NULL
WHERE pm.deleted_at IS NULL
  AND (mc.approved_at IS NOT NULL OR mc.refused_at IS NOT NULL)
GROUP BY pm.brand_id, b.name
ORDER BY total_medias DESC;
```

### Guardian False Positives (AI refused, brand approved)
```sql
SELECT pm.brand_id, b.name, pm.campaign_id, c.title,
       pm.media_id, pm.is_approved, pm.adherence,
       pg.guideline, pg.classification, pg.justification, pg.time
FROM proofread_medias pm
INNER JOIN media_content mc ON mc.id = pm.media_id
INNER JOIN actions a ON a.id = mc.action_id
INNER JOIN brands b ON b.id = pm.brand_id
INNER JOIN campaigns c ON c.id = pm.campaign_id
INNER JOIN proofread_guidelines pg ON pg.proofread_media_id = pm.id AND pg.answer = 0 AND pg.deleted_at IS NULL
WHERE pm.is_approved = 0
  AND pm.deleted_at IS NULL AND mc.deleted_at IS NULL AND a.deleted_at IS NULL
  AND a.approved_at IS NOT NULL  -- brand approved
ORDER BY pm.created_at DESC
LIMIT 100;
```

### Guideline Classification Distribution
```sql
SELECT pg.classification,
       COUNT(*) as total,
       SUM(CASE WHEN pg.answer = 1 THEN 1 ELSE 0 END) as passed,
       SUM(CASE WHEN pg.answer = 0 THEN 1 ELSE 0 END) as failed,
       ROUND(SUM(CASE WHEN pg.answer = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as failure_rate
FROM proofread_guidelines pg
INNER JOIN proofread_medias pm ON pm.id = pg.proofread_media_id AND pm.deleted_at IS NULL
WHERE pg.deleted_at IS NULL
GROUP BY pg.classification
ORDER BY total DESC;
```

### Contest Rate by Brand
```sql
SELECT pm.brand_id, b.name,
       COUNT(DISTINCT pm.id) as total_proofread,
       COUNT(DISTINCT pmc.id) as total_contests,
       ROUND(COUNT(DISTINCT pmc.id) * 100.0 / COUNT(DISTINCT pm.id), 2) as contest_rate,
       SUM(CASE WHEN pmc.status = 'approved' THEN 1 ELSE 0 END) as contests_won
FROM proofread_medias pm
INNER JOIN brands b ON b.id = pm.brand_id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.deleted_at IS NULL AND pm.is_approved = 0
GROUP BY pm.brand_id, b.name
HAVING total_proofread > 10
ORDER BY contest_rate DESC;
```

## Creator Analytics

### Creator Status in Campaign
```sql
SELECT cgi.creator_id, cgi.status, cgi.reward_value, cgi.fee_percentage,
       cgi.participating_at, cgi.approved_at, cgi.paid_at,
       cg.title as group_name, cg.channel
FROM creator_group_invites cgi
INNER JOIN creator_groups cg ON cg.id = cgi.creator_group_id
WHERE cgi.campaign_id = ? AND cgi.deleted_at IS NULL
ORDER BY cgi.creator_id, cgi.id DESC;
```

### Creator Content Delivery Status
```sql
SELECT act.creator_id,
       COUNT(DISTINCT a.id) as total_ads,
       COUNT(DISTINCT CASE WHEN mc.id IS NOT NULL THEN a.id END) as ads_with_content,
       COUNT(DISTINCT CASE WHEN act.approved_at IS NOT NULL THEN a.id END) as ads_approved,
       COUNT(DISTINCT CASE WHEN act.posted_at IS NOT NULL THEN a.id END) as ads_posted
FROM actions act
INNER JOIN ads a ON a.id = act.ad_id AND a.deleted_at IS NULL
INNER JOIN moments m ON m.id = a.moment_id AND m.deleted_at IS NULL
LEFT JOIN media_content mc ON mc.action_id = act.id AND mc.deleted_at IS NULL
WHERE m.campaign_id = ? AND act.deleted_at IS NULL
GROUP BY act.creator_id;
```

## Payment Queries

### Payment Summary by Campaign
```sql
SELECT cph.campaign_id, c.title,
       COUNT(DISTINCT cph.creator_id) as creators_paid,
       SUM(cph.value) as total_net_paid,
       SUM(cph.gross_value) as total_gross_paid,
       SUM(cph.gross_value - cph.value) as total_fees
FROM creator_payment_history cph
INNER JOIN campaigns c ON c.id = cph.campaign_id
WHERE cph.status = 'paid'
GROUP BY cph.campaign_id, c.title;
```

### Unpaid Participating Creators
```sql
SELECT cgi.creator_id, cgi.campaign_id, c.title, cgi.reward_value,
       cgi.participating_at, cgi.status
FROM creator_group_invites cgi
INNER JOIN campaigns c ON c.id = cgi.campaign_id
WHERE cgi.status = 'participating'
  AND cgi.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM creator_payment_history cph
    WHERE cph.creator_id = cgi.creator_id AND cph.campaign_id = cgi.campaign_id
  )
ORDER BY cgi.participating_at;
```

## Boost Analytics

### Boost Spend by Campaign
```sql
SELECT ba.campaign_id, c.title, ba.channel,
       COUNT(*) as total_boosts,
       SUM(ba.budget) / 100 as total_budget_reais,
       SUM(ba.budget_spent) / 100 as total_spent_reais,
       ROUND(SUM(ba.budget_spent) * 100.0 / NULLIF(SUM(ba.budget), 0), 2) as spend_rate
FROM boost_ads ba
INNER JOIN campaigns c ON c.id = ba.campaign_id
WHERE ba.deleted_at IS NULL
GROUP BY ba.campaign_id, c.title, ba.channel;
```

## Human Evaluation Analytics

### Guardian Eval Accuracy
```sql
SELECT COUNT(*) as total_evals,
       SUM(CASE WHEN ge.is_correct = 1 THEN 1 ELSE 0 END) as correct,
       ROUND(SUM(CASE WHEN ge.is_correct = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as accuracy,
       pg.classification
FROM guardian_evals ge
INNER JOIN proofread_guidelines pg ON pg.id = ge.proofread_guideline_id
GROUP BY pg.classification
ORDER BY total_evals DESC;
```

## Useful Filters

### Internal Brand IDs (exclude from analytics)
```sql
-- Guardian Agents API excludes these from pipelines:
AND brand_id NOT IN (171, 216, 446, 689, 793)
```

### Ended Campaigns (state_id = 4)
```sql
WHERE c.campaign_state_id = 4
```

### Content with Audio (for Guardian moderation)
```sql
AND JSON_CONTAINS_PATH(pm.metadata, 'one', '$.audio_output')
```

### Soft Delete Pattern (all tables)
```sql
AND table.deleted_at IS NULL
```
