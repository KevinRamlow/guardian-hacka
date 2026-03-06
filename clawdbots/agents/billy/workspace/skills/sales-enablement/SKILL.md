# Sales Enablement — Campaign Success Stories

Package campaign success stories with metrics for sales pitches. ROI, engagement stats, creator counts, approval rates — formatted as pitch-ready narratives.

## When to Use
- "me mostra cases de sucesso para pitch"
- "quais foram as melhores campanhas da marca X?"
- "top 10 campanhas do ano"
- "cases de ROI alto"
- "histórias de sucesso para apresentação"
- "estatísticas da campanha X para pitch"
- "campanhas com melhor taxa de aprovação"

## What It Shows

**Success Metrics:**
1. **Creator Engagement** — Total creators, content volume, participation rate
2. **Approval Excellence** — Approval rate vs platform average
3. **ROI Indicators** — Budget efficiency, payment completion rate
4. **Campaign Velocity** — Time from launch to completion
5. **Content Quality** — Contest rate (lower = higher quality)
6. **Brand Performance** — Aggregate metrics for specific brands

## Usage

```bash
# Top campaigns (last 6 months, by approval rate)
./sales-enablement.sh --top 10

# Best campaigns for a specific brand
./sales-enablement.sh --brand "Natura"

# Campaign success story (specific campaign)
./sales-enablement.sh --campaign-id 1234

# Top campaigns by metric
./sales-enablement.sh --top 10 --metric creators
./sales-enablement.sh --top 10 --metric approval_rate
./sales-enablement.sh --top 10 --metric roi

# Export to Google Sheets for pitch deck
./sales-enablement.sh --top 10 --export-sheets

# Year-over-year comparison
./sales-enablement.sh --brand "Natura" --year 2026
```

## Query Details

### Top Performing Campaigns (Last 6 Months)
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  b.name AS brand,
  c.budget,
  c.main_objective,
  COUNT(DISTINCT pm.creator_id) AS total_creators,
  COUNT(DISTINCT pm.id) AS total_content,
  SUM(pm.is_approved = 1) AS approved_content,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
  COUNT(DISTINCT pmc.id) AS contests,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS contest_rate,
  ROUND(SUM(cph.value), 2) AS total_paid,
  ROUND(SUM(cph.value) / NULLIF(c.budget, 0) * 100, 1) AS budget_utilization,
  COUNT(DISTINCT cph.id) AS total_payments,
  ROUND(AVG(cph.value), 2) AS avg_creator_payment,
  c.published_at,
  MAX(pm.created_at) AS last_submission
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.published_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
  AND c.deleted_at IS NULL
GROUP BY c.id, c.title, b.name, c.budget, c.main_objective, c.published_at
HAVING total_creators >= 10 AND total_content >= 30
ORDER BY approval_rate DESC, total_creators DESC
LIMIT ?;
```

### Brand-Specific Success Stories
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  c.budget,
  c.main_objective,
  COUNT(DISTINCT pm.creator_id) AS total_creators,
  COUNT(DISTINCT pm.id) AS total_content,
  SUM(pm.is_approved = 1) AS approved_content,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
  ROUND(SUM(cph.value), 2) AS total_paid,
  ROUND(SUM(cph.value) / NULLIF(c.budget, 0) * 100, 1) AS budget_utilization,
  c.published_at,
  DATEDIFF(MAX(pm.created_at), c.published_at) AS campaign_duration_days
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE b.name LIKE CONCAT('%', ?, '%')
  AND c.published_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
  AND c.deleted_at IS NULL
GROUP BY c.id, c.title, c.budget, c.main_objective, c.published_at
HAVING total_creators >= 5
ORDER BY approval_rate DESC, total_creators DESC
LIMIT 10;
```

### Platform Average Baseline (for comparison)
```sql
SELECT 
  ROUND(AVG(approval_rate), 1) AS platform_avg_approval,
  ROUND(AVG(total_creators), 0) AS avg_creators_per_campaign,
  ROUND(AVG(total_content), 0) AS avg_content_per_campaign,
  ROUND(AVG(contest_rate), 1) AS platform_avg_contest_rate
FROM (
  SELECT 
    c.id,
    SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100 AS approval_rate,
    COUNT(DISTINCT pm.creator_id) AS total_creators,
    COUNT(DISTINCT pm.id) AS total_content,
    COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100 AS contest_rate
  FROM campaigns c
  LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
  LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
  WHERE c.published_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
    AND c.deleted_at IS NULL
  GROUP BY c.id
  HAVING total_content >= 10
) AS campaign_stats;
```

