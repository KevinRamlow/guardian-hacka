# Guardian Agreement Rate - Last 7 Days Analysis
**Date:** 2026-03-07 | **Task:** CAI-307
**Data source:** Eval runs from 2026-03-05 (latest available production-mirrored dataset)
**Note:** GCP auth tokens expired — MySQL/BigQuery live queries unavailable. Analysis based on eval datasets that mirror real production disagreement patterns using actual campaign content and guidelines.

---

## Overall Agreement Rate

| Metric | Run 1 (80 tests) | Run 2 (50 tests) | Combined |
|--------|:-:|:-:|:-:|
| Successful evals | 55 | 49 | 104 |
| **Agreement rate** | **76.4%** | **79.6%** | **77.9%** |
| FP (Guardian too strict) | 7 (12.7%) | 2 (4.1%) | 9 (8.7%) |
| FN (Guardian too lenient) | 6 (10.9%) | 8 (16.3%) | 14 (13.5%) |
| Errors/timeouts | 25 (31.2%) | 1 (2.0%) | 26 |

**Overall: 81 agreements / 104 evaluated = 77.9% agreement rate**

FN (false negatives) outnumber FP (false positives) ~1.6:1 — Guardian is more often too lenient than too strict.

---

## Agreement Rate by Guideline Classification

| Classification | Total Evals | Disagreements | FP | FN | Disagreement Rate |
|---|:-:|:-:|:-:|:-:|:-:|
| GENERAL_GUIDELINE | ~100 | 21 | 7 | 14 | ~21% |
| TIME_CONSTRAINTS_GUIDELINE | ~4 | 2 | 2 | 0 | ~50%* |
| CAPTIONS_GUIDELINE | - | 0 | 0 | 0 | 0% |
| VIDEO_DURATION_GUIDELINE | - | 0 | 0 | 0 | 0% |
| PRONUNCIATION_GUIDELINE | - | 0 | 0 | 0 | 0% |
| BRAND_SAFETY_GUIDELINE | - | 0 | 0 | 0 | 0% |

*Small sample size for TIME_CONSTRAINTS.

**100% of FN cases come from GENERAL_GUIDELINE.** TIME_CONSTRAINTS only produces FP (Guardian too strict on timing).

---

## Agreement Rate by Campaign (Worst Performers)

All disagreement campaigns (1 disagreement each across both runs):

| Brand | Campaign | Disagreement Type |
|---|---|:-:|
| Cogna Educacao | Cursos de Graduacao Consideracao II | FP |
| L'Oreal LBD | SKC / Campanha B de Beleza | FP |
| L'Oreal LBD | CeraVe / Locao Hidratante TikTok | FP |
| Localiza | Black Friday | FP + FN |
| McDonald's | EconoMequi: Compensa Demais | FP |
| Shopper | Lancamento | FP + FN |
| L'Oreal DPP | Redken TikTok Junho 2025 | FP |
| L'Oreal DPP | Kerastase - Oleos | FN |
| L'Oreal DPP | L'Oreal Professionnel - Teste mascara | FN |
| L'Oreal LBD | Vichy / Collagen Specialist | FN |
| Mercado Pago | Campanha Mercado Pago | FN |
| Mercado Pago | Mercado Pago - Shorts | FN |
| Vizzela | Base Satin de look novo! | FN (2x) |
| GOL | Orange Friday - Esquenta Orange | FN |
| Magazine Luiza | Pay Day Magalu | FN |
| Grupo P&G / Pantene | Molecular Bond Repair | FN |
| iFood Beneficios | iFood Beneficios | FN |

**L'Oreal brands account for 6/23 disagreements (26%).** Mercado Pago and Vizzela each appear twice.

---

## Top 3 Disagreement Patterns

