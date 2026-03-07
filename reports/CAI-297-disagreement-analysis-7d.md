# CAI-297: Guardian Moderation Disagreements — Last 7 Days Analysis
**Date:** 2026-03-07 | **Data source:** Eval runs from 2026-03-05 (latest available)
**Note:** GCP auth tokens expired — MySQL/BigQuery live queries unavailable. Analysis uses eval dataset which mirrors production disagreement patterns.

## Executive Summary

| Metric | Run 20260305_202641 (80 tests) | Run 20260305_143139 (50 tests) |
|--------|-------------------------------|-------------------------------|
| **Successful evals** | 55 | 49 |
| **Agreement rate** | 76.4% | 79.6% |
| **FP (Guardian too strict)** | 7 (12.7%) | 2 (4.1%) |
| **FN (Guardian too lenient)** | 6 (10.9%) | 8 (16.3%) |
| **Errors** | 25 (31.2%) | 1 (2.0%) |

**Key finding:** FN (false negatives = Guardian approves, brand rejects) dominate disagreements. **11 out of 12 unique FN cases are at severity 3 boundary** — Guardian assigns sev 3 (approve with tolerance) when the brand expects rejection.

## Disagreement Breakdown by Classification

| Classification | FP | FN | Total |
|---------------|----|----|-------|
| GENERAL_GUIDELINE | 7 | 14 | 21 |
| TIME_CONSTRAINTS_GUIDELINE | 2 | 0 | 2 |
| **Total** | **9** | **14** | **23** |

100% of FN cases are GENERAL_GUIDELINE. TIME_CONSTRAINTS only causes FP (Guardian too strict on timing).

## Top FN Patterns (Guardian Too Lenient — Severity 3 Boundary)

### Pattern 1: Compound Requirements — Partial Compliance (3 cases)
- **Vizzela**: "mudou embalagem, MAS segue perfeita por dentro" — creator only mentioned new packaging
- **L'Oreal Professionnel**: "durante a aplicação" — product shown during preparation, not actual application
- **Pantene**: "chamando seguidores para experimentar a linha" — CTA paraphrased too loosely
- **Root cause**: Model accepts partial delivery of compound requirements as sev 3

### Pattern 2: Strategic Brand Terms Substituted (3 cases)
- **Mercado Pago** (2x): "é uma conta" replaced with generic praise; brand positioning term dropped
- **Mercafé**: "Chegou o SEU momento" → "Chegou o MEU momento" — pronoun swap changes beneficiary
- **Root cause**: Model treats brand-specific positioning as paraphrasable at high semantic similarity

### Pattern 3: CTA Verb/Intent Swap (2 cases)
- **Betano**: "aproveite" → "divirta-se" (97% similarity, different conversion intent)
- **GOL**: "parceira ideal para realizar o sonho" → paraphrased to lose specificity
- **Root cause**: High similarity score overrides verb-level analysis

### Pattern 4: Implicit vs Explicit Compliance (2 cases)
- **L'Oréal Vichy**: "estimulador de colágeno tópico, não bioestimulador" — distinction not made explicitly
- **iFood**: "Não utilizar VR/VA" — terms implicitly referenced
- **Root cause**: Model infers compliance from context rather than requiring explicit mention

### Pattern 5: Negative Guideline Violations (2 cases)
- **Mercado Pago**: "Não mencionar conta digital" — mentioned anyway, model scored sev 5 (approved)
- **Magazine Luiza**: "Não usar roupas laranja/amarela/vermelha" — violation not caught
- **Root cause**: Negative guidelines ("don't do X") harder for model to enforce

## Top FP Patterns (Guardian Too Strict)

### Pattern 1: Exact Phrase Requirements Over-Enforced (3 cases)
- **Localiza**: "Use o cupom BLACK20..." — minor paraphrase rejected
- **McDonald's**: "Pede Méqui já!" — slight variation in delivery
- **Shopper**: CTA with specific @handles — minor ordering/wording difference
- **Root cause**: Model takes "fale exatamente" too literally when brand would accept close paraphrases

### Pattern 2: Timing Requirements Too Strict (2 cases)
- **Cogna**: "3 primeiros segundos devem captar atenção" — subjective criterion rejected
- **L'Oréal SKC**: "nos primeiros 15 segundos" — appeared at ~16-17s
- **Root cause**: Model applies hard timing cutoffs when brands allow small margins

### Pattern 3: Visual Demonstration Ambiguity (2 cases)
- **CeraVe**: "Inicie com close-up da textura" — framing slightly different
- **Redken**: "Demonstre como One United contribui" — demonstration present but indirect
- **Root cause**: Visual guidelines have subjective interpretation

## Recommendations

### 1. HARD GATES for Severity 3 Assignment (addresses 11/12 FN)
```
ANTES de atribuir Severidade 3, VERIFIQUE:
[ ] Todos os elementos de requisito composto presentes EXPLICITAMENTE?
[ ] Termo estratégico de marca presente LITERALMENTE?
[ ] Pronomes/sujeito IDÊNTICOS ao da diretriz?
[ ] Verbo de CTA IDÊNTICO ou sinônimo direto funcional?
[ ] Diretrizes negativas ("não fazer X") verificadas por ausência?
Se QUALQUER check falhar → Sev 2 (answer: false).
```

### 2. Override Hierarchy (addresses tolerance pattern override)
```
1. Restrições Críticas de Sev 3 → VETO ABSOLUTO
2. Anti-Padrões de Erro → CORREÇÃO OBRIGATÓRIA
3. Padrões de Tolerância → GUIA (overridável por 1 e 2)
4. Similaridade Semântica → REFERÊNCIA APENAS
```

### 3. Relax Exact Phrase Matching (addresses 3/9 FP)
Add tolerance for minor paraphrases of CTAs when brand history shows approval of similar variations.

### 4. Timing Buffer (addresses 2/9 FP)
Allow ±2 second margin for timing guidelines unless explicitly marked as hard cutoffs.

### 5. Negative Guideline Reinforcement (addresses 2/12 FN)
Add explicit step: "Para diretrizes 'NÃO fazer X': verificar se X aparece em QUALQUER forma no conteúdo. Se sim → Sev 1-2."

## Data Gaps

- **Live 7-day production data unavailable**: GCP auth tokens expired (`invalid_rapt`). Need `gcloud auth login` to refresh.
- **Campaign-level production metrics**: Cannot compute actual production disagreement rate, only eval-based estimates.
- **SQL queries ready to run**: See `reports/CAI-290-disagreement-analysis.md` lines 120-173 for pre-built queries.

## Files

- **This report**: `reports/CAI-297-disagreement-analysis-7d.md`
- **Top cases CSV**: `reports/CAI-297-top-cases.csv`
- **Prior analysis**: `reports/CAI-290-disagreement-analysis.md`
- **Eval data**: `guardian-agents-api/evals/.runs/content_moderation/run_20260305_*/`
