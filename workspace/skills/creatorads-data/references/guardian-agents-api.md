# Guardian Agents API — Database Usage

Python FastAPI service that manages AI agent semantic memory via BigQuery and reads from MySQL for pipeline ingestion.

**Codebase**: `/Users/fonsecabc/brandlovrs/ai/guardian/guardian-agents-api`

## BigQuery Dataset: `guardian`

### tolerance_patterns
Aggregated tolerance patterns from high-disagreement guidelines. Each pattern = (guideline_archetype, action_type) pair.

| Column | Type | Notes |
|---|---|---|
| guideline_archetype | STRING REQUIRED | Generalized guideline template |
| action_category | STRING REQUIRED | VISUAL_RESTRICTION, VERBAL_RESTRICTION, PROCEDURAL_REQUIREMENT, etc. |
| action_subcategory | STRING REQUIRED | e.g. brand_identification, product_claim |
| prohibition_or_requirement | STRING REQUIRED | "prohibition" or "requirement" |
| generalized_action | STRING REQUIRED | Action without specific objects |
| total_cases | INTEGER REQUIRED | Count of rejections later approved |
| unique_brands | INTEGER REQUIRED | Must be 3+ for pattern to be valid |
| prominence_patterns | STRUCT | common_approved_phrases, typical_approved_range |
| duration_patterns | STRUCT | common_approved_phrases, typical_approved_range |
| context_patterns | STRUCT | commonly_approved, rarely_approved |
| element_criticality | STRUCT | critical_elements, flexible_elements, optional_elements |
| confidence_score | FLOAT64 | 0.0-1.0 pattern reliability |
| example_cases | ARRAY<STRUCT> | guideline, justification, time |
| pattern_embedding | ARRAY<FLOAT64> | For vector search |

**Vector search** uses `guardian.gemini_embedding_model` with COSINE distance.

### error_patterns
Clustered error patterns by guideline similarity.

| Column | Type | Notes |
|---|---|---|
| guideline_archetype | STRING REQUIRED | |
| error_type | STRING REQUIRED | THRESHOLD_TOO_STRICT, CONTEXT_MISUNDERSTOOD, GUIDELINE_MISINTERPRETED, FALSE_DETECTION, TEMPORAL_ERROR, SEMANTIC_PARAPHRASE_OK, BRAND_TOLERANCE_HIGHER |
| guideline_classification | STRING | GENERAL_GUIDELINE, CAPTIONS_GUIDELINE, etc. |
| correction_guidance | STRING | Actionable guidance for agents |
| total_cases | INTEGER REQUIRED | |
| error_sources | STRUCT | contest_count, brand_refusal_count |
| example_errors | ARRAY<STRUCT> | error_description, ai_justification, guideline |
| pattern_embedding | ARRAY<FLOAT64> | |
| confidence_score | FLOAT64 | |

**Vector search** filtered by `guideline_classification` and `distance <= threshold`.

### error_signals
Raw error signals from contests and brand refusals.

| Column | Type | Notes |
|---|---|---|
| error_source | STRING REQUIRED | CONTEST_APPROVED or BRAND_REFUSED_GUIDELINE |
| guideline, classification, requirement | STRING | |
| error_description | STRING REQUIRED | Analyst reason or brand refusal reason |
| ai_justification | STRING | Guardian's justification |
| ai_answer | BOOLEAN | Guardian's decision |
| ai_severity | INTEGER | 1-5 |
| ai_reasoning, ai_relevance_analysis, ai_intent_consideration | STRING | From pg.metadata JSON |
| evidence_time | STRING | Video timestamp |
| brand_id, campaign_id, media_id | INTEGER | |
| source_id | INTEGER REQUIRED | proofread_guidelines.id |
| error_embedding | ARRAY<FLOAT64> | |
| error_type | STRING | Classified by build pipeline |

### rejected_guidelines_with_disagreement
Unique rejected guidelines where Guardian rejected but brand approved.

| Column | Type | Notes |
|---|---|---|
| guideline | STRING REQUIRED | Unique guideline text |
| guideline_id | INTEGER | Representative proofread_guidelines.id |
| total_cases | INTEGER REQUIRED | |
| action_category, action_subcategory | STRING | |
| prohibition_or_requirement | STRING | |
| generalized_action | STRING | |
| guideline_embedding | ARRAY<FLOAT64> | |
| example_cases | ARRAY<STRUCT> | justification, time |

### guidelines_critiques_gold_standards
Canonical examples for guideline critique evaluation.

