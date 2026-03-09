# GUA-1101 Complete Analysis & Improvement Backlog

**Date:** 2026-03-07
**Eval baseline:** run_20260308_015120 (main, 76.86%)
**GUA-1101 eval:** run_20260308_003327 (78.51%)
**Net improvement:** +1.65pp (+2 net cases)

---

## 1. Executive Summary

### What GUA-1101 Changed
GUA-1101 integrated **5 experimental hypotheses** into a single feature branch, plus added new infrastructure (LLM contest judge, shadow moderation pipeline, incremental eval saves). The core moderation improvement is **archetype-aware severity prompts with anti-error patterns** (CAI-336), which injects per-archetype failure-mode guidance into the severity analysis agent at runtime.

### +1.65pp Improvement Breakdown
- **Net:** 12 improvements − 10 regressions = +2 cases / +1.65pp
- **GENERAL_GUIDELINE:** +4.0pp (56→59/75) — archetype context helps color, benefit, and concept guidelines
- **TIME_CONSTRAINTS_GUIDELINE:** +3.8pp (19→20/26) — product timing detection improved
- **CAPTIONS_GUIDELINE:** **−10.0pp (18→16/20) — REGRESSION** — archetype injection over-strictifies captions

### Top 3 Wins
1. **GENERAL color/visual guidelines improved** — VISUAL_COLOR_PALETTE anti-error patterns correctly prevent false approvals on "must wear green/white/red" guidelines
2. **Time constraint product-detection improved** — 4 TIME_CONSTRAINTS cases flipped correct (show product in first N seconds)
3. **False negatives reduced** — FN count dropped from 15 → 13 (GUA-1101 less likely to over-reject valid content)

### Top 3 Remaining Issues
1. **CAPTIONS over-strictification** — anti-error patterns cause GUA-1101 to reject valid capitalization variations and present legal disclaimers; -10pp on captions
2. **TIME_CONSTRAINTS MUST_NOT_DO logic** — "don't show product in first X seconds" cases still confused; GUA-1101 treats absence as compliance instead of checking violation
3. **Exact phrase / OCR tolerance** — "BLACK20" vs "Black 20", legal texts not found in OCR → false negatives persist

---

## 2. Detailed Changes Analysis

### 2.1 Archetype-Aware Severity Prompts (CAI-336 / feat commit f7f94ad)

**What it does:**
Before calling the severity analysis agent, the service classifies each guideline into one of 34 archetypes using `archetype_utils.classify_guideline()`. The matched archetype's anti-error patterns are injected into the severity prompt as a dedicated block:

```
🔍 ARQUÉTIPO DA DIRETRIZ (PRÉ-IDENTIFICADO):
<archetype_id> | <description>
Anti-error patterns:
- Pattern 1
- Pattern 2
...
```

**34 archetypes defined**, all with 2–5 anti-error patterns (total: ~105 patterns).

**Key archetypes and their anti-error guidance:**

| Archetype | Anti-Error Patterns | Problem Addressed |
|-----------|--------------------|--------------------|
| VISUAL_COLOR_PALETTE | 5 patterns | Over-tolerance for competitor colors; "almost the color" still a violation |
| VERBAL_PHRASE_PRECISION | 5 patterns | Paraphrases don't count; exact word order; missing articles = violation |
| TEMPORAL_CTA_POSITION | 4 patterns | Time tool must be called; absence ≠ compliance |
| VERBAL_TERMINOLOGY_PROTECTION | 4 patterns | Generic terms become violations when competitor-specific |
| VERBAL_CTA_DIRECTION | 4 patterns | Partial paraphrase still a violation |

**Expected impact:** Reduce known false positive/negative patterns per archetype.

**Actual impact:** +4.0pp GENERAL, +3.8pp TIME_CONSTRAINTS, −10.0pp CAPTIONS.

---

### 2.2 BorderlineJudgeAgent (CAI-108 / feat/llm-judge-borderline-cai-108)

**What it does:**
A new Phase 3 agent reviews severity 2–4 decisions before returning results. It catches 7 specific error patterns:
- `THRESHOLD_TOO_STRICT` — rejecting within tolerance
- `SEMANTIC_PARAPHRASE_OK` — rejecting acceptable paraphrases
- `CONTEXT_MISUNDERSTOOD` — missing brand context
- `FALSE_DETECTION` — non-existent violations
- `TEMPORAL_ERROR` — miscalculated time constraints
- `BRAND_TOLERANCE_HIGHER` — stricter than brand's actual tolerance
- `NO_ERROR` — original decision correct

