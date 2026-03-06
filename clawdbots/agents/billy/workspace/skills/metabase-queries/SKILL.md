# Metabase Queries Replacement

Pre-built SQL queries for common Metabase dashboards. Direct MySQL/BigQuery execution for instant answers to frequently asked business questions.

## When to Use
- User asks questions that would normally require Metabase
- "quantas campanhas ativas temos?"
- "qual é o GMV total?"
- "quantos criadores se cadastraram essa semana?"
- "como está a fila de moderação?"
- "quais campanhas têm mais engajamento?"

## Coverage

This skill replaces these common Metabase queries:
1. **Campaign counts by status** — Active/draft/completed campaigns
2. **Total GMV/Revenue** — Overall and by time period
3. **Creator signup counts** — New creators by period
4. **Moderation queue stats** — Pending, in review, completed
5. **Top campaigns by engagement** — Most active campaigns

---

## Query Patterns

### 1. Campaign Counts by Status

**Question:** "quantas campanhas ativas/draft/finalizadas temos?"

```sql
-- All campaign counts by status
SELECT 
  campaign_state_id AS status,
  COUNT(*) AS total
FROM campaigns
WHERE deleted_at IS NULL
GROUP BY campaign_state_id
ORDER BY total DESC;
```

**Recent campaigns (last 30 days):**
```sql
SELECT 
  campaign_state_id AS status,
  COUNT(*) AS total,
  COUNT(CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 END) AS ultimos_7d,
  COUNT(CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 END) AS ultimos_30d
FROM campaigns
WHERE deleted_at IS NULL
GROUP BY campaign_state_id
ORDER BY total DESC;
```

**Response format:**
> Atualmente temos:
> - **342 campanhas ativas** (12 criadas nos últimos 7 dias)
> - 128 campanhas finalizadas
> - 47 campanhas em draft
> 
> Total: 517 campanhas

---

### 2. Total GMV / Revenue

**Question:** "qual é o GMV total?" / "quanto já pagamos aos criadores?"

```sql
-- Total GMV (all time)
SELECT 
  value_currency AS moeda,
  COUNT(DISTINCT creator_id) AS criadores_pagos,
  COUNT(*) AS total_pagamentos,
  ROUND(SUM(value), 2) AS gmv_net,
  ROUND(SUM(gross_value), 2) AS gmv_gross,
  ROUND(AVG(value), 2) AS pagamento_medio
FROM creator_payment_history
WHERE payment_status IN ('complete', 'partial')
GROUP BY value_currency;
```

**GMV by period:**
```sql
-- GMV últimos 30/90 dias
SELECT 
  CASE 
    WHEN created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 'ultimos_7d'
    WHEN created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'ultimos_30d'
    WHEN created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY) THEN 'ultimos_90d'
    ELSE 'anteriores'
  END AS periodo,
  COUNT(DISTINCT creator_id) AS criadores,
  ROUND(SUM(value), 2) AS gmv_net,
  ROUND(SUM(gross_value), 2) AS gmv_gross
FROM creator_payment_history
WHERE payment_status IN ('complete', 'partial')
  AND created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY periodo
ORDER BY 
  CASE periodo
    WHEN 'ultimos_7d' THEN 1
    WHEN 'ultimos_30d' THEN 2
    WHEN 'ultimos_90d' THEN 3
    ELSE 4
  END;
```

**GMV by campaign (top 20):**
```sql
SELECT 
  c.title AS campanha,
  c.campaign_state_id AS status,
  COUNT(DISTINCT cph.creator_id) AS criadores_pagos,
  ROUND(SUM(cph.value), 2) AS gmv_net,
  ROUND(SUM(cph.gross_value), 2) AS gmv_gross,
  cph.value_currency AS moeda
FROM campaigns c
JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE cph.payment_status IN ('complete', 'partial')
GROUP BY c.id, c.title, c.campaign_state_id, cph.value_currency
ORDER BY gmv_net DESC
LIMIT 20;
```

**Response format:**
> GMV Total: **R$ 1.247.382,00** (net) | **R$ 1.450.120,00** (gross)
> 
> **Últimos 30 dias:** R$ 215.340,00 (427 criadores pagos)
> **Últimos 7 dias:** R$ 52.180,00 (89 criadores)
> 
> Pagamento médio: R$ 342,00
> 
> _Fonte: creator_payment_history (status: complete, partial)_

---

### 3. Creator Signup Counts

**Question:** "quantos criadores se cadastraram essa semana/mês?"