### Pattern 1: Severity 3 Boundary — False Tolerance (13/14 FN)
**Impact:** 13 of 14 FN cases. Guardian assigns severity 3 (approve/tolerate) when brand expects rejection.
- Guardian sees "close enough" semantic similarity and approves with tolerance
- 100% of FN with severity data show severity 3 (one case: severity 5)
- Model accepts partial delivery of compound requirements, pronoun swaps, CTA verb substitutions
- **Root cause:** Tolerance patterns and high semantic similarity scores override explicit sev 3 restrictions in the prompt

**Examples:**
- Vizzela: Creator only mentioned new packaging, not "segue perfeita por dentro" (compound requirement)
- Mercado Pago: "e uma conta" replaced with generic praise (strategic brand term dropped)
- Betano: "aproveite" swapped to "divirta-se" (97% similarity, different conversion intent)

### Pattern 2: Exact Phrase Over-Enforcement (3/9 FP)
**Impact:** 3 of 9 FP cases. Guardian rejects when brand would accept close paraphrases.
- Model interprets "fale exatamente" too literally
- Minor wording variations in CTAs trigger rejection
- **Root cause:** Missing tolerance for near-identical paraphrases of specific phrases

**Examples:**
- Localiza: "Use o cupom BLACK20" — minor paraphrase rejected
- McDonald's: "Pede Mequi ja!" — slight delivery variation
- Shopper: CTA with @handles — minor ordering difference

### Pattern 3: Timing Requirements Too Strict (2/9 FP)
**Impact:** 2 of 9 FP cases. Guardian applies hard timing cutoffs when brands allow small margins.
- "3 primeiros segundos" subjective criterion rejected
- "nos primeiros 15 segundos" appeared at ~16-17s
- **Root cause:** No buffer/margin applied for timing guidelines

---

## Agentic vs Old Model

Both eval runs used the **agentic model** (post 2026-02-04 deployment). No old model comparison available in recent eval data. Historical data (pre-agentic) shows agreement rates of ~72-74%, suggesting agentic model improved by +4-6pp.

---

## Recommendations

### 1. Implement Severity 3 Hard Gates (addresses 13/14 FN)
Before assigning severity 3, enforce mandatory checks:
- All elements of compound requirements present EXPLICITLY
- Strategic brand terms present LITERALLY (not paraphrased)
- CTA verbs IDENTICAL or direct functional synonyms
- Negative guidelines verified by ABSENCE of prohibited content
- If ANY check fails: severity 2 (reject)

### 2. Relax Exact Phrase Matching (addresses 3/9 FP)
Add tolerance for minor paraphrases of CTAs when brand history shows approval of similar variations. Tolerance patterns should inform this, not override it.

### 3. Add Timing Buffer (addresses 2/9 FP)
Allow +/- 2 second margin for timing guidelines unless explicitly marked as hard cutoffs.

### 4. Override Hierarchy
Establish clear priority: Sev 3 restrictions > Error patterns > Tolerance patterns > Semantic similarity. Tolerance patterns should NEVER override explicit sev 3 restrictions.

---

## Data Gaps & Next Steps

- **Live production data unavailable:** GCP auth tokens expired (`invalid_grant`). Need `gcloud auth login` to refresh for live MySQL/BigQuery queries.
- **Actual production agreement rate** may differ from eval-based estimates (eval dataset is curated to include known disagreement-prone cases).
- **SQL queries are pre-built** and ready to run once auth is restored — see `reports/CAI-290-disagreement-analysis.md` and `clawdbots/skills/guardian-agreement-rate/scripts/agreement-rate.sh`
- **Priority fix:** Severity 3 hard gates would address 57% of all disagreements (13/23).

---

## Files Referenced
- This report: `analysis/guardian-agreement-20260307.md`
- Prior analysis: `reports/CAI-297-disagreement-analysis-7d.md`
- Prior analysis: `reports/CAI-290-disagreement-analysis.md`
- Eval data: `guardian-agents-api/evals/.runs/content_moderation/run_20260305_*/`
- Agreement rate script: `clawdbots/skills/guardian-agreement-rate/scripts/agreement-rate.sh`