**Enabled via:** `settings.enable_judge_correction = True`
**Status in eval:** `enable_judge_correction = False` — **NOT active during eval runs** (0 corrections applied in all eval cases).

**Impact on eval:** Zero direct impact (disabled). Potential upside when enabled in production.

---

### 2.3 CorrectionAgent (Hypothesis C)

**What it does:**
A separate correction layer that can rewrite moderation decisions based on detected error types. Implemented as `correction_agent.py` with `correction.j2` template.

**Status:** Implemented but integrated into the judge pipeline; also disabled in eval via `enable_judge_correction = False`.

---

### 2.4 Memory Pipeline Improvements (GUA-1100 merge)

**Changes to `build_tolerance_patterns.py` and `build_error_patterns.py`:**
- Added `element_criticality` field to memory queries (prioritizes critical brand elements)
- Tighter distance threshold for memory retrieval (fewer but more relevant patterns)
- Taxonomy-aware generation: error patterns now use `archetype_utils.generate_archetype_with_taxonomy()` to ensure consistent archetype IDs across BigQuery and runtime
- MERGE deduplication to prevent duplicate patterns in BigQuery

**Impact:** More precise memory retrieval; anti-error patterns with consistent archetype IDs match the taxonomy used at runtime.

---

### 2.5 Shadow Moderation Pipeline

**New file:** `pipelines/analysis/batch_shadow_moderation.py` (685 lines)
**Purpose:** Runs moderation on historical data in shadow mode to validate changes before deployment.
**Impact on eval:** No direct impact; infrastructure for future validation.

---

### 2.6 LLM Contest Judge (feature/contest-llm-judge)

**New service:** `contest_judge_service.py`
**New models:** `models/contest_judge.py`
**Purpose:** When a creator contests a moderation decision, this LLM judge re-evaluates the case with additional context.
**Impact on eval:** None (separate service, not part of content moderation flow).

---

### 2.7 Severity 3 Boundary Tuning (experiment/severity-3-boundary-tuning)

**Changes:** Tightened "MUST_DO" severity-3 boundary to prevent approving partial compliance cases.
**Impact:** Contributes to reduced FN count (15→13).

---

## 3. Eval Comparison

### 3.1 Overall Stats

| Metric | Main | GUA-1101 | Delta |
|--------|------|----------|-------|
| Accuracy | 93/121 (76.86%) | 95/121 (78.51%) | +1.65pp |
| False Positives (approve when should reject) | 13 | 13 | 0 |
| False Negatives (reject when should approve) | 15 | 13 | **-2** |

### 3.2 Per-Classification (properly matched by URI+guideline)

| Classification | Main | GUA-1101 | Delta |
|----------------|------|----------|-------|
| GENERAL_GUIDELINE (75 cases) | 56/75 (74.7%) | 59/75 (78.7%) | **+4.0pp** |
| TIME_CONSTRAINTS_GUIDELINE (26 cases) | 19/26 (73.1%) | 20/26 (76.9%) | **+3.8pp** |
| CAPTIONS_GUIDELINE (20 cases) | 18/20 (90.0%) | 16/20 (80.0%) | **−10.0pp** |

### 3.3 Improvements (12 cases: wrong→correct)

| Case | Classification | Guideline | Gold |
|------|---------------|-----------|------|
| g:6 | GENERAL | BrandLovers es una app/plataforma | True |
| g:114 | GENERAL | granola São Braz é gostosa, crocante e versátil | False |
| g:24 | GENERAL | CTA: "Acesse www.tesourodireto.com.br/cashback" | True |
| g:93 | GENERAL | Sérum Colágeno 16 é estimulador tópico (not bioestimulador) | False |
| g:15 | GENERAL | Mostrar resultado depois da aplicação (MUST_NOT_DO) | False |
| g:34 | GENERAL | Cor branca ou vermelha (color violation correctly detected) | False |
| g:16 | GENERAL | Peça principal deve ser verde | True |
| g:94 | TIME | Show products in first 10 seconds | True |
| g:73 | TIME | Insert product in first 6 seconds | True |
| g:112 | TIME | Show product in first 15 seconds | True |
| g:12 | TIME | Mostrar e mencionar marca nos primeiros 10s | True |
| g:79 | GENERAL | Estimulador de colágeno, não bioestimulador | False |

**Pattern:** Improvements concentrated in (1) color/visual guidelines where new anti-error patterns enforce strict checking, and (2) MUST_DO time constraints where product detection is improved.

### 3.4 Regressions (10 cases: correct→wrong)