```sql
-- Creator signups por período
SELECT 
  DATE_FORMAT(created_at, '%Y-%m') AS mes,
  COUNT(*) AS novos_criadores,
  COUNT(CASE WHEN onboarding_completed = 1 THEN 1 END) AS com_onboarding_completo
FROM creators
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
GROUP BY DATE_FORMAT(created_at, '%Y-%m')
ORDER BY mes DESC;
```

**This week vs last week:**
```sql
SELECT 
  CASE 
    WHEN created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 'esta_semana'
    WHEN created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY) THEN 'semana_passada'
  END AS periodo,
  COUNT(*) AS novos_criadores,
  COUNT(CASE WHEN onboarding_completed = 1 THEN 1 END) AS onboarding_completo,
  ROUND(COUNT(CASE WHEN onboarding_completed = 1 THEN 1 END) / COUNT(*) * 100, 1) AS taxa_completude
FROM creators
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
GROUP BY periodo
ORDER BY 
  CASE periodo
    WHEN 'esta_semana' THEN 1
    WHEN 'semana_passada' THEN 2
  END;
```

**Daily signups (last 7 days):**
```sql
SELECT 
  DATE(created_at) AS dia,
  COUNT(*) AS novos_criadores
FROM creators
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at)
ORDER BY dia DESC;
```

**Response format:**
> **Esta semana:** 127 novos criadores (84 completaram onboarding — 66,1%)
> **Semana passada:** 142 novos criadores (91 completaram — 64,1%)
> 
> Variação: -10,6% no total de signups
> Taxa de completude: +2pp ✅
> 
> Nos últimos 30 dias: 542 novos criadores

---

### 4. Moderation Queue Stats

**Question:** "como está a fila de moderação?" / "quantos conteúdos pendentes?"

```sql
-- Moderation queue overview
SELECT 
  CASE 
    WHEN pm.is_approved IS NULL THEN 'pendente'
    WHEN pm.is_approved = 1 THEN 'aprovado'
    WHEN pm.is_approved = 0 AND pmc.id IS NOT NULL THEN 'recusado_contestado'
    WHEN pm.is_approved = 0 THEN 'recusado'
  END AS status,
  COUNT(*) AS total,
  COUNT(CASE WHEN pm.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR) THEN 1 END) AS ultimas_24h,
  COUNT(CASE WHEN pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 END) AS ultimos_7d
FROM proofread_medias pm
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.deleted_at IS NULL
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY status
ORDER BY 
  CASE status
    WHEN 'pendente' THEN 1
    WHEN 'recusado_contestado' THEN 2
    WHEN 'aprovado' THEN 3
    WHEN 'recusado' THEN 4
  END;
```

**Pending by campaign (top 10):**
```sql
SELECT 
  c.title AS campanha,
  COUNT(pm.id) AS pendentes,
  MIN(pm.created_at) AS mais_antigo
FROM proofread_medias pm
JOIN campaigns c ON pm.campaign_id = c.id
WHERE pm.is_approved IS NULL
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title
ORDER BY pendentes DESC, mais_antigo ASC
LIMIT 10;
```

**Average moderation time (last 7 days):**
```sql
SELECT 
  ROUND(AVG(TIMESTAMPDIFF(MINUTE, pm.created_at, pm.updated_at)), 1) AS tempo_medio_minutos,
  ROUND(AVG(TIMESTAMPDIFF(HOUR, pm.created_at, pm.updated_at)), 1) AS tempo_medio_horas,
  MIN(TIMESTAMPDIFF(MINUTE, pm.created_at, pm.updated_at)) AS mais_rapido_min,
  MAX(TIMESTAMPDIFF(HOUR, pm.created_at, pm.updated_at)) AS mais_lento_horas
FROM proofread_medias pm
WHERE pm.is_approved IS NOT NULL
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND pm.deleted_at IS NULL;
```

**Response format:**
> 📋 Fila de Moderação (últimos 30 dias):
> 
> **Pendentes:** 342 conteúdos
> - Últimas 24h: 78
> - Mais antigo: 2 dias atrás
> 
> **Processados:**
> - Aprovados: 2.847 (78,3%)
> - Recusados: 788 (21,7%)
> - Contestados: 42 (5,3% das recusas)
> 
> **Tempo médio de moderação:** 2,3 horas
> (mais rápido: 5 min | mais lento: 18 horas)

---

### 5. Top Campaigns by Engagement

**Question:** "quais campanhas têm mais engajamento?" / "campanhas mais ativas"

