# Hypothesis D Results — Memory Pipeline Tuning

**Status:** ❌ BLOCKED — Cannot run evals (GCP auth expired)  
**Branch:** `experiment/hypothesis-d-memory-tuning`  
**Baseline:** 76.8% agreement rate (late Feb 2026)

---

## Implementation Summary

### Changes Made

#### 1. Quality Scoring in Tolerance Pattern Retrieval (`src/data/memory.py`)

Added quality-based ranking instead of pure distance ranking:

```sql
WITH scored_patterns AS (
    SELECT
        ...,
        -- Quality score based on:
        -- 1. Number of cases (more = better)
        -- 2. Brand diversity (more brands = better generalization)
        -- 3. Embedding distance (closer = more relevant)
        (
            LOG(base.total_cases + 1) * 0.4 +
            LOG(base.unique_brands + 1) * 0.3 +
            (1 - distance) * 0.3
        ) as quality_score
    FROM VECTOR_SEARCH(...)
    WHERE distance <= @distance_threshold
)
SELECT ... FROM scored_patterns
ORDER BY quality_score DESC  -- Rank by quality, not just distance
LIMIT @top_k
```

**Rationale:** Patterns with more cases and brand diversity are more reliable than patterns with low distance but few examples.

#### 2. DBSCAN Clustering Tuning (`pipelines/memory/content_moderation/build_tolerance_patterns.py`)

```python
# Before (Hypothesis D):
CLUSTERING_EPS = 0.1
CLUSTERING_MIN_SAMPLES = 3

# After (Hypothesis D):
CLUSTERING_EPS = 0.15  # More permissive clustering
CLUSTERING_MIN_SAMPLES = 2  # Capture rare patterns
```

**Rationale:** 
- `eps=0.15` allows slightly more distant cases to cluster together (better generalization)
- `min_samples=2` prevents single-case clusters while still capturing rare patterns

---

## BigQuery Analysis (Before Changes)

```
+-----------------------------------------------------------------------+-----+-----------+
| guideline_archetype                                                   | cnt | avg_cases |
+-----------------------------------------------------------------------+-----+-----------+
| Garantir a precisão da mensagem chave {frase} em toda comunicação... |   1 |     138.0 |
| Assegurar a comunicação precisa, empregando a terminologia...        |   1 |     941.0 |
| Convidar a audiência, via CTA explícito, a {ação} na {plataforma}... |   1 |     450.0 |
| Ao mencionar {marca}, evite artigos femininos e use a forma...       |   1 |     333.0 |
| ... (21 unique archetypes total)                                      |     |           |
+-----------------------------------------------------------------------+-----+-----------+
```

- **21 unique archetypes** in tolerance_patterns table
- **Case counts range:** 24-941 per archetype (avg ~180)
- **Clustering output:** Each archetype has 1 pattern (suggests over-strict clustering)

---

## Expected Impact (from Eval Plan)

- **+1pp from better pattern matching:** Higher quality patterns → better calibration
- **+0.5pp from clustering improvements:** More comprehensive coverage
- **Total: +1.5pp expected** (76.8% → 78.3%)

---

## Blocker: GCP Authentication Expired

### Error:
```
google.auth.exceptions.RefreshError: Reauthentication is needed. 
Please run `gcloud auth application-default login` to reauthenticate.
```

### Root Cause:
The ADC credentials at `/root/.config/gcloud/legacy_credentials/caio.fonseca@brandlovers.ai/adc.json` have expired.

### Required Fix:
```bash
gcloud auth application-default login
# OR
# Provide fresh service account JSON key
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

---

## Next Steps (When Auth Fixed)

1. **Run 5 eval iterations:**
   ```bash
   cd /root/.openclaw/workspace/guardian-agents-api
   source .venv/bin/activate && source .env
   
   for i in {1..5}; do
     echo "=== RUN $i/5 ==="
     python evals/run_eval.py --config evals/content_moderation/eval.yaml --workers 4 \
       2>&1 | tee /tmp/hypothesis-d-run-$i.log
     
     # Extract agreement rate
     grep -E "mean_aggregate_score|exact_match.*mean" /tmp/hypothesis-d-run-$i.log
   done
   ```

2. **Analyze results:**
   - Calculate mean, std dev, min, max across 5 runs
   - Compare to 76.8% baseline
   - Require improvement in ≥4/5 runs for PR

3. **Open DRAFT PR if successful:**
   ```bash
   gh pr create --draft \
     --title "Hypothesis D: Memory Pipeline Tuning" \
     --body "$(cat hypothesis-d-results.md)" \
     --reviewer fonsecabc
   ```

---

## Commit Details

```
commit e133efe0cad4a2fc6d11c88ca54fd09bb6812506
Author: fonsecabc <caio.fonseca@brandlovrs.com>
Date:   Fri Mar 6 02:32:40 2026 +0000

    feat: hypothesis D — memory pipeline tuning with quality scoring
    
    - Add quality scoring to tolerance pattern retrieval (LOG(total_cases+1)*0.4 + LOG(unique_brands+1)*0.3 + (1-distance)*0.3)
    - Order patterns by quality_score DESC instead of just distance
    - Adjust DBSCAN clustering: eps 0.1→0.15, min_samples 3→2 for better generalization
```

**Files Changed:**
- `src/data/memory.py` (quality scoring in VECTOR_SEARCH query)
- `pipelines/memory/content_moderation/build_tolerance_patterns.py` (DBSCAN params)

---

## PR Requirements (from Caio 2026-03-06)

When opening PR after evals:

1. ✅ **Use `gh pr create --draft`**
2. ✅ **Reviewer: fonsecabc** (NOT manoel/juani)
3. ❌ **PR body must include:**
   - Exact agreement rate for EACH of the 5 runs
   - Mean, std dev, min, max
   - Delta vs baseline (76.8%) per run
   - Which specific test cases improved/regressed
   - Data-driven arguments for deployment
   - Before/after comparison of pattern retrieval quality

**Status:** Waiting for auth fix to collect eval metrics.