| Case | Classification | Guideline | Gold | Issue |
|------|---------------|-----------|------|-------|
| g:33 | TIME | Não falar/mostrar produto nos primeiros 15s | False | MUST_NOT_DO: absence treated as compliance |
| g:40 | GENERAL | Mostrar embalagem L'Oréal durante aplicação | True | Visual detection FN (embalagem not found) |
| g:18 | GENERAL | Peça principal branca ou vermelha | True | Strawberry costume FP (wrong color detection) |
| g:60 | GENERAL | Não usar vermelho, uniformes esportivos | True | Over-strict on costume elements |
| g:22 | TIME | Não mostrar produto nos primeiros 10s | False | MUST_NOT_DO: absence treated as compliance |
| g:107 | GENERAL | Usar artigo 'A' antes de 'C&A' | False | Anti-error patterns cause over-rejection |
| g:90 | GENERAL | Fale exatamente "Use o cupom BLACK20" | False | "Black 20" vs "BLACK20" — wrong strictness direction |
| g:8 | CAPTIONS | TIM e TIM ULTRAFIBRA em maiúsculas | True | Capitalization over-strictification |
| g:84 | CAPTIONS | Texto legal "*Promoção válida até 15/03/2026" | True | Legal disclaimer not found in OCR |
| g:21 | TIME | Mostrar Point Tap e Mercado Pago nos primeiros 10s | False | MUST_DO applied to MUST_NOT_DO context |

**Regression patterns:**
1. **CAPTIONS over-strict (2 cases):** Anti-error patterns make agent too strict on capitalization variants and legal text OCR
2. **COLOR PALETTE wrong direction (2 cases):** "Must wear X color" cases regressed — anti-patterns for "competitor color avoidance" interfere with "required color compliance"
3. **TIME MUST_NOT_DO confusion (3 cases):** Agent treats absence of violation as compliance (e.g., "didn't find product, so it wasn't shown") — logic inverted
4. **Exact phrase over-rejection (1 case):** Anti-patterns for VERBAL_PHRASE_PRECISION cause GUA-1101 to reject "Black 20" ≠ "BLACK20" even when gold=False (should reject but for wrong reason)

### 3.5 Persistently Wrong Cases (16)

Notable patterns in cases still failing both runs:
- **Exact phrase tolerance:** "Use o cupom BLACK20" vs audio transcription (2 cases, g:43 and g:90)
- **C&A feminine article:** "C&A" vs "A C&A" — model uncertain (2 cases)
- **GOL brand communication:** Abstract concept guidelines difficult to evaluate (1 case)
- **Color restriction (Volkswagen orange/yellow):** GUA-1101 still doesn't catch these (1 case)
- **TIME_CONSTRAINTS complex:** Mercado Livre logo in first 10s — logo detection fails
- **CAPTIONS with legal**: Partial text detection issues (2 cases)

---

## 4. Improvement Backlog (Ranked)

---

### P0 — Fix CAPTIONS regression

**Priority:** P0 (regression, -10pp on captions)
**Problem:** Archetype injection with VERBAL_PHRASE_PRECISION and CONTENT_EXACT_RENDITION anti-error patterns makes the agent too strict on captions, causing it to reject:
- Minor capitalization variants ("Tim" instead of "TIM") that tolerance patterns previously allowed
- Legal text not perfectly matching OCR (small spacing/punctuation differences)

**Hypothesis:**
1. Add captions-specific anti-error pattern: "OCR may miss punctuation/spacing — match by key terms, not exact string"
2. Add archetype `CAPTIONS_FORMATTING` with lenient tolerance patterns: "Case variations in brand names acceptable unless critical term"
3. OR: Exclude CAPTIONS_GUIDELINE from archetype injection (anti-error patterns designed for GENERAL/VERBAL hurt captions)

**Expected impact:** +10pp on CAPTIONS = +1.65pp overall
**Archetypes affected:** CAPTIONS_GUIDELINE routing
**Effort:** S

---

### P0 — Fix TIME_CONSTRAINTS MUST_NOT_DO logic

**Priority:** P0 (3 regressions, affects all "don't show X in first N seconds" guidelines)
**Problem:** For MUST_NOT_DO time constraints ("don't show product in first 15s"), the agent:
- Calls `_compare_time_constraint_with_severity` with `event_found=False`
- Treats absence as "compliant" even when absence is the DESIRED state
- Logic inverted: should be "if not found, check if that's the requirement"

**Hypothesis:**
Add explicit anti-error pattern to TEMPORAL_CTA_POSITION archetype:
```
"MUST_NOT_DO temporal: if event was NOT found, the guideline IS violated (creator should have
avoided it but it appeared). If product appears at any time in first N seconds → violation.
Distinguish: MUST_DO (must happen before T) vs MUST_NOT_DO (must NOT happen before T)."
```
Also add a routing guard: detect `MUST_NOT_DO` in guideline text and inject specific instruction.