| Column | Type | Notes |
|---|---|---|
| brand_id, brand_name | INT/STRING | |
| campaign_id, campaign_title | INT/STRING | |
| moment_id, moment_title | INT/STRING | |
| campaign_briefing, moment_briefing | STRING | |
| guideline | STRING | |
| requirement | STRING | MUST_DO or MUST_NOT_DO |
| gold_feedback_type, gold_improved_guideline, gold_feedback | STRING | |
| guideline_embedding | ARRAY<FLOAT64> | Uses `text_embedding_model` (legacy) |

## MySQL Pipeline Queries

### Load Rejected Guidelines
```sql
SELECT pg.id as guideline_id, pm.brand_id, pm.campaign_id, pm.moment_id,
       pm.ad_id, pm.action_id, pm.media_id, pg.guideline, pg.justification, pg.`time`
FROM proofread_guidelines pg
INNER JOIN proofread_medias pm ON pg.proofread_media_id = pm.id
INNER JOIN media_content mc ON pm.media_id = mc.id
INNER JOIN actions a ON mc.action_id = a.id
WHERE pg.classification = 'GENERAL_GUIDELINE'
  AND pg.answer = false
  AND pg.id > @min_pg_id
  AND pm.brand_id NOT IN (171, 216, 446, 689, 793)  -- internal brands
  AND mc.refused_at IS NULL
  AND a.approved_at IS NOT NULL
```

### Load Contest Error Signals
```sql
SELECT pg.id as pg_id, pmc.id as contest_id, pmc.decision_reason,
       pg.guideline, pg.classification, pg.requirement,
       pg.answer as ai_answer, pg.justification as ai_justification,
       pg.time as evidence_time,
       JSON_EXTRACT(pg.metadata, '$.severity') as ai_severity,
       JSON_UNQUOTE(JSON_EXTRACT(pg.metadata, '$.reasoning')) as ai_reasoning,
       JSON_UNQUOTE(JSON_EXTRACT(pg.metadata, '$.intent_consideration')) as ai_intent_consideration,
       JSON_EXTRACT(pg.metadata, '$.relevance_analysis') as ai_relevance_analysis,
       pm.brand_id, pm.campaign_id, pm.media_id
FROM proofread_media_contest pmc
INNER JOIN proofread_medias pm ON pmc.proofread_media_id = pm.id
INNER JOIN proofread_guidelines pg ON pg.proofread_media_id = pm.id
  AND pg.answer = 0 AND pg.deleted_at IS NULL
WHERE pmc.status = 'approved'
  AND pmc.decision_reason IS NOT NULL
  AND JSON_CONTAINS_PATH(pm.metadata, 'one', '$.audio_output')
  AND pg.classification != 'PRONUNCIATION_GUIDELINE'
  AND pm.brand_id NOT IN (171, 216, 446, 689, 793)
```

### Load Brand Refusal Error Signals
```sql
SELECT pg.id as pg_id, mcrf.media_content_id, mcrf.guideline_id,
       g.guideline, g.classification,
       COALESCE(pg.requirement, g.requirement) as requirement,
       mc.refusal_reason as brand_refusal_reason,
       pg.answer as ai_answer, pg.justification as ai_justification,
       pg.time as evidence_time,
       JSON_EXTRACT(pg.metadata, '$.severity') as ai_severity,
       pm.brand_id, pm.campaign_id, pm.media_id
FROM media_content_refused_guidelines mcrf
INNER JOIN guidelines g ON mcrf.guideline_id = g.id
INNER JOIN media_content mc ON mcrf.media_content_id = mc.id
INNER JOIN proofread_medias pm ON pm.media_id = mc.id
INNER JOIN proofread_guidelines pg ON pg.proofread_media_id = pm.id
  AND pg.guideline_id = mcrf.guideline_id AND pg.deleted_at IS NULL
WHERE mc.refused_at IS NOT NULL
  AND g.classification IS NOT NULL
  AND g.classification != 'PRONUNCIATION_GUIDELINE'
  AND JSON_CONTAINS_PATH(pm.metadata, 'one', '$.audio_output')
  AND pm.brand_id NOT IN (171, 216, 446, 689, 793)
```

## BigQuery ML Models
- **`guardian.text_embedding_model`** (legacy) — Used for guidelines_critiques_gold_standards
- **`guardian.gemini_embedding_model`** (current) — Used for tolerance_patterns, error_patterns, error_signals

## Incremental Loading
- **rejected_guidelines**: Watermark = `MAX(guideline_id)` from BigQuery
- **error_signals**: Watermark = `MAX(source_id)` per `error_source` from BigQuery

## Internal Brand IDs (excluded from pipelines)
`[171, 216, 446, 689, 793]`
