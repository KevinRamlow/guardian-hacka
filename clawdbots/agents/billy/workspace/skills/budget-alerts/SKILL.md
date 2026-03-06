# Budget Alerts Skill

Monitor campaign spend vs budget and alert when approaching or exceeding limits.

## When to Use
- "quais campanhas estão perto do limite de budget?"
- "alguma campanha estourou o orçamento?"
- "me mostra as campanhas com gasto alto"
- "check campaign budgets"
- "budget violations"

## Alert Thresholds
- **⚠️ Warning (80-99%)** — Approaching budget limit
- **🚨 Critical (100-109%)** — Budget exceeded
- **🔥 Severe (110%+)** — Seriously over budget

## Query Logic

### All campaigns with budget violations (≥80%)
```sql
SELECT 
  c.id,
  c.title,
  c.budget,
  COALESCE(SUM(cph.value), 0) AS total_spend,
  ROUND((COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100, 1) AS budget_used_pct,
  CASE 
    WHEN (COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100 >= 110 THEN '🔥 SEVERE'
    WHEN (COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100 >= 100 THEN '🚨 CRITICAL'
    WHEN (COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100 >= 80 THEN '⚠️ WARNING'
    ELSE 'OK'
  END AS alert_level
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.budget > 0
GROUP BY c.id, c.title, c.budget
HAVING budget_used_pct >= 80
ORDER BY budget_used_pct DESC;
```

### Breakdown by alert level
```sql
SELECT 
  CASE 
    WHEN budget_used_pct >= 110 THEN '🔥 SEVERE (110%+)'
    WHEN budget_used_pct >= 100 THEN '🚨 CRITICAL (100-109%)'
    WHEN budget_used_pct >= 80 THEN '⚠️ WARNING (80-99%)'
    ELSE 'OK (<80%)'
  END AS alert_level,
  COUNT(*) AS campaign_count,
  SUM(total_spend - budget) AS total_overspend
FROM (
  SELECT 
    c.id,
    c.budget,
    COALESCE(SUM(cph.value), 0) AS total_spend,
    ROUND((COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100, 1) AS budget_used_pct
  FROM campaigns c
  LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
  WHERE c.budget > 0
  GROUP BY c.id, c.budget
) AS campaign_spend
GROUP BY alert_level
ORDER BY 
  CASE alert_level
    WHEN '🔥 SEVERE (110%+)' THEN 1
    WHEN '🚨 CRITICAL (100-109%)' THEN 2
    WHEN '⚠️ WARNING (80-99%)' THEN 3
    ELSE 4
  END;
```

### Top 10 worst budget violations
```sql
SELECT 
  c.id,
  c.title,
  c.budget,
  COALESCE(SUM(cph.value), 0) AS total_spend,
  ROUND(COALESCE(SUM(cph.value), 0) - c.budget, 2) AS overspend,
  ROUND((COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100, 1) AS budget_used_pct
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.budget > 0
GROUP BY c.id, c.title, c.budget
HAVING total_spend > budget
ORDER BY overspend DESC
LIMIT 10;
```

### Campaigns by brand (filter by brand)
```sql
SELECT 
  b.name AS brand,
  c.id AS campaign_id,
  c.title AS campaign,
  c.budget,
  COALESCE(SUM(cph.value), 0) AS total_spend,
  ROUND((COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0)) * 100, 1) AS budget_used_pct
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.budget > 0
  AND b.name LIKE '%BRAND_NAME%'
GROUP BY b.name, c.id, c.title, c.budget
HAVING budget_used_pct >= 80
ORDER BY budget_used_pct DESC;
```

## Response Format

Always format as **bullet-point summaries**, NO TABLES:

### Summary Format:
> **Budget Status Report** — [date/time]
> 
> **🔥 SEVERE (≥110%):** 45 campaigns
> - Total overspend: R$ 2.4M
> 
> **🚨 CRITICAL (100-109%):** 23 campaigns
> - Total overspend: R$ 543K
> 
> **⚠️ WARNING (80-99%):** 102 campaigns
> - Approaching limits
> 
> **Top 3 Worst:**
> - Campaign #500340 "Mercado Livre - Moda e Beleza": R$ 83K budget → R$ 6.8M spent (8200% utilization) 🔥
> - Campaign #500377 "Amazon - Valentine's": R$ 16K budget → R$ 1.2M spent (8000% utilization) 🔥
> - Campaign #500456 "Mercado Livre - Moda e Beleza II": R$ 1.8K budget → R$ 150K spent (8000% utilization) 🔥

### Individual Campaign Format:
> **Campanha #500340** — "Mercado Livre - Moda e Beleza"
> - Budget: R$ 83.333,00
> - Gasto: R$ 6.833.306,00
> - Utilização: 8200% 🔥
> - Estouro: R$ 6.749.973,00

## Safety
- READ ONLY
- Don't modify budgets or payments
- Alert format should be clear and actionable
- Include campaign IDs for tracking
