# Guardian Agreement Rate — Last 7 Days (LIVE PRODUCTION DATA)
**Period:** 2026-02-28 to 2026-03-07 | **Task:** CAI-307 | **Generated:** 2026-03-07
**Data source:** Live MySQL (db-maestro-prod) — proofread_medias + actions tables

---

## Overall Metrics

| Metric | Value |
|--------|-------|
| Total proofreads | 790 |
| With brand decision | 401 |
| **Agreement rate** | **43.4%** (174/401) |
| False Negatives (Guardian rejected, Brand approved) | 211 (52.6%) |
| False Positives (Guardian approved, Brand refused) | 16 (4.0%) |

> **Critical finding:** Guardian is massively over-rejecting. 211 FNs vs only 16 FPs — the model is far too strict on production data compared to eval performance (~78%).

---

## Agentic vs Old Model

| Model | Total | Agreements | Rate | FP | FN |
|-------|-------|------------|------|----|----|
| **Agentic** | 188 | 100 | **53.2%** | 10 | 78 |
| Old model | 213 | 74 | **34.7%** | 6 | 133 |

Agentic model outperforms old model by **+18.5pp**. Old model still handles 53% of reviewed volume.

---

## Daily Trend

| Day | Total | Agreements | Rate | FN | FP |
|-----|-------|------------|------|----|-----|
| 02-28 | 13 | 7 | 53.8% | 5 | 1 |
| 03-01 | 31 | 10 | 32.3% | 21 | 0 |
| 03-02 | 76 | 25 | 32.9% | 51 | 0 |
| 03-03 | 49 | 15 | 30.6% | 33 | 1 |
| 03-04 | 46 | 17 | 37.0% | 26 | 3 |
| 03-05 | 98 | 42 | 42.9% | 50 | 6 |
| 03-06 | 76 | 46 | **60.5%** | 25 | 5 |
| 03-07 | 12 | 12 | 100.0%* | 0 | 0 |

*03-07 incomplete (early data). Positive trend: rate improved from ~31% (03-01 to 03-03) to **60.5%** (03-06).

---

## Agreement Rate by Brand

| Brand | Total | Rate | FN | FP |
|-------|-------|------|----|----|
| Renault | 126 | 44.4% | 62 | 8 |
| McDonald's | 90 | 37.8% | 56 | 0 |
| PagBank | 46 | 41.3% | 26 | 1 |
| Mercado Livre | 45 | 48.9% | 22 | 1 |
| Nuvemshop | 39 | 64.1% | 10 | 4 |
| Sprite | 16 | 18.8% | 13 | 0 |
| L'Oreal CDMO | 13 | 30.8% | 9 | 0 |
| Claro | 8 | 50.0% | 2 | 2 |
| Magazine Luiza | 7 | 28.6% | 5 | 0 |
| BrandLovers | 6 | 0.0% | 6 | 0 |

Worst: BrandLovers (0%), Sprite (18.8%), Magazine Luiza (28.6%), L'Oreal (30.8%).

---

## Top 3 Disagreement Patterns

### Pattern 1: Guidelines Over-Rejection (97.6% of all FNs)

- **206 of 211 FN** cases: `is_guidelines_approved = 0`, but `is_audio_quality_approved = 1` and `is_safe = 1`
- Content passes audio quality and brand safety checks, but fails guideline compliance
- Brands approve this content anyway — Guardian's guideline strictness is the primary driver of disagreements
- Only 3 FN cases had guidelines approved (edge cases), 2 had safety issues

### Pattern 2: High-Adherence Rejections (55.5% of FNs)

- **117 FN cases** have adherence scores between 80-89%
- Content meets 80%+ of guidelines but fails on 1-2 items → Guardian rejects
- Brands consider 80%+ adherence acceptable — tolerance mismatch
- Adherence breakdown of FNs:
  - <50%: 9 cases (4.3%)
  - 50-69%: 34 cases (16.1%)
  - 70-79%: 48 cases (22.7%)
  - **80-89%: 117 cases (55.5%)**
  - 90-100%: 3 cases (1.4%)

### Pattern 3: Renault + McDonald's Dominate (55.9% of all FNs)

- **Renault:** 62 FN (29.4% of all FNs) — "Boreal Fevereiro" campaign
- **McDonald's:** 56 FN (26.5% of all FNs) — "Economequi Março" campaign
- These two campaigns account for **118/211 FNs**
- Both are high-volume campaigns with lenient brands that need stronger tolerance patterns

---

## Eval vs Production Gap

| Metric | Eval (03-05) | Production (7d) |
|--------|-------------|-----------------|
| Agreement rate | 77.9% | 43.4% |
| FP rate | 8.7% | 4.0% |
| FN rate | 13.5% | 52.6% |

Production FN rate is **~4x higher** than eval. This suggests:
1. Eval dataset is not representative of production distribution (over-indexes on clear cases)
2. Production campaigns have more lenient brands than eval captures
3. Tolerance patterns in eval may not reflect actual brand behavior

---

## Recommendations

### 1. Raise approval threshold for 80%+ adherence content
117 FNs (55.5%) have adherence 80-89%. Content scoring 80%+ with only 1 guideline miss should default to severity 3 (approved/tolerated), not rejected. This single change could eliminate ~55% of FNs.

### 2. Feed Renault & McDonald's tolerance patterns urgently
These two brands alone cause 56% of FNs. Ingest their recent approval history into tolerance memory pipeline to calibrate Guardian's strictness for these brands.

### 3. Accelerate agentic model migration
Agentic at 53.2% vs old model at 34.7%. Migrating remaining old-model campaigns to agentic would lift overall rate by an estimated +8-10pp.

### 4. Fix eval representativeness
Production agreement rate (43.4%) is 34pp below eval rate (77.9%). Eval dataset needs rebalancing with more high-adherence borderline cases that match production distribution.

### 5. Investigate Sprite & L'Oreal campaigns
Sprite (18.8%) and L'Oreal (30.8%) have very low agreement rates — likely missing tolerance patterns or miscalibrated guidelines.
