# Campaign Comparison — Side-by-Side Analysis

Compare two or more campaigns on key metrics for quick decision-making.

## When to Use
- "compara a campanha X com a Y"
- "qual campanha performou melhor?"
- "me mostra as campanhas da [marca] lado a lado"
- "benchmark da campanha X vs média da plataforma"
- Before meetings: "preciso comparar as campanhas de março pra reunião"

## What It Compares

| Metric | Description |
|--------|-------------|
| Volume | Total content moderated |
| Approval Rate | % approved |
| Contest Rate | % contested after refusal |
| Creator Count | Unique creators participating |
| Time to Moderate | Avg time from submission to moderation |
| Top Refusal Reasons | Most common reasons content was refused |
| Budget Efficiency | Content per R$ (budget vs volume) |

## Query Patterns

### Compare Specific Campaigns by Name/ID
```sql
SELECT
  c.id,
  c.title AS campanha,
  b.name AS marca,
  c.budget,
  COUNT(DISTINCT pm.id) AS total_moderado,
  SUM(pm.is_approved = 1) AS aprovados,
  SUM(pm.is_approved = 0) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT pmc.id) AS contestacoes,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(SUM(pm.is_approved = 0), 0) * 100, 1) AS taxa_contestacao_sobre_recusas,
  COUNT(DISTINCT a.creator_id) AS creators,
  ROUND(COUNT(DISTINCT pm.id) / NULLIF(c.budget, 0), 2) AS conteudos_por_real,
  MIN(pm.created_at) AS primeira_moderacao,
  MAX(pm.created_at) AS ultima_moderacao
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
JOIN moments m ON m.campaign_id = c.id
JOIN ads ON ads.moment_id = m.id
JOIN actions a ON a.ad_id = ads.id
JOIN proofread_medias pm ON pm.action_id = a.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id IN (CAMPAIGN_ID_1, CAMPAIGN_ID_2)
   OR c.title IN ('CAMPAIGN_NAME_1', 'CAMPAIGN_NAME_2')
GROUP BY c.id, c.title, b.name, c.budget;
```

### Compare All Campaigns of a Brand
```sql
SELECT
  c.title AS campanha,
  c.budget,
  COUNT(DISTINCT pm.id) AS total_moderado,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT a.creator_id) AS creators,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
JOIN moments m ON m.campaign_id = c.id
JOIN ads ON ads.moment_id = m.id
JOIN actions a ON a.ad_id = ads.id
JOIN proofread_medias pm ON pm.action_id = a.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE b.name LIKE '%BRAND_NAME%'
  AND c.deleted_at IS NULL
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY c.id, c.title, c.budget
HAVING total_moderado > 0
ORDER BY total_moderado DESC;
```

### Campaign vs Platform Average
```sql
SELECT
  'campanha' AS tipo,
  c.title AS nome,
  COUNT(DISTINCT pm.id) AS total_moderado,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM campaigns c
JOIN moments m ON m.campaign_id = c.id
JOIN ads ON ads.moment_id = m.id
JOIN actions a ON a.ad_id = ads.id
JOIN proofread_medias pm ON pm.action_id = a.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = CAMPAIGN_ID

UNION ALL

SELECT
  'plataforma' AS tipo,
  'Média Geral' AS nome,
  COUNT(DISTINCT pm2.id) AS total_moderado,
  ROUND(SUM(pm2.status = 'approved') / NULLIF(COUNT(DISTINCT pm2.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(COUNT(DISTINCT pmc2.id) / NULLIF(COUNT(DISTINCT pm2.id), 0) * 100, 1) AS taxa_contestacao
FROM proofread_medias pm2
LEFT JOIN proofread_media_contest pmc2 ON pmc2.proofread_media_id = pm2.id
WHERE pm2.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY);
```

### Refusal Reasons Comparison
```sql
SELECT
  c.title AS campanha,
  pg.guideline AS motivo_recusa,
  COUNT(*) AS vezes,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY c.id) * 100, 1) AS pct
FROM media_content_refused_guidelines mcrg
JOIN proofread_guidelines pg ON mcrg.proofread_guideline_id = pg.id
JOIN media_content mc ON mcrg.media_content_id = mc.id
JOIN actions a ON mc.action_id = a.id
JOIN ads ON a.ad_id = ads.id
JOIN moments m ON ads.moment_id = m.id
JOIN campaigns c ON m.campaign_id = c.id
WHERE c.id IN (CAMPAIGN_ID_1, CAMPAIGN_ID_2)
GROUP BY c.id, c.title, pg.guideline
ORDER BY c.title, vezes DESC;
```

## Response Format

### Two-Campaign Comparison
```
📊 *Comparativo: [Campanha A] vs [Campanha B]*

| Métrica | [Camp A] | [Camp B] | Δ |
|---------|----------|----------|---|
| Volume | X.XXX | Y.YYY | ↑ ZZ% |
| Aprovação | XX% | YY% | ↑ Z pp |
| Contestação | X% | Y% | — |
| Creators | XXX | YYY | — |
| Budget | R$ XX.XXX | R$ YY.YYY | — |
| Eficiência | X,X cont/R$ | Y,Y cont/R$ | ↑ ZZ% |

*Análise:*
• [Campanha A] teve maior volume mas [Campanha B] teve melhor taxa de aprovação
• [Insight sobre eficiência de budget]
• [Recomendação]

_Fonte: MySQL db-maestro-prod_
```

### Slack-Native Format (no tables)
For Slack delivery, use bullet lists:

```
📊 *Comparativo: [Campanha A] vs [Campanha B]*

*[Campanha A]* ([Marca])
• Volume: X.XXX conteúdos
• Aprovação: XX,X%
• Contestação: X,X%
• Creators: XXX
• Budget: R$ XX.XXX (X,X conteúdos/R$)

*[Campanha B]* ([Marca])
• Volume: Y.YYY conteúdos
• Aprovação: YY,Y%
• Contestação: Y,Y%
• Creators: YYY
• Budget: R$ YY.YYY (Y,Y conteúdos/R$)

*Veredito:*
🏆 [Campanha X] vence em [volume/aprovação/eficiência]
💡 [Insight acionável]
```

## Safety
- READ ONLY
- Don't expose exact budget amounts in group channels without checking context
- Mask creator IDs
- Always cite data source