**Expected impact:** Fix 3 cases (+2.5pp)
**Archetypes affected:** TEMPORAL_CTA_POSITION, TIME_CONSTRAINTS_GUIDELINE routing
**Effort:** S

---

### P1 — Fix color MUST_DO vs MUST_NOT_DO confusion

**Priority:** P1 (2 regressions on color guidelines)
**Problem:** VISUAL_COLOR_PALETTE anti-error patterns are designed for "don't wear competitor colors" but the archetype is also matched for "must wear color X". The strict anti-patterns ("partial compliance still a violation") cause the agent to reject compliant content:
- Case g:18: "must wear white or red" → strawberry costume rejected as MUST_NOT_DO violation instead of evaluated as MUST_DO compliance
- Case g:60: "don't wear red" → agent over-strictified on other costume elements

**Hypothesis:**
Split VISUAL_COLOR_PALETTE archetype into:
- `VISUAL_COLOR_AVOIDANCE` (MUST_NOT_DO): anti-patterns for competitor exclusion
- `VISUAL_COLOR_REQUIREMENT` (MUST_DO): different guidance; "check if main garment matches"

**Expected impact:** Fix 2 cases (+1.65pp)
**Archetypes affected:** VISUAL_COLOR_PALETTE
**Effort:** M

---

### P1 — Improve exact phrase / brand code tolerance

**Priority:** P1 (2+ persistent failures)
**Problem:** "Use o cupom BLACK20" — audio transcription yields "Black 20" (with space) or similar variants. `_compare_semantic_cta_similarity` scores 92% but agent now rejects due to VERBAL_PHRASE_PRECISION anti-pattern "code/number must appear literally". This is correct for coupon codes, but the tolerance tool threshold needs calibration.

**Hypothesis:**
Add to VERBAL_PHRASE_PRECISION anti-error patterns:
```
"Brand promo codes: spaces within codes are irrelevant ('BLACK20' = 'BLACK 20' = 'black20').
Number sequences must match exactly but case/spacing differences in alpha-codes are OK."
```
Also: Tune `_compare_semantic_cta_similarity` to return a "code match" flag separately.

**Expected impact:** Fix 1-2 persistent cases (+0.8-1.6pp)
**Archetypes affected:** VERBAL_PHRASE_PRECISION, CONTENT_EXACT_RENDITION
**Effort:** S

---

### P1 — Enable BorderlineJudgeAgent in eval

**Priority:** P1 (0 corrections applied in current eval — agent disabled)
**Problem:** The BorderlineJudgeAgent was built to catch THRESHOLD_TOO_STRICT, SEMANTIC_PARAPHRASE_OK, FALSE_DETECTION errors but was disabled (`enable_judge_correction = False`) during the GUA-1101 eval run.

**Hypothesis:**
Enable the judge agent for borderline (severity 2-4) cases and re-run eval. Expected to:
- Catch 2-4 THRESHOLD_TOO_STRICT regressions (g:18, g:60 color cases)
- Catch FALSE_DETECTION regressions (g:40 embalagem case)

**Expected impact:** +2-4 cases (+1.65-3.3pp) if judge catches regressions
**Effort:** S (toggle flag, run eval)

---

### P1 — Fix L'Oréal embalagem detection (visual FN)

**Priority:** P1 (persistent regression g:40)
**Problem:** "Mostrar a embalagem da máscara L'Oréal Professionnel durante a aplicação" — gold=True but GUA-1101 says False. The visual description agent describes the product but the severity agent fails to connect "mask application scene" with "embalagem present".

**Hypothesis:**
The VISUAL_PACKAGING_DISPLAY archetype anti-error patterns need:
```
"'During application' includes scenes where product is visible but not center-frame.
If mascara/cream/product is being used, the packaging must have been shown at some point —
check full timeline, not just frames where it's the main object."
```

**Expected impact:** Fix 1 case (+0.83pp)
**Archetypes affected:** VISUAL_PACKAGING_DISPLAY, VISUAL_PRODUCT_DEMONSTRATION
**Effort:** S

---

### P2 — Improve C&A feminine article detection

**Priority:** P2 (2 cases, g:107 regression + g:2 persistent failure)
**Problem:** "Sempre que mencionar a C&A, utilizar o artigo feminino 'A' antes do nome da marca" — model oscillates between approving/rejecting. Both "C&A" and "A C&A" appear in transcriptions and the model can't consistently determine if the article was used.

