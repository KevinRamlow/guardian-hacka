# Creator & Payment Analytics

Answer questions about creator participation, payment status, and performance across campaigns.

## When to Use
- "quantos creators participaram da campanha X?"
- "quanto já pagamos para creators esse mês?"
- "quais creators mais ativos?"
- "status dos pagamentos da campanha Y"
- "qual a distribuição de creators por campanha?"
- "creators com maior taxa de aprovação"
- "quanto um creator específico já recebeu?"

## Key Concepts

- **Creator**: Influencer/content creator who participates in campaigns
- **Action**: A creator's submission to a campaign ad
- **Payment**: Creator gets paid after content is approved and posted
- **Creator Group**: A batch of creators invited to a campaign moment

## Query Patterns

### Creator Participation Summary (by campaign)
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(DISTINCT a.creator_id) AS creators_participantes,
  COUNT(DISTINCT a.id) AS total_submissoes,
  ROUND(COUNT(DISTINCT a.id) / NULLIF(COUNT(DISTINCT a.creator_id), 0), 1) AS submissoes_por_creator,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
JOIN moments m ON m.campaign_id = c.id
JOIN ads ON ads.moment_id = m.id
JOIN actions a ON a.ad_id = ads.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id
WHERE c.title LIKE '%CAMPAIGN_NAME%'
  OR c.id = CAMPAIGN_ID
GROUP BY c.id, c.title, b.name;
```

### Top 10 Creators This Month
```sql
SELECT
  a.creator_id,
  COUNT(DISTINCT a.id) AS total_submissoes,
  COUNT(DISTINCT pm.campaign_id) AS campanhas_participadas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  SUM(CASE WHEN pm.is_approved = 0 THEN 1 ELSE 0 END) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(AVG(TIMESTAMPDIFF(MINUTE, a.created_at, pm.created_at)), 1) AS tempo_moderacao_medio_min
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')
  AND a.deleted_at IS NULL
GROUP BY a.creator_id
HAVING total_submissoes > 0
ORDER BY total_submissoes DESC
LIMIT 10;
```

### Most Active Creators (last 30 days)
```sql
SELECT
  a.creator_id,
  COUNT(DISTINCT a.id) AS total_submissoes,
  COUNT(DISTINCT pm.campaign_id) AS campanhas_participadas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  SUM(CASE WHEN pm.is_approved = 0 THEN 1 ELSE 0 END) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(AVG(TIMESTAMPDIFF(MINUTE, a.created_at, pm.created_at)), 1) AS tempo_moderacao_medio_min
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND a.deleted_at IS NULL
GROUP BY a.creator_id
HAVING total_submissoes > 0
ORDER BY total_submissoes DESC
LIMIT 20;
```

### Specific Creator Performance
```sql
SELECT
  a.creator_id,
  COUNT(DISTINCT a.id) AS total_acoes,
  COUNT(DISTINCT pm.campaign_id) AS campanhas_participadas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  SUM(CASE WHEN pm.is_approved = 0 THEN 1 ELSE 0 END) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(AVG(TIMESTAMPDIFF(MINUTE, a.created_at, pm.created_at)), 1) AS tempo_moderacao_medio_min,
  MIN(a.created_at) AS primeira_submissao,
  MAX(a.created_at) AS ultima_submissao
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.creator_id = CREATOR_ID
  AND a.deleted_at IS NULL
GROUP BY a.creator_id;
```

### Highest Approval Rate Creators (min 5 submissions, last 30 days)
```sql
SELECT
  a.creator_id,
  COUNT(DISTINCT a.id) AS total_submissoes,
  COUNT(DISTINCT pm.campaign_id) AS campanhas_participadas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  SUM(CASE WHEN pm.is_approved = 0 THEN 1 ELSE 0 END) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  ROUND(AVG(TIMESTAMPDIFF(MINUTE, a.created_at, pm.created_at)), 1) AS tempo_moderacao_medio_min
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND a.deleted_at IS NULL
GROUP BY a.creator_id
HAVING total_submissoes >= 5
ORDER BY taxa_aprovacao DESC, total_submissoes DESC
LIMIT 10;
```

### Payment Summary (monthly)
```sql
SELECT
  DATE_FORMAT(cph.date_of_transaction, '%Y-%m') AS mes,
  COUNT(*) AS num_pagamentos,
  COUNT(DISTINCT cph.creator_id) AS creators_pagos,
  ROUND(SUM(cph.value), 2) AS total_pago,
  ROUND(AVG(cph.value), 2) AS pagamento_medio,
  ROUND(MIN(cph.value), 2) AS menor_pagamento,
  ROUND(MAX(cph.value), 2) AS maior_pagamento,
  cph.value_currency
FROM creator_payment_history cph
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
GROUP BY mes, cph.value_currency
ORDER BY mes DESC;
```

### Payment Status by Campaign
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(DISTINCT cph.creator_id) AS creators_pagos,
  ROUND(SUM(cph.value), 2) AS total_pago,
  ROUND(AVG(cph.value), 2) AS pagamento_medio,
  cph.value_currency,
  cph.payment_status
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE c.title LIKE '%CAMPAIGN_NAME%'
   OR c.id = CAMPAIGN_ID
GROUP BY c.id, c.title, b.name, cph.value_currency, cph.payment_status;
```

