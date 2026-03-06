# Creator Churn Prediction & Alerts

Identify creators at risk of churning: declining submission frequency, long inactivity gaps, previously active creators now silent.

## When to Use
- "quais creators estão em risco de churn?"
- "creators com atividade em queda"
- "creators inativos"
- "creators que pararam de participar"
- "alerta de churn creators"
- "creators que sumiram"

## What It Detects

### 1. Declining Submission Frequency
Creators with significantly fewer submissions in last 30 days vs prior 30 days (>50% drop).

**Example alert:**
> ⚠️ **Creator #12345** — Submissões caíram 70% (20 → 6 nos últimos 30d)

### 2. Inactive Previously-Active Creators
Creators who had >5 submissions historically but ZERO in the last 30 days.

**Example alert:**
> 🚨 **Creator #67890** — 0 submissões nos últimos 30d (tinha 47 histórico total)

### 3. Long Gaps Since Last Submission
Creators with no submissions for >14, >30, or >60 days.

**Example alert:**
> ⏸️ **Creator #54321** — 42 dias sem submissão (última: 24/01/2026)

## Configurable Thresholds

Default values (can override via environment variables):
- **Decline threshold:** 50% (`CHURN_DECLINE_PCT=50`)
- **Min historical submissions for "active" status:** 5 (`CHURN_MIN_ACTIVE=5`)
- **Gap alert thresholds:** 14, 30, 60 days (`CHURN_GAP_WARN=14`, `CHURN_GAP_ALERT=30`, `CHURN_GAP_CRITICAL=60`)
- **Min submissions in prior period:** 3 (`CHURN_MIN_PRIOR=3`)

## Usage

```bash
# Check all creators for churn risk
./creator-churn.sh

# Check specific creator
./creator-churn.sh --creator 12345

# Custom thresholds
CHURN_DECLINE_PCT=40 CHURN_GAP_ALERT=21 ./creator-churn.sh

# JSON output (for automation)
./creator-churn.sh --format json

# Only show critical (>60d gap or previously active now silent)
./creator-churn.sh --critical-only
```

## Query Details

### 1. Declining Submission Frequency
```sql
WITH last_30d AS (
  SELECT 
    a.creator_id,
    COUNT(DISTINCT a.id) AS submissions
  FROM actions a
  WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    AND a.deleted_at IS NULL
  GROUP BY a.creator_id
),
prior_30d AS (
  SELECT 
    a.creator_id,
    COUNT(DISTINCT a.id) AS submissions
  FROM actions a
  WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY)
    AND a.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
    AND a.deleted_at IS NULL
  GROUP BY a.creator_id
)
SELECT 
  p.creator_id,
  COALESCE(l.submissions, 0) AS last_30d_submissions,
  p.submissions AS prior_30d_submissions,
  ROUND((p.submissions - COALESCE(l.submissions, 0)) / p.submissions * 100, 1) AS decline_pct,
  (SELECT MAX(created_at) FROM actions WHERE creator_id = p.creator_id AND deleted_at IS NULL) AS last_submission
FROM prior_30d p
LEFT JOIN last_30d l ON l.creator_id = p.creator_id
WHERE p.submissions >= ?
  AND COALESCE(l.submissions, 0) < p.submissions * (1 - ? / 100.0)
ORDER BY decline_pct DESC
LIMIT 50;
```

### 2. Inactive Previously-Active Creators
```sql
SELECT 
  a.creator_id,
  COUNT(DISTINCT a.id) AS total_submissions_all_time,
  MAX(a.created_at) AS last_submission,
  DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last,
  COUNT(DISTINCT pm.campaign_id) AS campaigns_participated
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.deleted_at IS NULL
GROUP BY a.creator_id
HAVING total_submissions_all_time >= ?
  AND last_submission < DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY days_since_last DESC
LIMIT 50;
```

### 3. Long Gaps Since Last Submission
```sql
SELECT 
  a.creator_id,
  MAX(a.created_at) AS last_submission,
  DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last,
  COUNT(DISTINCT a.id) AS total_submissions_all_time,
  COUNT(DISTINCT pm.campaign_id) AS campaigns_participated,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate
FROM actions a
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.deleted_at IS NULL
GROUP BY a.creator_id
HAVING last_submission < DATE_SUB(NOW(), INTERVAL ? DAY)
ORDER BY days_since_last DESC
LIMIT 50;
```

### 4. Submission Rate Trends (detailed view)
```sql
SELECT 
  a.creator_id,
  COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS last_30d,
  COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS prior_30d,
  COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 60 DAY) THEN a.id END) AS prior_60d,
  COUNT(DISTINCT a.id) AS total_all_time,
  MAX(a.created_at) AS last_submission,
  DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last
FROM actions a
WHERE a.deleted_at IS NULL
  AND a.creator_id = ?
GROUP BY a.creator_id;
```

