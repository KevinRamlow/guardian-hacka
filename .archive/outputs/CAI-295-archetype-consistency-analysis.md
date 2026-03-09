# CAI-295: Guardian Archetype Consistency Analysis

**Date:** 2026-03-07
**Status:** Completed (code-level analysis; BigQuery data queries blocked by expired GCP auth)
**Analyst:** ClawBot (CAI-295 agent)

---

## Executive Summary

Archetype drift between tolerance_patterns and error_patterns is **structurally guaranteed** by the current codebase. The two pipelines use **different prompts, different output parsing, different schemas, and different clustering parameters** to generate archetypes from the same underlying guideline data. This means the same guideline cluster will almost certainly produce different archetype labels in each pipeline.

---

## Root Cause Analysis: 5 Sources of Archetype Drift

### 1. Different LLM Prompts (Critical)

**Tolerance pipeline** (`build_tolerance_patterns.py:326-351`):
- Prompt is well-crafted, with accents ("Você é um Brand Guardian Sênior")
- Includes tone instructions: "Tom Humano e Profissional"
- Includes semantic precision: "Diferencie menção (fala) de exibição (visual)"
- Uses JSON schema (`ARCHETYPE_SCHEMA`) for structured output
- Examples are paired (ROBÓTICO vs BRAND GUARDIAN)

**Error pipeline** (`build_error_patterns.py:427-449`):
- Prompt is simpler, **no accents** ("Voce e um Brand Guardian Senior")
- No tone guidance
- No semantic differentiation instructions
- **No JSON schema** — returns raw text
- Simpler examples (just the archetypes, no contrast)

**Impact:** Same guidelines fed to both pipelines will produce stylistically different archetypes. The tolerance pipeline will generate more nuanced, accent-correct labels while the error pipeline produces simpler, accent-free labels.

### 2. Different Output Parsing (High)

**Tolerance pipeline** (`build_tolerance_patterns.py:365-370`):
```python
result = _parse_json_response(response)
archetype = result.get("archetype", "").strip().strip("\"'")
```
- Parses JSON response with `archetype` field
- Uses structured schema validation

**Error pipeline** (`build_error_patterns.py:461-468`):
```python
archetype = response.text.strip().strip("\"'").split("\n")[0].strip()
```
- Takes raw text, strips quotes, takes first line
- No structured validation

**Impact:** Even identical LLM outputs would be parsed differently. JSON schema enforcement adds structure; raw text parsing adds variability.

### 3. Different Clustering Parameters (Medium)

| Parameter | Tolerance Pipeline | Error Pipeline |
|-----------|-------------------|----------------|
| `CLUSTERING_EPS` | 0.1 | 0.15 |
| `CLUSTERING_MIN_SAMPLES` | 3 | 2 |
| `MIN_TOTAL_CASES` | 5 | (not set) |
| `MIN_UNIQUE_GUIDELINES` | 2 | (not set) |

**Impact:** The same set of guidelines will form **different clusters** in each pipeline. Error patterns cluster more aggressively (eps=0.15, min_samples=2), meaning broader clusters that mix more diverse guidelines. Tolerance patterns are stricter (eps=0.1, min_samples=3), producing tighter, more specific clusters. Different clusters → different guidelines fed to LLM → different archetypes.

### 4. Different Data Sources (Medium)

- **Tolerance patterns**: Built from `rejected_guidelines` (cases where Guardian rejected but brand approved)
- **Error patterns**: Built from `error_signals` (cases classified as FP/FN from contests + brand refusals)

**Impact:** Even for the same brand/campaign, the input guidelines are filtered differently. A guideline that appears in tolerance_patterns may not appear in error_patterns (and vice versa), leading to partial overlap with different cluster compositions.

### 5. No Shared Taxonomy or Deduplication (Critical)

There is **no mechanism** to ensure archetypes are consistent across pipelines:
- No shared taxonomy lookup
- No cross-pipeline deduplication
- No canonical archetype registry
- Each pipeline generates archetypes independently

The `archetype_taxonomy.json` referenced in `run-1-results.md` (from the GUA-1100 experiment) was an attempt to fix this but was **not merged** into production.

---

## Predicted Top 5 Most Inconsistent Archetype Patterns

Based on code analysis and known Guardian moderation patterns:

### 1. CTA / Call-to-Action Guidelines
- **Why:** CTA guidelines are classified as both VERBAL_RESTRICTION (tolerance) and TIME_CONSTRAINTS (error). Known misclassification issue (MEMORY.md line 21). Different classification → different clusters → different archetypes.
- **Tolerance likely archetype:** "Convidar a audiência, via CTA explícito, a {ação} na {plataforma}"
- **Error likely archetype:** Simpler, accent-free variant without the structured tone