### Single Campaign Success Story
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  b.name AS brand,
  c.budget,
  c.main_objective,
  c.published_at,
  COUNT(DISTINCT pm.creator_id) AS total_creators,
  COUNT(DISTINCT pm.id) AS total_content,
  SUM(pm.is_approved = 1) AS approved_content,
  SUM(pm.is_approved = 0) AS refused_content,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
  COUNT(DISTINCT pmc.id) AS contests,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS contest_rate,
  ROUND(SUM(cph.value), 2) AS total_paid_net,
  ROUND(SUM(cph.gross_value), 2) AS total_paid_gross,
  ROUND(SUM(cph.value) / NULLIF(c.budget, 0) * 100, 1) AS budget_utilization,
  COUNT(DISTINCT cph.id) AS total_payments,
  ROUND(AVG(cph.value), 2) AS avg_creator_payment,
  SUM(cph.payment_status = 'complete') AS payments_complete,
  SUM(cph.payment_status = 'partial') AS payments_partial,
  SUM(cph.payment_status = 'in_process') AS payments_in_process,
  DATEDIFF(MAX(pm.created_at), c.published_at) AS campaign_duration_days,
  MAX(pm.created_at) AS last_submission
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.id = ?
GROUP BY c.id, c.title, b.name, c.budget, c.main_objective, c.published_at;
```

## Response Format (Pitch-Ready Narrative)

### Single Campaign Story
```
📊 Case de Sucesso: [CAMPAIGN NAME]
Marca: [BRAND] | Objetivo: [MAIN_OBJECTIVE]

✨ DESTAQUES
• [X] creators engajados gerando [Y] conteúdos de alta qualidade
• Taxa de aprovação de [Z]% — [N]pp acima da média da plataforma
• [A]% do budget utilizado de forma eficiente
• Campanha concluída em [B] dias — [fast/standard/extended] velocity
• Apenas [C]% de contestações — conteúdo de excelente qualidade

💰 INVESTIMENTO & ROI
• Budget: R$ [BUDGET]
• Investido: R$ [TOTAL_PAID] ([BUDGET_UTILIZATION]%)
• Pagamento médio por creator: R$ [AVG_PAYMENT]
• [PAYMENTS_COMPLETE] pagamentos completos de [TOTAL_PAYMENTS] totais

📈 PERFORMANCE
• [APPROVED] conteúdos aprovados de [TOTAL_CONTENT] submetidos
• [TOTAL_CREATORS] creators ativos
• Taxa de aprovação: [APPROVAL_RATE]% (média da plataforma: [PLATFORM_AVG]%)
• [CONTESTS] contestações ([CONTEST_RATE]%) — quality indicator

🎯 CONTEXTO
Publicada em [DATE], essa campanha demonstra [insight based on metrics].
[Context about why this was successful — high approval = strong brief, 
low contests = clear guidelines, high participation = attractive offer, etc.]
```

### Top Campaigns List
```
🏆 TOP 10 CAMPANHAS — Últimos 6 Meses

1️⃣ [CAMPAIGN NAME] — [BRAND]
   • [X] creators | [Y] conteúdos | [Z]% aprovação
   • R$ [PAID] investido | [N] dias de duração
   • Destaque: [highest approval/most creators/best ROI/etc]

2️⃣ [CAMPAIGN NAME] — [BRAND]
   • [X] creators | [Y] conteúdos | [Z]% aprovação
   • R$ [PAID] investido | [N] dias de duração
   • Destaque: [what makes this special]

...

📊 Média da Plataforma (6 meses)
• Aprovação: [X]% | Creators/campanha: [Y] | Conteúdo/campanha: [Z]
• Taxa de contestação: [N]%

💡 Insight: [Pattern across top performers — what makes them successful?]
```

### Brand Performance Summary
```
📈 PERFORMANCE DA MARCA: [BRAND NAME]

🎯 Últimos 12 Meses — [N] campanhas realizadas

