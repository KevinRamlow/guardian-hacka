# CAI-290: Guardian Disagreement & Tolerance Pattern Analysis
**Date:** 2026-03-07 | **Data source:** sev3_disagreements_analysis.json (2026-03-06), severity_analysis.j2 prompt review

## Executive Summary

**GCP auth tokens are expired** — could not run live MySQL/BQ queries for fresh 7-day data. Analysis based on most recent eval dataset (2026-03-06) and prompt review.

**Key finding:** 100% of disagreements (5/5) are **false tolerations at the severity 3 boundary** — Guardian approves (sev 3) when the brand rejects. Zero false rejections. The severity agent prompt already contains specific restrictions for these exact patterns, but the model is not consistently applying them.

## Top 5 Disagreement Patterns

### Pattern 1: Compound Requirements (X + Y) — Only X Delivered
- **Cases:** Vizzela ("mudou embalagem, MAS segue perfeita por dentro") — creator only mentioned new packaging, not quality
- **Root cause:** Model accepts partial compliance + high semantic similarity as sufficient
- **Prompt already says:** "Se diretriz tem X, MAS Y — AMBOS devem ser EXPLICITAMENTE mencionados"
- **Issue:** Model rationalizes via "implicação" — "testing implies quality is maintained"

### Pattern 2: Strategic Brand Terms Substituted with Generic Praise
- **Cases:** Mercado Pago ("é uma conta" replaced with "é cheio de vantagens")
- **Root cause:** Model treats brand positioning terms as paraphrasable
- **Prompt already says:** "Palavras de posicionamento estratégico... Substituições genéricas mudam o posicionamento"
- **Issue:** Model leans on tolerance patterns and "intent alignment" to override the explicit restriction

### Pattern 3: Pronoun/Subject Swap Changes Beneficiary
- **Cases:** Mercafe ("Chegou o SEU momento" → "Chegou o MEU momento")
- **Root cause:** 93.58% semantic similarity overrides pronoun analysis
- **Prompt already says:** "Alta similaridade (>90%) com pronome trocado → AINDA E Sev 2"
- **Issue:** Model notes the swap but still classifies as tolerável because "a intenção de convidar é mantida"

### Pattern 4: CTA Verb Swap Changes Conversion Intent
- **Cases:** Betano ("aproveite" → "divirta-se", 97.84% similarity)
- **Root cause:** High similarity score dominates the decision
- **Prompt already says:** "aproveite (tome vantagem) ≠ divirta-se (engaje)... Similaridade >95% com verbo diferente → AINDA E Sev 2"
- **Issue:** The EXACT example from the prompt is being ignored by the model

### Pattern 5: "During Application" Temporal Over-Tolerance
- **Cases:** L'Oreal (product shown during preparation, not actual application)
- **Root cause:** "Preparation for application" interpreted as "during application"
- **Prompt already says:** "Durante aplicação = NO MOMENTO de aplicar, não antes (preparação)"
- **Issue:** Model uses tolerance patterns ("commonly approved: hands applying product from jar") to override temporal restriction

## Classification Breakdown (from eval data)

| Classification | Disagreements | FP | FN |
|---|---|---|---|
| GENERAL_GUIDELINE | 5 | 5 | 0 |

All disagreements are in GENERAL_GUIDELINE with MUST_DO requirements. Other classifications (CAPTIONS, VIDEO_DURATION, PRONUNCIATION, BRAND_SAFETY) show no disagreements in this dataset.

## Root Cause Analysis

The severity analysis prompt (severity_analysis.j2) already contains **explicit restrictions** for all 5 patterns at lines 53-60. The problem is NOT missing instructions — it's that:

1. **Tolerance patterns override restrictions:** The model uses historical tolerance data to justify overriding the explicit sev 3 restrictions. The "Comumente Aprovados" examples from tolerance patterns create a competing signal.

2. **High semantic similarity creates false confidence:** Scores >90% make the model default to "close enough" even when the prompt says otherwise.

3. **Anti-patterns not applied reflexively:** The prompt asks the model to check anti-patterns, but the model's reasoning shows it proceeds with the tolerant decision anyway.

## Recommended Prompt Improvements

### 1. Add HARD GATES before severity assignment
Instead of listing restrictions as text, restructure as explicit IF-THEN gates:

```
ANTES de atribuir Severidade 3, VERIFIQUE OBRIGATORIAMENTE:
[ ] Todos os elementos de requisito composto presentes EXPLICITAMENTE? (Se NAO → Sev 2)
[ ] Termo estrategico de marca presente LITERALMENTE? (Se NAO → Sev 2)
[ ] Pronomes/sujeito IDENTICOS ao da diretriz? (Se NAO → Sev 2)
[ ] Verbo de CTA IDENTICO ou sinonimo direto funcional? (Se NAO → Sev 2)
[ ] Contexto temporal preciso (durante = durante, nao antes/depois)? (Se NAO → Sev 2)

Se QUALQUER check falhar: Sev 2 (answer: false). Tolerancia patterns NAO overridam estes gates.
```

### 2. Add explicit override hierarchy
```
HIERARQUIA DE DECISAO (nao pode ser invertida):
1. Restricoes Criticas de Sev 3 (linhas acima) — VETO ABSOLUTO
2. Anti-Padroes de Erro — CORRECAO OBRIGATORIA
3. Padroes de Tolerancia — GUIA (pode ser overridado por 1 e 2)
4. Similaridade Semantica — REFERENCIA APENAS
```