```sql
-- Top campaigns by content submissions (last 30 days)
SELECT 
  c.title AS campanha,
  c.campaign_state_id AS status,
  b.name AS marca,
  COUNT(DISTINCT pm.creator_id) AS criadores_ativos,
  COUNT(pm.id) AS conteudos_submetidos,
  SUM(pm.is_approved = 1) AS aprovados,
  SUM(pm.is_approved = 0) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  COUNT(DISTINCT pmc.id) AS contestacoes,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_contestacao
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id 
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.campaign_state_id = 'active'
GROUP BY c.id, c.title, c.campaign_state_id, b.name
HAVING conteudos_submetidos > 0
ORDER BY conteudos_submetidos DESC
LIMIT 15;
```

**Top by creator participation:**
```sql
SELECT 
  c.title AS campanha,
  b.name AS marca,
  COUNT(DISTINCT pm.creator_id) AS criadores_unicos,
  COUNT(pm.id) AS conteudos,
  ROUND(COUNT(pm.id) / NULLIF(COUNT(DISTINCT pm.creator_id), 0), 1) AS conteudos_por_criador
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id 
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
WHERE c.campaign_state_id = 'active'
GROUP BY c.id, c.title, b.name
HAVING criadores_unicos > 0
ORDER BY criadores_unicos DESC
LIMIT 15;
```

**Response format:**
> 🔥 Top 10 Campanhas (últimos 30 dias):
> 
> **1. Summer Vibes 2026** (Natura)
>    - 1.234 conteúdos | 142 criadores ativos
>    - Taxa aprovação: 82,3% | Contestações: 1,5%
> 
> **2. Black Friday Deals** (Magazine Luiza)
>    - 987 conteúdos | 118 criadores
>    - Taxa aprovação: 76,1% | Contestações: 3,2%
> 
> **3. Verão Sem Fim** (O Boticário)
>    - 856 conteúdos | 97 criadores
>    - Taxa aprovação: 88,5% | Contestações: 0,8%
> 
> _Ordenado por volume de conteúdo submetido_

---

## Automation Script (Optional)

For instant answers, use the companion script:

```bash
# Quick stats
./metabase-queries.sh --quick

# Specific query
./metabase-queries.sh --query campaigns
./metabase-queries.sh --query gmv
./metabase-queries.sh --query creators
./metabase-queries.sh --query moderation
./metabase-queries.sh --query top-campaigns

# All queries
./metabase-queries.sh --all

# JSON output
./metabase-queries.sh --query gmv --format json
```

---

## Response Guidelines

1. **Always include context** — "compared to last week", "above platform average"
2. **Translate numbers to business language** — not just "2847", but "quase 3 mil conteúdos"
3. **Highlight anomalies** — sudden drops, spikes, unusual patterns
4. **Add actionable insights** — "a taxa está caindo, talvez revisar guidelines?"
5. **Source attribution** — mention which table/database

Example good response:
> GMV dos últimos 30 dias: **R$ 215.340,00** — **23% acima** do mês anterior! 🚀
> 
> Campanhas que puxaram: Summer Vibes (R$ 42k), Black Friday (R$ 38k)
> 
> 427 criadores receberam pagamento (média R$ 504/criador)
> 
> _Fonte: creator_payment_history (complete + partial payments)_

---

## Safety & Privacy

- **READ ONLY** — never modify data
- **No PII** — mask creator names/emails in summaries
- **Add LIMIT** — default 100 for lists
- **Warn on expensive queries** — large date ranges on BigQuery
- **Aggregate only** — individual creator data only when specifically requested

---

## Migration from Metabase

| Metabase Dashboard | This Skill Query |
|--------------------|------------------|
| "Campaign Status Overview" | Query #1: Campaign Counts by Status |
| "Total GMV & Revenue" | Query #2: Total GMV / Revenue |
| "Creator Growth" | Query #3: Creator Signup Counts |
| "Moderation Queue" | Query #4: Moderation Queue Stats |
| "Top Campaigns" | Query #5: Top Campaigns by Engagement |

**Advantages over Metabase:**
- ✅ Instant answers in Slack (no need to open browser)
- ✅ Conversational queries (plain language)
- ✅ Always fresh data (direct DB queries)
- ✅ Customizable on the fly (can modify queries per request)
- ✅ Context-aware responses (Billy knows recent trends)

**When to still use Metabase:**
- Complex multi-table joins not covered here
- Visual charts/graphs needed
- Exploratory analysis (drilling down)
- Custom date range filters not pre-built