🏆 MELHORES CAMPANHAS
1. [CAMPAIGN] — [APPROVAL_RATE]% aprovação, [CREATORS] creators
2. [CAMPAIGN] — [APPROVAL_RATE]% aprovação, [CREATORS] creators
3. [CAMPAIGN] — [APPROVAL_RATE]% aprovação, [CREATORS] creators

📊 ESTATÍSTICAS GERAIS
• Total de creators engajados: [SUM_CREATORS]
• Total de conteúdos criados: [SUM_CONTENT]
• Taxa média de aprovação: [AVG_APPROVAL]%
• Investimento total: R$ [SUM_PAID]

✨ DESTAQUES
• [Insight 1 — e.g., consistently high approval rates]
• [Insight 2 — e.g., strong creator engagement]
• [Insight 3 — e.g., efficient budget utilization]

🎤 NARRATIVA PARA PITCH
[Brand] é um case consistente de sucesso na plataforma, 
com [X] campanhas nos últimos 12 meses mantendo taxa de 
aprovação média de [Y]%, bem acima da média do mercado.
[Additional context about brand's success factors]
```

## Narrative Generation Rules

When formatting responses:
1. **Lead with the wow factor** — biggest number, most impressive metric
2. **Compare to baseline** — platform average, industry benchmarks
3. **Tell the story** — why was this successful? what patterns emerge?
4. **Use bullet points** — no tables, keep it pitch-deck friendly
5. **Highlight efficiency** — ROI, budget utilization, time to complete
6. **Quality indicators** — low contest rate = strong guidelines
7. **Context matters** — fast velocity? high creator count? explain why it's notable

**Metric interpretation guide:**
- **Approval rate >85%** → "excelente alinhamento de brief e guidelines"
- **Contest rate <2%** → "guidelines claras e conteúdo de alta qualidade"
- **Budget utilization >90%** → "planejamento eficiente de recursos"
- **Campaign duration <30 days** → "alto engajamento e execução rápida"
- **Creators >50** → "campanha de grande escala"
- **Avg payment >R$200** → "investimento premium em creators"

## Google Sheets Export (--export-sheets)

When generating pitch deck exports:
1. **Sheet 1: Executive Summary** — Top metrics, key insights, platform comparison
2. **Sheet 2: Campaign Details** — Full data table for all campaigns in scope
3. **Sheet 3: Brand Breakdown** — If brand-specific, show all campaigns
4. **Sheet 4: Success Factors** — Analysis of what makes top performers succeed

Charts to include:
- Approval rate comparison (campaign vs platform avg)
- Creator engagement over time
- Budget utilization distribution
- Campaign velocity histogram

## Safety & Best Practices

- **READ ONLY** — no writes to database
- **No PII** — creator names/emails never in pitch materials
- **Aggregated data only** — individual creator performance stays internal
- **Budget transparency** — OK to share campaign budgets (not sensitive)
- **Context required** — always include platform baseline for comparison
- **Recency filter** — default to last 6 months unless specified
- **Minimum thresholds** — only include campaigns with ≥10 creators, ≥30 content pieces (signal quality)

## Integration with Other Skills

- **campaign-performance** → Deep dive on a single campaign (full dashboard)
- **sales-enablement** → Cross-campaign stories for pitch decks
- **campaign-lookup** → Quick status check
- Use sales-enablement when preparing client pitches, investor updates, or showcasing platform success
- Use campaign-performance when analyzing a specific active campaign

## Example Use Cases

**Scenario 1: Sales pitch for new brand**
> "Billy, me mostra os top 5 cases de sucesso de campanhas de skincare"
> → Returns 5 best skincare campaigns with metrics formatted for pitch deck

**Scenario 2: Quarterly business review**
> "Billy, performance da marca Natura nos últimos 12 meses"
> → Brand performance summary with all campaigns, trends, success factors

**Scenario 3: Investor update**
> "Billy, top 10 campanhas do trimestre para incluir no board deck"
> → Top performers with ROI, engagement, quality metrics + Google Sheets export

**Scenario 4: Client renewal conversation**
> "Billy, estatísticas da campanha Summer Vibes 2026 para pitch de renovação"
> → Single campaign success story with full narrative and comparison to platform avg