### 3. Add negative examples to the CTA tool interpretation
In the `_compare_semantic_cta_similarity` interpretation section, add:
```
ARMADILHA: Score >90% NAO significa aprovacao automatica.
Exemplos de rejeicao com score alto:
- "aproveite" vs "divirta-se" (97%) → Sev 2 (verbo diferente)
- "seu momento" vs "meu momento" (93%) → Sev 2 (pronome trocado)
- "mudou mas segue perfeita" vs "de embalagem nova" (90%) → Sev 2 (parte B ausente)
```

### 4. Strengthen tolerance pattern disclaimer
Add to section "Como usar Padrões de Tolerância":
```
LIMITACAO: Padroes de Tolerancia refletem decisoes PASSADAS da marca, que podem incluir erros.
Eles NAO overridam as Restricoes Criticas de Sev 3. Se um padrao sugere aprovar mas uma
Restricao Critica sugere rejeitar → REJEITE (Sev 2).
```

### 5. Add a "Devil's Advocate" step before final decision
After step 6 (Synthesis), add:
```
Passo 6.5: Advocacia do Diabo
Se voce esta prestes a dar Sev 3 (aprovar com violacao), PARE e pergunte:
"Alguma das 5 Restricoes Criticas se aplica?" Releia cada uma.
Se SIM → mude para Sev 2 INDEPENDENTE de tolerancia ou similaridade.
```

## Data Gaps

- **Live data needed:** GCP auth must be refreshed (`gcloud auth login`) to run fresh 7-day queries
- **By-campaign breakdown:** Cannot compute without live MySQL access
- **Volume metrics:** Total evaluations, overall agreement rate, FP/FN split unavailable

## SQL Queries (Ready to Run When Auth Fixed)

```sql
-- Overall disagreement rate (last 7 days, agentic only)
SELECT
  COUNT(*) as total,
  SUM(CASE WHEN gpm.is_approved != (CASE WHEN mc.refused_at IS NOT NULL THEN 0 WHEN a.approved_at IS NOT NULL THEN 1 END) THEN 1 ELSE 0 END) as disagreements,
  ROUND(100.0 * SUM(CASE WHEN gpm.is_approved != (CASE WHEN mc.refused_at IS NOT NULL THEN 0 WHEN a.approved_at IS NOT NULL THEN 1 END) THEN 1 ELSE 0 END) / COUNT(*), 2) as disagree_pct,
  SUM(CASE WHEN gpm.is_approved = 0 AND a.approved_at IS NOT NULL THEN 1 ELSE 0 END) as FP,
  SUM(CASE WHEN gpm.is_approved = 1 AND mc.refused_at IS NOT NULL THEN 1 ELSE 0 END) as FN
FROM proofread_medias gpm
INNER JOIN media_content mc ON gpm.media_id = mc.id
INNER JOIN actions a ON mc.action_id = a.id
INNER JOIN campaigns c ON c.id = gpm.campaign_id
WHERE LOWER(c.title) NOT LIKE '%teste%'
  AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)
  AND gpm.deleted_at IS NULL
  AND gpm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output');

-- Disagreements by guideline classification
SELECT
  pg.classification, COUNT(DISTINCT gpm.id) as total,
  SUM(CASE WHEN gpm.is_approved != (CASE WHEN mc.refused_at IS NOT NULL THEN 0 WHEN a.approved_at IS NOT NULL THEN 1 END) THEN 1 ELSE 0 END) as disagreements,
  SUM(CASE WHEN gpm.is_approved = 0 AND a.approved_at IS NOT NULL THEN 1 ELSE 0 END) as FP,
  SUM(CASE WHEN gpm.is_approved = 1 AND mc.refused_at IS NOT NULL THEN 1 ELSE 0 END) as FN
FROM proofread_medias gpm
INNER JOIN media_content mc ON gpm.media_id = mc.id
INNER JOIN actions a ON mc.action_id = a.id
INNER JOIN campaigns c ON c.id = gpm.campaign_id
INNER JOIN proofread_guidelines pg ON pg.proofread_media_id = gpm.id
WHERE LOWER(c.title) NOT LIKE '%teste%'
  AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)
  AND gpm.deleted_at IS NULL AND pg.deleted_at IS NULL
  AND gpm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output')
GROUP BY pg.classification ORDER BY disagreements DESC;

-- Top campaigns by disagreement rate (min 5 evals)
SELECT
  c.title, b.name, COUNT(*) as total,
  SUM(CASE WHEN gpm.is_approved != (CASE WHEN mc.refused_at IS NOT NULL THEN 0 WHEN a.approved_at IS NOT NULL THEN 1 END) THEN 1 ELSE 0 END) as disagreements,
  ROUND(100.0 * SUM(CASE WHEN gpm.is_approved != (CASE WHEN mc.refused_at IS NOT NULL THEN 0 WHEN a.approved_at IS NOT NULL THEN 1 END) THEN 1 ELSE 0 END) / COUNT(*), 1) as disagree_pct
FROM proofread_medias gpm
INNER JOIN media_content mc ON gpm.media_id = mc.id
INNER JOIN actions a ON mc.action_id = a.id
INNER JOIN campaigns c ON c.id = gpm.campaign_id
INNER JOIN brands b ON b.id = c.brand_id
WHERE LOWER(c.title) NOT LIKE '%teste%'
  AND (mc.refused_at IS NOT NULL OR a.approved_at IS NOT NULL)
  AND gpm.deleted_at IS NULL
  AND gpm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND JSON_CONTAINS_PATH(gpm.metadata, 'one', '$.audio_output')
GROUP BY c.id, c.title, b.name HAVING total >= 5
ORDER BY disagree_pct DESC LIMIT 15;
```
