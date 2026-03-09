# Hypothesis B Results — Archetype Standardization v2

**Branch:** `experiment/hypothesis-b-archetype-v2`  
**Commit:** `ebfb34f`  
**Status:** ❌ BLOCKED — Cannot run evals (GCP auth expired)

## Implementation Summary

Successfully implemented archetype standardization v2 as specified in `guardian-eval-plan.md`:

### Changes Made

1. **`src/data/memory.py`:**
   - Added `ARCHETYPE_TAXONOMY` dict with 13 granular categories
   - Added `archetype_filter` parameter to `get_tolerance_pattern()`
   - Updated SQL query to support archetype filtering with WHERE clause

2. **`src/agents/templates/content_moderation/general/severity_analysis.j2`:**
   - Added "D.1 ARQUÉTIPO DA DIRETRIZ" section
   - Includes archetype identification mapping (13 categories)
   - Instructions for 2x weight on matching archetypes
   - Calibration by historical tolerance
   - Anomaly detection guidance

### Code Quality
- ✅ All changes compile
- ✅ Follows existing patterns in memory.py
- ✅ Proper parameter passing (archetype_filter optional, backward compatible)
- ✅ SQL injection safe (uses parameterized queries)
- ✅ Prompt is clear and actionable

## Blocker: GCP Authentication

Cannot run eval runs due to expired GCP authentication:

```
google.auth.exceptions.RefreshError: Reauthentication is needed. 
Please run `gcloud auth application-default login` to reauthenticate.
```

### Required to Unblock

**Option 1:** Caio runs `gcloud auth application-default login` on this machine  
**Option 2:** Caio provides fresh service account JSON key and updates GOOGLE_APPLICATION_CREDENTIALS path

### Next Steps (After Auth Fixed)

1. Run 5 eval iterations:
   ```bash
   cd /root/.openclaw/workspace/guardian-agents-api
   for i in {1..5}; do
     bash -c "source .venv/bin/activate && source .env && python evals/run_eval.py --config evals/content_moderation/eval.yaml --workers 4" 2>&1 | tee /tmp/hypothesis-b-run-$i.log
   done
   ```

2. Extract metrics from each run:
   - Agreement rate (answer exact_match mean)
   - Total cases, successful, failed
   - Mean latency

3. Analyze per-case results:
   - Which test_idx improved vs baseline
   - Which test_idx regressed
   - Calculate mean, std dev, min, max across 5 runs

4. Create DRAFT PR with comprehensive results:
   ```bash
   gh pr create --draft \
     --title "Hypothesis B: Archetype Standardization v2" \
     --body "[full metrics report]" \
     --reviewer fonsecabc \
     --base main \
     --head experiment/hypothesis-b-archetype-v2
   ```

## Expected Impact (From Plan)

- +1pp from better pattern matching (more relevant tolerance patterns)
- +0.5pp from archetype-aware decisions
- **Total expected: +1.5pp** (target: 78.3% vs 76.8% baseline)

## PR Requirements (Caio's Spec)

The PR body must include:

1. **Per-run agreement rates:**
   - Run 1: X.X%
   - Run 2: X.X%
   - Run 3: X.X%
   - Run 4: X.X%
   - Run 5: X.X%

2. **Statistics:**
   - Mean: X.X%
   - Std dev: X.X%
   - Min: X.X%
   - Max: X.X%

3. **Delta vs baseline (76.8%):**
   - Per-run deltas
   - Mean delta

4. **Case-by-case analysis:**
   - test_idx that improved (list with before/after)
   - test_idx that regressed (list with before/after)
   - Explanation for regressions

5. **Data-driven deployment argument:**
   - Is improvement consistent (≥4/5 runs show gain)?
   - Are regressions acceptable?
   - Should this be deployed?

---

**Current blocker:** Cannot proceed past implementation without GCP auth.
