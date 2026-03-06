# Weekly Digest — Automated Platform Summary

Generate a comprehensive weekly summary of platform activity, formatted for Slack or PowerPoint delivery.

## When to Use
- "resumo da semana" / "como foi a semana?"
- "weekly digest" / "weekly report"
- "me dá um overview dos últimos 7 dias"
- Scheduled weekly delivery (every Monday morning)
- Before leadership meetings for quick prep

## What It Covers

1. **Volume Overview** — Total content moderated, approval/refusal rates, week-over-week change
2. **Top Campaigns** — Highest volume campaigns with key metrics
3. **Brand Activity** — Most active brands and new campaigns published
4. **Contest Analysis** — Contest rate trends, highest-contested campaigns
5. **Creator Participation** — New submissions, unique creators active
6. **Alerts** — Anomalies: unusually low approval rates, spikes in contests, etc.

## Flow

1. Run the digest query bundle (see below)
2. Calculate week-over-week deltas
3. Identify anomalies (>2 std dev from mean)
4. Format for delivery target (Slack message or PPTX)
5. Highlight wins 🎉 and risks ⚠️

## Query Bundle

### Q1: Weekly Volume Overview (this week vs last week)
```sql
SELECT
  CASE
    WHEN pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
    THEN 'esta_semana'
    ELSE 'semana_passada'
  END AS periodo,
  COUNT(*) AS total_moderado,
  SUM(pm.is_approved = 1) AS aprovados,
  SUM(pm.is_approved = 0) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT pm.creator_id) AS creators_ativos
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL (WEEKDAY(CURDATE()) + 7) DAY)
  AND pm.created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)
  AND pm.deleted_at IS NULL
GROUP BY periodo;
```

### Q2: Top 10 Campaigns by Volume (this week)
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(*) AS total,
  SUM(pm.is_approved = 1) AS aprovados,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT a.creator_id) AS creators
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN ads ON a.ad_id = ads.id
JOIN moments m ON ads.moment_id = m.id
JOIN campaigns c ON m.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
GROUP BY c.id, c.title, b.name
ORDER BY total DESC
LIMIT 10;
```

### Q3: New Campaigns Published This Week
```sql
SELECT c.title, b.name AS marca, c.budget, c.main_objective, c.published_at
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
WHERE c.published_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
  AND c.deleted_at IS NULL
ORDER BY c.published_at DESC;
```

### Q4: Contest Rate This Week
```sql
SELECT
  COUNT(DISTINCT pm.id) AS total_moderado,
  COUNT(DISTINCT pmc.id) AS contestados,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM proofread_medias pm
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY);
```

### Q5: Most Contested Campaigns
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(DISTINCT pm.id) AS moderados,
  COUNT(DISTINCT pmc.id) AS contestados,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN ads ON a.ad_id = ads.id
JOIN moments m ON ads.moment_id = m.id
JOIN campaigns c ON m.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
GROUP BY c.id, c.title, b.name
HAVING moderados >= 5
ORDER BY taxa_contestacao DESC
LIMIT 5;
```

### Q6: Daily Volume Trend (last 14 days)
```sql
SELECT
  DATE(pm.created_at) AS dia,
  COUNT(*) AS total,
  SUM(pm.is_approved = 1) AS aprovados,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
GROUP BY DATE(pm.created_at)
ORDER BY dia;
```

### Q7: Creator Payment Activity This Week
```sql
SELECT
  COUNT(*) AS pagamentos,
  COUNT(DISTINCT cph.creator_id) AS creators_pagos,
  SUM(cph.value) AS total_pago,
  cph.value_currency
FROM creator_payment_history cph
WHERE cph.date_of_transaction >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
GROUP BY cph.value_currency;
```

## Slack Output Format

```
📊 *Resumo Semanal — [date range]*

*Volume*
• Total moderado: X.XXX (↑/↓ Y% vs semana passada)
• Aprovação: XX,X% (↑/↓ Y pp)
• Contestações: XX (X,X%)
• Creators ativos: XXX

*🏆 Top Campanhas*
1. [Campanha] ([Marca]) — X.XXX conteúdos, XX% aprovação
2. ...

*🆕 Novas Campanhas*
• [Campanha] ([Marca]) — Budget: R$ X.XXX
• ...

*⚠️ Atenção*
• [Campanha X] com taxa de contestação de XX% (acima da média)
• Volume caiu XX% na quarta — possível feriado?

*💰 Pagamentos*
• XXX creators pagos — Total: R$ XX.XXX

_Dados: MySQL db-maestro-prod | Gerado automaticamente_
```

## Anomaly Detection Rules

Flag these as ⚠️:
- Approval rate dropped >5pp vs last week
- Contest rate >10% for any campaign with >20 moderations
- Volume dropped >30% any day vs same day last week
- A single campaign has >50% of total volume (concentration risk)
- No new campaigns published in the week

Flag these as 🎉:
- Approval rate up >3pp vs last week
- Record volume day
- Campaign with >95% approval and >100 moderations
- New brand's first campaign

## Safety
- READ ONLY
- Round financial data (R$ XX.XXX, not exact cents)
- Don't expose individual creator IDs/names
- Always cite data source
