# Daily Digest — Proactive Daily Platform Summary

Generate a concise daily summary of platform activity: campaign updates, moderation stats, alerts, and upcoming deadlines. Designed for proactive Slack delivery each morning.

## When to Use
- "resumo de hoje" / "como está o dia?"
- "daily digest" / "daily report"
- "o que rolou hoje?"
- Scheduled daily delivery (every morning via cron)
- Quick platform health check

## What It Covers

1. **Yesterday's Volume** — Total content moderated, approval rate, contests
2. **New Campaigns** — Campaigns published in last 24h
3. **Completed Campaigns** — Campaigns that finished yesterday
4. **Moderation Stats** — Volume trends, approval/rejection rates
5. **Alerts** — Anomalies: stalled campaigns, high rejection rates, submission drops
6. **Upcoming Deadlines** — Campaigns ending in next 2-3 days

## Flow

1. Run daily metrics queries
2. Detect anomalies using campaign-health patterns
3. Flag upcoming deadlines
4. Format as Slack-friendly digest
5. Highlight wins 🎉 and risks ⚠️

## Query Bundle

### Q1: Yesterday's Volume Overview
```sql
SELECT
  COUNT(*) AS total_moderado,
  SUM(pm.is_approved = 1) AS aprovados,
  SUM(pm.is_approved = 0) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT pm.creator_id) AS creators_ativos,
  COUNT(DISTINCT pmc.id) AS contestados,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM proofread_medias pm
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE DATE(pm.created_at) = CURDATE() - INTERVAL 1 DAY
  AND pm.deleted_at IS NULL;
```

### Q2: New Campaigns (last 24h)
```sql
SELECT
  c.id,
  c.title AS campanha,
  b.name AS marca,
  c.budget,
  c.main_objective AS objetivo,
  c.published_at
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
WHERE c.published_at >= NOW() - INTERVAL 24 HOUR
  AND c.deleted_at IS NULL
ORDER BY c.published_at DESC;
```

### Q3: Completed Campaigns (yesterday)
```sql
SELECT
  c.id,
  c.title AS campanha,
  b.name AS marca,
  c.finished_at,
  (SELECT COUNT(*) FROM proofread_medias pm
   JOIN actions a ON pm.action_id = a.id
   WHERE a.campaign_id = c.id AND pm.is_approved = 1) AS total_aprovados
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
WHERE DATE(c.finished_at) = CURDATE() - INTERVAL 1 DAY
  AND c.deleted_at IS NULL
ORDER BY total_aprovados DESC;
```

### Q4: Top 5 Active Campaigns by Volume (yesterday)
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(*) AS total,
  SUM(pm.is_approved = 1) AS aprovados,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN campaigns c ON a.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE DATE(pm.created_at) = CURDATE() - INTERVAL 1 DAY
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title, b.name
ORDER BY total DESC
LIMIT 5;
```

### Q5: Campaigns with High Rejection Rate (last 7 days, >50%)
```sql
SELECT
  c.title AS campanha,
  b.name AS marca,
  COUNT(*) AS total_moderado,
  SUM(pm.is_approved = 0) AS rejeitados,
  ROUND(SUM(pm.is_approved = 0) / COUNT(*) * 100, 1) AS taxa_rejeicao
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN campaigns c ON a.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE pm.created_at >= NOW() - INTERVAL 7 DAY
  AND pm.deleted_at IS NULL
  AND c.campaign_state_id = 2
GROUP BY c.id, c.title, b.name
HAVING total_moderado >= 10
  AND taxa_rejeicao >= 50
ORDER BY taxa_rejeicao DESC;
```

### Q6: Stalled Campaigns (no submissions in >7 days)
```sql
SELECT
  c.id,
  c.title AS campanha,
  b.name AS marca,
  MAX(a.created_at) AS ultima_submissao,
  DATEDIFF(NOW(), MAX(a.created_at)) AS dias_sem_submissao
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN actions a ON a.campaign_id = c.id
WHERE c.campaign_state_id = 2
  AND c.deleted_at IS NULL