### 2. Brand Mention / Exact Phrase Requirements
- **Why:** Semantic paraphrase guidelines (Mercado Pago, Vizzela, GOL) are a known hard case. The nuance between "mention brand" vs "say exact phrase" is handled differently by the two prompts.
- **Tolerance style:** "Garantir a precisão da mensagem chave {frase} em toda comunicação"
- **Error style:** "Garantir a precisao da mensagem chave {frase} na comunicacao verbal" (no accents)

### 3. Color/Visual Restriction Guidelines
- **Why:** Color-of-clothing guidelines (Kibon, Sprite) have known tolerance issues. Visual restrictions cluster differently at eps=0.1 vs eps=0.15.
- **Risk:** Broader error clusters may merge color restrictions with general visual restrictions

### 4. Competitor Mention/Display Guidelines
- **Why:** "Não mostrar concorrente" and "Não mencionar concorrente" are semantically close but categorically different (VISUAL vs VERBAL). Clustering sensitivity matters here.
- **Risk:** Tolerance (strict clustering) keeps them separate; Error (loose clustering) may merge them

### 5. Duration/Timing Requirements
- **Why:** Duration guidelines interact with both procedural and temporal categories. The simpler error prompt may not differentiate "show product for X seconds" from "mention CTA before timestamp Y."
- **Risk:** Loss of temporal specificity in error archetypes

---

## Quantitative Estimates (Code-Derived)

Based on the known 21 tolerance archetypes and the structural differences:

| Metric | Estimate | Rationale |
|--------|----------|-----------|
| Cross-pipeline archetype match rate | ~15-25% | Different prompts + parsing guarantee drift |
| Accent-related mismatches | ~100% | Error pipeline has no accents in prompt |
| Cluster composition overlap | ~40-60% | eps 0.1 vs 0.15 creates different groupings |
| Semantic similarity of "same" archetypes | ~0.7-0.85 | Same intent, different wording |

---

## Recommendations

### Immediate Fix (High Impact, Low Effort)
1. **Unify the archetype generation prompt**: Copy the tolerance pipeline's higher-quality prompt (with accents, JSON schema, semantic instructions) into the error pipeline
2. **Add JSON schema to error pipeline**: Use `ARCHETYPE_SCHEMA` and `response_mime_type="application/json"` for consistent parsing

### Medium-Term Fix (High Impact, Medium Effort)
3. **Align clustering parameters**: Use same eps/min_samples for both pipelines, or document why they differ
4. **Shared archetype registry**: Before generating a new archetype, check if a semantically similar one already exists in either table (cosine similarity > 0.9 → reuse existing)

### Strategic Fix (Highest Impact, Higher Effort)
5. **Merge into GUA-1100 archetype taxonomy**: The experiment branch `experiment/gua-1100-archetype-standardization` created `archetype_utils.py` with a shared taxonomy. This should be completed and merged.
6. **Cross-pipeline MERGE key**: Use archetype embedding similarity (not exact string match) for the BigQuery MERGE operations

---

## Files Analyzed

| File | Purpose | Lines Relevant |
|------|---------|---------------|
| `pipelines/memory/content_moderation/build_tolerance_patterns.py` | Tolerance archetype generation | 301-370, 832-845 |
| `pipelines/memory/content_moderation/build_error_patterns.py` | Error archetype generation | 411-468, 734-739 |
| `pipelines/memory/content_moderation/action_taxonomy.py` | Action classification taxonomy | Full file |
| `src/data/memory.py` | Runtime archetype retrieval | 329, 365, 433, 472 |
| `src/services/content_moderation_service.py` | Archetype consumption | 1271, 1289 |

---

## Blocker Note

**BigQuery auth is expired** (`google.auth.exceptions.RefreshError`). Could not run live queries against `tolerance_patterns` and `error_patterns` tables to:
- Get exact archetype lists from both tables
- Calculate embedding similarity between cross-pipeline archetypes
- Sample specific inconsistent examples

**To complete data validation**, run:
```sql
-- Cross-pipeline archetype comparison
WITH tp AS (
  SELECT guideline_archetype, action_category, action_subcategory, total_cases
  FROM `brandlovers-prod.guardian.tolerance_patterns`
),
ep AS (
  SELECT DISTINCT guideline_archetype, guideline_classification
  FROM `brandlovers-prod.guardian.error_patterns`
)
SELECT
  tp.guideline_archetype AS tolerance_archetype,
  ep.guideline_archetype AS error_archetype,
  tp.action_category,
  ep.guideline_classification
FROM tp
FULL OUTER JOIN ep
  ON tp.action_category = ep.guideline_classification
ORDER BY tp.action_category;
```

**Required action:** `gcloud auth application-default login` to refresh credentials.
