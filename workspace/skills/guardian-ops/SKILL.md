---
name: guardian-ops
description: Guardian content moderation analytics, debugging, and improvement. Covers agreement rate, FP/FN rates, contest analysis, disagreement investigation, tolerance/error pattern debugging, and agent prompt improvement.
---

# Guardian Ops

Unified analytics and improvement workflow for Guardian's content moderation system.

## System Context

Guardian evaluates creator-submitted content against campaign guidelines. Two independent decisions:
- **Guardian decision**: AI-driven (`proofread_medias.is_approved`)
- **Brand decision**: Manual — `media_content.refused_at` (refused) or `actions.approved_at` (approved)
- **Agentic model** identified by `audio_output` in `proofread_medias.metadata` JSON

## Core SQL Templates

### Agreement Rate (Avg by Campaign)
```sql
SELECT
  ROUND(AVG(CASE WHEN is_agentic_model = 1 THEN avg_agreement END), 2) AS agentic,
  ROUND(AVG(CASE WHEN is_agentic_model = 0 THEN avg_agreement END), 2) AS old_model
FROM (
  SELECT is_agentic_model, ROUND(AVG(campaign_agreement_pct), 2) AS avg_agreement
  FROM (
    SELECT gpm.campaign_id,
      JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output') AS is_agentic_model,
      ROUND(100.0 * SUM(CASE WHEN gpm.is_approved = CASE WHEN mc.refused_at IS NOT NULL THEN FALSE WHEN a.approved_at IS NOT NULL THEN TRUE ELSE NULL END THEN 1 ELSE 0 END) / COUNT(*), 2) AS campaign_agreement_pct
    FROM proofread_medias gpm
    INNER JOIN media_content mc ON gpm.media_id = mc.id
    INNER JOIN actions a ON mc.action_id = a.id
    INNER JOIN campaigns c ON c.id = gpm.campaign_id
    WHERE LOWER(c.title) NOT LIKE '%teste%'
      AND (CASE WHEN mc.refused_at IS NOT NULL THEN FALSE WHEN a.approved_at IS NOT NULL THEN TRUE ELSE NULL END) IS NOT NULL
      AND gpm.created_at >= '2026-02-04 14:18:50'
    GROUP BY gpm.campaign_id, is_agentic_model
    HAVING COUNT(DISTINCT gpm.media_id) >= 10
  ) t GROUP BY is_agentic_model
) t2;
```

### Contest Rate per 100 Moderations
```sql
SELECT
  ROUND(100.0 * SUM(CASE WHEN is_agent THEN contests ELSE 0 END) /
    NULLIF(SUM(CASE WHEN is_agent THEN volume ELSE 0 END), 0), 2) AS agent_per_100,
  ROUND(100.0 * SUM(CASE WHEN NOT is_agent THEN contests ELSE 0 END) /
    NULLIF(SUM(CASE WHEN NOT is_agent THEN volume ELSE 0 END), 0), 2) AS old_per_100
FROM (
  SELECT JSON_CONTAINS_PATH(pm.metadata, 'one', '$.audio_output') AS is_agent,
    COUNT(DISTINCT c.id) AS contests, COUNT(DISTINCT pm.id) AS volume
  FROM proofread_medias pm
  LEFT JOIN proofread_media_contest c ON c.proofread_media_id = pm.id
  INNER JOIN campaigns camp ON camp.id = pm.campaign_id
  WHERE LOWER(camp.title) NOT LIKE '%teste%' AND pm.created_at >= '2026-02-04 14:18:50'
  GROUP BY is_agent
) t;
```

### Disagreement by Classification (Agentic Only)
```sql
SELECT classification, COUNT(*) AS total,
  SUM(CASE WHEN guideline_answer = FALSE AND brand_answer = TRUE THEN 1
    WHEN guideline_answer = TRUE AND brand_answer = FALSE AND brand_rejected THEN 1 ELSE 0 END) AS disagreements,
  SUM(CASE WHEN guideline_answer = FALSE AND brand_answer = TRUE THEN 1 ELSE 0 END) AS fn,
  SUM(CASE WHEN guideline_answer = TRUE AND brand_answer = FALSE AND brand_rejected THEN 1 ELSE 0 END) AS fp
FROM (
  SELECT pg.classification, pg.answer AS guideline_answer,
    CASE WHEN mc.refused_at IS NOT NULL THEN FALSE WHEN a.approved_at IS NOT NULL THEN TRUE ELSE NULL END AS brand_answer,
    rr.guideline_id IS NOT NULL AS brand_rejected
  FROM proofread_guidelines pg
  INNER JOIN proofread_medias pm ON pg.proofread_media_id = pm.id
  INNER JOIN media_content mc ON pm.media_id = mc.id
  INNER JOIN actions a ON mc.action_id = a.id
  INNER JOIN campaigns c ON c.id = pm.campaign_id
  LEFT JOIN media_content_refused_guidelines rr ON pg.guideline_id = rr.guideline_id
  WHERE LOWER(c.title) NOT LIKE '%teste%'
    AND JSON_CONTAINS_PATH(pm.metadata, 'one', '$.audio_output') = TRUE
    AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)
    AND pg.classification NOT IN ('BRAND_SAFETY_GUIDELINE', 'PRONUNCIATION_GUIDELINE')
) t WHERE brand_answer IS NOT NULL
GROUP BY classification ORDER BY disagreements DESC;
```

## Interpretation

| Metric | Good | Bad | Action |
|--------|------|-----|--------|
| Agreement Rate | >85% | <70% | Investigate worst campaigns |
| FP Rate | <5% | >15% | Agent too lenient — tighten prompts |
| FN Rate | <5% | >15% | Agent too strict — relax prompts |
| Contest Rate | Agentic < Old | Agentic >> Old | Investigate reasons |

## Investigation Workflow

1. Run core metrics
2. Identify worst metric
3. Pull 10-20 specific disagreement examples
4. Cross-reference with Langfuse traces for reasoning
5. Check tolerance/error patterns in BigQuery
6. Determine root cause: prompt, pipeline, data, or expected behavior
7. Recommend fix with evidence