GROUP BY c.id, c.title, b.name
HAVING ultima_submissao IS NOT NULL
  AND dias_sem_submissao >= 7
ORDER BY dias_sem_submissao DESC
LIMIT 5;
```

### Q7: Upcoming Deadlines (campaigns ending in 2-3 days)
```sql
SELECT
  c.id,
  c.title AS campanha,
  b.name AS marca,
  c.valid_until AS prazo,
  DATEDIFF(c.valid_until, NOW()) AS dias_restantes,
  (SELECT COUNT(DISTINCT a.creator_id)
   FROM actions a
   WHERE a.campaign_id = c.id) AS creators_ativos
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
WHERE c.campaign_state_id = 2
  AND c.valid_until IS NOT NULL
  AND c.valid_until BETWEEN NOW() AND NOW() + INTERVAL 3 DAY
  AND c.deleted_at IS NULL
ORDER BY dias_restantes ASC;
```

### Q8: Volume Comparison (yesterday vs same day last week)
```sql
SELECT
  DATE(pm.created_at) AS dia,
  COUNT(*) AS total,
  ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias pm
WHERE DATE(pm.created_at) IN (CURDATE() - INTERVAL 1 DAY, CURDATE() - INTERVAL 8 DAY)
  AND pm.deleted_at IS NULL
GROUP BY DATE(pm.created_at)
ORDER BY dia DESC;
```

## Slack Output Format

```
🌅 *Resumo Diário — [date]*

*📊 Volume de Ontem*
• Total moderado: X.XXX (↑/↓ Y% vs semana passada)
• Aprovação: XX,X%
• Contestações: XX (X,X%)
• Creators ativos: XXX

*🆕 Novas Campanhas (últimas 24h)*
• [Campanha] ([Marca]) — Budget: R$ X.XXX

*✅ Campanhas Finalizadas Ontem*
• [Campanha] ([Marca]) — XXX conteúdos aprovados

*🔥 Top Campanhas Ontem*
1. [Campanha] ([Marca]) — X.XXX conteúdos, XX% aprovação
2. ...

*⚠️ Alertas*
• [Campanha X] com taxa de rejeição de XX% (últimos 7d)
• [Campanha Y] sem submissões há X dias

*📅 Prazos Próximos (2-3 dias)*
• [Campanha] ([Marca]) — termina em X dias

_Dados: MySQL db-maestro-prod | Gerado automaticamente_
```

## Alert Rules

Flag ⚠️ when:
- Rejection rate >50% in last 7 days (min 10 moderations)
- No submissions in >7 days for active campaign
- Volume dropped >40% vs same day last week

Flag 🎉 when:
- New campaign launched
- Campaign completed with >100 approved submissions
- Record daily volume

Flag 📅 when:
- Campaign ends in ≤3 days

## Usage

```bash
# Generate today's digest
python generate.py

# JSON output (for automation)
python generate.py --format json

# Specific date
python generate.py --date 2026-03-05
```

## Automation

Add to Billy's crontab for daily delivery:
```bash
# Daily digest at 9:00 AM São Paulo time (12:00 UTC)
0 12 * * * cd /root/.openclaw/workspace/skills/daily-digest && python generate.py --slack-channel "#tech-gua-ma-internal" >> /var/log/billy/daily-digest.log 2>&1
```

## Safety
- READ ONLY queries
- Round financial data (R$ XX.XXX, not exact cents)
- Don't expose individual creator IDs/names
- Always cite data source
- Only queries db-maestro-prod (never writes)

## Integration
- Called automatically by Billy when user asks for daily summary
- Scheduled via cron for proactive morning delivery
- Outputs plain text for Slack or JSON for automation
- Can be triggered manually for ad-hoc checks