### Creator Payment Lookup (by creator_id)
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  cph.value,
  cph.gross_value,
  cph.value_currency,
  cph.payment_status,
  cph.date_of_transaction
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE cph.creator_id = CREATOR_ID
ORDER BY cph.date_of_transaction DESC
LIMIT 20;
```

### Creator Group Utilization
```sql
SELECT
  c.title AS campanha,
  cg.title AS grupo,
  cg.creators_quantity_goal AS meta_creators,
  COUNT(DISTINCT cgi.id) AS convidados,
  cg.status,
  cg.published_at
FROM creator_groups cg
JOIN campaigns c ON cg.campaign_id = c.id
LEFT JOIN creator_group_invites cgi ON cgi.creator_group_id = cg.id
  AND cgi.deleted_at IS NULL
WHERE c.title LIKE '%CAMPAIGN_NAME%'
   OR c.id = CAMPAIGN_ID
GROUP BY cg.id, c.title, cg.title, cg.creators_quantity_goal, cg.status, cg.published_at;
```

### Platform-Wide Creator Stats
```sql
SELECT
  COUNT(DISTINCT a.creator_id) AS creators_ativos_30d,
  COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) 
        THEN a.creator_id END) AS creators_ativos_7d,
  COUNT(DISTINCT a.id) AS total_submissoes_30d,
  ROUND(COUNT(DISTINCT a.id) / NULLIF(COUNT(DISTINCT a.creator_id), 0), 1) AS submissoes_media_por_creator
FROM actions a
WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND a.deleted_at IS NULL;
```

### Payment Distribution (histogram-like)
```sql
SELECT
  CASE
    WHEN cph.value < 50 THEN '< R$50'
    WHEN cph.value < 100 THEN 'R$50-100'
    WHEN cph.value < 250 THEN 'R$100-250'
    WHEN cph.value < 500 THEN 'R$250-500'
    WHEN cph.value < 1000 THEN 'R$500-1K'
    ELSE '> R$1K'
  END AS faixa,
  COUNT(*) AS pagamentos,
  COUNT(DISTINCT cph.creator_id) AS creators,
  ROUND(SUM(cph.value), 2) AS total
FROM creator_payment_history cph
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND cph.value_currency = 'BRL'
GROUP BY faixa
ORDER BY MIN(cph.value);
```

## Response Format

### Top 10 Creators This Month
```
🏆 *Top 10 Creators — [Mês/Ano]*

1. Creator #XXXX
   • Submissões: XXX | Campanhas: X
   • Aprovados: XX | Recusados: XX (taxa: XX,X%)
   • Tempo médio moderação: XX,X min

2. Creator #YYYY
   • Submissões: YYY | Campanhas: Y
   • Aprovados: YY | Recusados: YY (taxa: YY,Y%)
   • Tempo médio moderação: YY,Y min

[...]

_Fonte: MySQL db-maestro-prod_
```

### Specific Creator Performance
```
📊 *Performance — Creator #XXXXX*

• Total ações: XXX
• Campanhas participadas: XX
• Aprovados: XXX (XX,X%)
• Recusados: XX (XX,X%)
• Tempo médio moderação: XX,X minutos
• Primeira submissão: DD/MM/YYYY
• Última submissão: DD/MM/YYYY

_Fonte: MySQL db-maestro-prod_
```

### Highest Approval Rate
```
⭐ *Creators com Maior Taxa de Aprovação (mín. 5 submissões)*

1. Creator #XXXX — XX,X% (XX aprovados de XX)
   • Campanhas: X | Tempo médio: XX min

2. Creator #YYYY — YY,Y% (YY aprovados de YY)
   • Campanhas: Y | Tempo médio: YY min

[...]

_Fonte: MySQL db-maestro-prod_
```

### Creator Participation
```
👥 *Creators na campanha [Nome]*

• Participantes: XXX creators
• Submissões: X.XXX (média: X,X por creator)
• Aprovação: XX,X%
• Mais ativo: Creator #XXXX (XX submissões)

_Fonte: MySQL db-maestro-prod_
```

### Payment Summary
```
💰 *Pagamentos — [Mês/Período]*

• Total pago: R$ XXX.XXX
• Creators pagos: XXX
• Pagamento médio: R$ XXX
• Maior pagamento: R$ X.XXX
• Menor pagamento: R$ XX

*Distribuição:*
• < R$50: XX pagamentos (XX%)
• R$50-100: XX pagamentos (XX%)
• R$100-250: XX pagamentos (XX%)
• > R$250: XX pagamentos (XX%)

_Fonte: MySQL db-maestro-prod_
```

## Privacy Rules — CRITICAL
- **NEVER expose creator names, emails, or any PII**
- Use creator_id only (e.g., "Creator #12345")
- In group channels, anonymize even creator_ids: "um creator específico"
- Payment amounts for specific creators: ONLY in DMs with authorized personnel
- Aggregate data is always safe to share

## Safety
- READ ONLY
- Mask individual creator identities
- Be careful with financial data — round values, don't expose exact amounts in groups
- Always add LIMIT to queries
- Date-bound all queries
