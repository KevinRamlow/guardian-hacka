# Campaign Health Monitoring

Detect campaign anomalies: submission drops, high rejection rates, and stalled campaigns.

## When to Use
- "quais campanhas estão com problemas?"
- "campanha health check"
- "campanhas com baixa submissão"
- "campanhas paradas"
- "anomalias nas campanhas"
- "campanhas com alta rejeição"

## What It Detects

### 1. Submission Rate Drops
Compares last 7 days vs prior 7 days. Alerts when submissions drop by >40% (configurable).

**Example alert:**
> ⚠️ **Campanha XYZ** — Submissões caíram 55% na última semana (120 → 54)

### 2. High Rejection Rates
Flags campaigns with >50% rejection rate in last 30 days (min 10 submissions).

**Example alert:**
> 🚨 **Campanha ABC** — Taxa de rejeição em 68% (32 aprovados, 62 recusados)

### 3. Stalled Campaigns
Active campaigns with no submissions in >7 days.

**Example alert:**
> ⏸️ **Campanha DEF** — Sem submissões há 12 dias (última: 24/02)

## Configurable Thresholds

Default values (can override via environment variables):
- **Submission drop threshold:** 40% (`HEALTH_SUBMISSION_DROP_PCT=40`)
- **Rejection rate threshold:** 50% (`HEALTH_REJECTION_RATE_PCT=50`)
- **Stalled days threshold:** 7 (`HEALTH_STALLED_DAYS=7`)
- **Minimum submissions for rejection check:** 10 (`HEALTH_MIN_SUBMISSIONS=10`)

## Usage

```bash
# Check all active campaigns
./campaign-health.sh

# Check specific campaign
./campaign-health.sh --id 1234

# Custom thresholds
HEALTH_SUBMISSION_DROP_PCT=30 HEALTH_REJECTION_RATE_PCT=60 ./campaign-health.sh

# JSON output (for automation)
./campaign-health.sh --format json
```

## Query Details

### Submission Rate Trends
```sql
WITH last_7d AS (
  SELECT 
    c.id AS campaign_id,
    c.title,
    COUNT(DISTINCT a.id) AS submissions
  FROM campaigns c
  LEFT JOIN actions a ON a.campaign_id = c.id 
    AND a.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  WHERE c.campaign_state_id = 2
  GROUP BY c.id, c.title
),
prior_7d AS (
  SELECT 
    c.id AS campaign_id,
    COUNT(DISTINCT a.id) AS submissions
  FROM campaigns c
  LEFT JOIN actions a ON a.campaign_id = c.id 
    AND a.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
    AND a.created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)
  WHERE c.campaign_state_id = 2
  GROUP BY c.id
)
SELECT 
  l.campaign_id,
  l.title,
  l.submissions AS last_7d_submissions,
  COALESCE(p.submissions, 0) AS prior_7d_submissions,
  ROUND((l.submissions - COALESCE(p.submissions, 0)) / NULLIF(COALESCE(p.submissions, 0), 0) * 100, 1) AS pct_change
FROM last_7d l
LEFT JOIN prior_7d p ON p.campaign_id = l.campaign_id
WHERE COALESCE(p.submissions, 0) > 0
  AND l.submissions < COALESCE(p.submissions, 0) * (1 - ? / 100.0)
ORDER BY pct_change ASC;
```

### High Rejection Rates
```sql
SELECT 
  c.id AS campaign_id,
  c.title,
  COUNT(DISTINCT pm.id) AS total_moderated,
  SUM(pm.is_approved = 1) AS approved,
  SUM(pm.is_approved = 0) AS rejected,
  ROUND(SUM(pm.is_approved = 0) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS rejection_rate
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
WHERE c.campaign_state_id = 2
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title
HAVING total_moderated >= ?
  AND rejection_rate >= ?
ORDER BY rejection_rate DESC;
```

### Stalled Campaigns
```sql
SELECT 
  c.id AS campaign_id,
  c.title,
  MAX(a.created_at) AS last_submission,
  DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
WHERE c.campaign_state_id = 2
GROUP BY c.id, c.title
HAVING last_submission IS NULL OR days_since_last >= ?
ORDER BY days_since_last DESC;
```

## Response Format

Billy responds with bullet-point summaries:

```
🩺 Campaign Health Check — 3 alertas encontrados

⚠️ QUEDAS DE SUBMISSÃO (últimos 7d vs 7d anteriores)
• Campanha "Verão 2026" — queda de 52% (180 → 87 submissões)
• Campanha "Black Friday" — queda de 48% (240 → 125 submissões)

🚨 ALTAS TAXAS DE REJEIÇÃO (>50% nos últimos 30d)
• Campanha "Natal Premium" — 65% rejeição (28 aprovados, 52 recusados)

⏸️ CAMPANHAS PARADAS (sem submissões há >7 dias)
• Campanha "Inverno Frio" — 18 dias sem submissões (última: 18/02)
• Campanha "Primavera Leve" — 9 dias sem submissões (última: 26/02)

✅ Todas as outras campanhas ativas estão saudáveis.
```

If no anomalies found:
```
✅ Todas as campanhas ativas estão saudáveis — sem anomalias detectadas.
```

## Safety
- READ ONLY
- Only checks active campaigns (`campaign_state_id = 2`)
- No destructive actions
- Thresholds prevent false positives on small samples

## Integration
- Called automatically by Billy when user asks about campaign health
- Can be scheduled via cron for proactive alerts
- Outputs plain text for Slack or JSON for automation