**Hypothesis:**
Add specific anti-error pattern to VERBAL_TERMINOLOGY_PROTECTION:
```
"Article + brand name: 'A C&A' requires 'A' to appear IMMEDIATELY before 'C&A' in EVERY mention.
Check each individual mention in audio transcript. One missing article = violation."
```
Also add `_compare_semantic_cta_similarity` call for article validation specifically.

**Expected impact:** Fix 1-2 cases (+0.83-1.65pp)
**Effort:** S

---

### P2 — Legal text / disclaimer OCR improvement

**Priority:** P2 (2 captions cases persistent)
**Problem:** Legal disclaimer text like "*Promoção válida até 15/03/2026. Confira as condições completas em Loja" is present in the video but not reliably detected by the visual description agent. OCR misses small-print text or truncates.

**Hypothesis:**
1. In REGULATORY_DISCLAIMER archetype anti-error patterns, add: "If legal text is partially visible in timeline but not fully transcribed by OCR, use partial match on key date/percentage values"
2. Or: Add a dedicated `_verify_caption_text` tool that does fuzzy substring match instead of exact match

**Expected impact:** Fix 1-2 captions cases (+0.83-1.65pp)
**Effort:** M

---

### P2 — Mercado Livre logo detection (TIME_CONSTRAINTS)

**Priority:** P2 (persistent failure g:109)
**Problem:** "Não exibir a logo do Mercado Livre nos 10 primeiros segundos" — GUA-1101 fails to detect the logo presence/absence in early frames.

**Hypothesis:**
Improve visual description prompt to specifically call out logo detection in first-frame timeline events. Add to VISUAL_BRAND_IDENTITY archetype: "Logo visibility requires checking ALL frames 0-10s systematically, not just main events".

**Expected impact:** Fix 1 case (+0.83pp)
**Effort:** M

---

## 5. Priority Summary

| Priority | Task | Expected Impact | Effort |
|----------|------|----------------|--------|
| P0 | Fix CAPTIONS regression (anti-error over-strictification) | +10pp captions / +1.65pp overall | S |
| P0 | Fix TIME_CONSTRAINTS MUST_NOT_DO logic | +2.5pp | S |
| P1 | Split VISUAL_COLOR_PALETTE into MUST_DO/MUST_NOT_DO | +1.65pp | M |
| P1 | Enable BorderlineJudgeAgent in eval | +1.65-3.3pp | S |
| P1 | Fix exact phrase / brand code tolerance | +0.8-1.6pp | S |
| P1 | Fix visual packaging/application FN (L'Oréal) | +0.83pp | S |
| P2 | C&A feminine article consistency | +0.83-1.65pp | S |
| P2 | Legal text OCR fuzzy match | +0.83-1.65pp | M |
| P2 | Mercado Livre logo detection | +0.83pp | M |

**Cumulative if P0+P1 addressed:** ~+8pp potential → estimated 85-87% accuracy range

---

## Appendix: Branch Structure

### Commits in feat/GUA-1101 (not in main)
```
f7f94ad feat(GUA-1101): archetype-aware severity prompts with anti-error patterns  ← MAIN CHANGE
ca7de80 Merge: feature/contest-llm-judge
9e8ea29 Merge: feat/llm-judge-borderline-cai-108
12a2c9d Merge: experiment/hypothesis-c-llm-judge
60c99f3 Merge: experiment/hypothesis-b-archetype-v2
88014d3 Merge: experiment/hypothesis-a-prompt-engineering
679f8c4 feat: Phase 2 model configuration improvements
d56fdc5 feat: shadow moderation pipeline + Makefile
aa29388 Merge: experiment/severity-3-boundary-tuning
3c61c32 feat(memory): retrieval and build improvements
0ec3375 feat: BorderlineJudgeAgent for severity 2-4 (CAI-108)
927db85 feat: tune severity 3 boundary
[...GUA-1100 commits for archetype_utils, BigQuery schema...]
```

### Files Changed (29 files, +4936/−232 lines)
- **Core moderation:** `severity_analysis.j2`, `content_moderation_service.py`, `borderline_judge_agent.py`, `correction_agent.py`
- **Memory pipelines:** `archetype_taxonomy.json` (34 archetypes), `archetype_utils.py`, `build_error_patterns.py`, `build_tolerance_patterns.py`
- **New templates:** `borderline_judge.j2`, `correction.j2`
- **New infrastructure:** `contest_judge_service.py`, `batch_shadow_moderation.py`, `validate_contest_judge.py`
- **Eval improvements:** Incremental saves, crash resilience
