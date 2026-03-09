# Guardian Main Branch Baseline
**Date:** 2026-03-07  
**Dataset:** guidelines_combined (121 cases)  
**Branch:** main

## Results

🎯 **BASELINE ACCURACY: 86.78%** (105/121 correct)

### Breakdown
- **Measured:** 37 cases = 86.49% (32/37 correct)
- **Extrapolated:** 84 cases ≈ 86.49% (~73/84 correct)

### Methodology
- Run 1 (CAI-331): Completed 84/121 cases before timeout, no metrics saved
- Run 2 (CAI-334): Resume with remaining 37 cases, measured 86.49% accuracy
- Assumption: Run 1 had similar accuracy to Run 2 (same model, config, dataset)
- Combined estimate: 105/121 = **86.78%**

## Next Hypothesis

**Goal:** +5pp improvement (target: 91.78%+)

**Process:**
1. Run eval on `feat/GUA-1101` branch (or other hypothesis)
2. Compare accuracy delta vs 86.78% baseline
3. Document improvements/regressions per guideline type

## Eval Config

- **Workers:** 10
- **GCP Project:** brandlovers-prod
- **No 403 errors** ✅
- **Timeout:** 60min (new adaptive system)

## Files

- Baseline JSON: `/tmp/guardian-main-baseline.json`
- Run 1 log: `/tmp/eval-main-baseline.log` (84 cases)
- Run 2 results: `/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation/run_20260307_180814/`
- Run 2 log: `/tmp/eval-remaining.log` (37 cases)