### 5. At-Risk Summary (combined view)
```sql
-- Combines all risk factors into one summary
WITH creator_activity AS (
  SELECT 
    a.creator_id,
    COUNT(DISTINCT a.id) AS total_submissions,
    COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS last_30d,
    COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS prior_30d,
    MAX(a.created_at) AS last_submission,
    DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last
  FROM actions a
  WHERE a.deleted_at IS NULL
  GROUP BY a.creator_id
)
SELECT 
  creator_id,
  total_submissions,
  last_30d,
  prior_30d,
  last_submission,
  days_since_last,
  CASE 
    WHEN last_30d = 0 AND total_submissions >= 5 THEN 'CRITICAL: Previously active, now silent'
    WHEN days_since_last >= 60 THEN 'CRITICAL: 60+ days gap'
    WHEN days_since_last >= 30 THEN 'HIGH: 30+ days gap'
    WHEN prior_30d >= 3 AND last_30d < prior_30d * 0.5 THEN 'MEDIUM: 50%+ decline'
    WHEN days_since_last >= 14 THEN 'LOW: 14+ days gap'
    ELSE 'WATCH'
  END AS risk_level
FROM creator_activity
WHERE (last_30d = 0 AND total_submissions >= ?)
   OR (days_since_last >= ?)
   OR (prior_30d >= ? AND last_30d < prior_30d * (1 - ? / 100.0))
ORDER BY 
  CASE risk_level
    WHEN 'CRITICAL: Previously active, now silent' THEN 1
    WHEN 'CRITICAL: 60+ days gap' THEN 2
    WHEN 'HIGH: 30+ days gap' THEN 3
    WHEN 'MEDIUM: 50%+ decline' THEN 4
    WHEN 'LOW: 14+ days gap' THEN 5
    ELSE 6
  END,
  days_since_last DESC
LIMIT 100;
```

## Response Format

Billy responds with bullet-point summaries grouped by risk level:

```
🔴 Creator Churn Alert — 24 creators em risco

🚨 CRÍTICO (anteriormente ativos, agora silenciosos)
• Creator #12345 — 0 submissões nos últimos 30d (tinha 47 total | última: 15/01/2026, 50 dias atrás)
• Creator #67890 — 0 submissões nos últimos 30d (tinha 32 total | última: 08/01/2026, 57 dias atrás)
• Creator #54321 — 0 submissões nos últimos 30d (tinha 28 total | última: 22/01/2026, 43 dias atrás)

🔴 CRÍTICO (gap >60 dias)
• Creator #11111 — 72 dias sem submissão (tinha 15 total | última: 24/12/2025)
• Creator #22222 — 65 dias sem submissão (tinha 8 total | última: 31/12/2025)

🟠 ALTO (gap >30 dias)
• Creator #33333 — 42 dias sem submissão (tinha 19 total)
• Creator #44444 — 38 dias sem submissão (tinha 13 total)
• [+5 mais]

🟡 MÉDIO (queda >50% nas submissões)
• Creator #55555 — 20 → 6 submissões (queda de 70% nos últimos 30d)
• Creator #66666 — 15 → 5 submissões (queda de 67% nos últimos 30d)
• [+8 mais]

🟢 BAIXO (gap >14 dias)
• Creator #77777 — 18 dias sem submissão
• Creator #88888 — 16 dias sem submissão
• [+3 mais]

💡 Recomendação: priorizar reengajamento dos 5 críticos (anteriormente ativos, agora silenciosos)
```

If no at-risk creators found:
```
✅ Nenhum creator em risco crítico detectado — todos creators ativos estão engajados!
```

### Specific Creator Analysis
When checking a specific creator:
```
📊 Análise de Risco — Creator #12345

**Tendência de Submissões:**
• Últimos 30d: 6 submissões
• 30-60d atrás: 20 submissões
• 60-90d atrás: 18 submissões
• Total histórico: 142 submissões

**Status:**
• Última submissão: 02/03/2026 (4 dias atrás)
• Declínio: 70% nos últimos 30d vs 30d anteriores
• Campanhas participadas: 28

🔴 **RISCO: MÉDIO** — Queda significativa na atividade recente

💡 Recomendação: Entrar em contato para entender causa da queda
```

## Privacy Rules — CRITICAL
- **NEVER expose creator names, emails, or any PII**
- Use creator_id only (e.g., "Creator #12345")
- In group channels, anonymize even creator_ids: "X creators em risco crítico"
- Aggregate data is always safe to share
- Specific creator analysis: ONLY in DMs with authorized personnel

## Safety
- READ ONLY
- All queries use `deleted_at IS NULL` filters
- Queries are LIMIT-bound to prevent performance issues
- Thresholds prevent false positives on new/low-activity creators
- No destructive actions

## Automation Opportunities
- Daily digest of at-risk creators (scheduled cron)
- Weekly churn report sent to team channel
- Alert when a previously high-volume creator goes silent
- Integration with creator engagement campaigns

## Integration
- Called automatically by Billy when user asks about creator churn
- Can be scheduled via cron for proactive alerts (e.g., Monday morning reports)
- Outputs plain text for Slack or JSON for downstream automation
- Can feed into creator re-engagement workflows
