# Revenue Forecasting & GMV Tracking

Historical revenue analysis, trend calculation, and forward projection for campaigns, brands, and overall platform.

## When to Use
- "qual foi a receita dos últimos 6 meses?"
- "forecast de GMV para o próximo trimestre"
- "tendência de revenue por marca"
- "projeção de faturamento próximos 3 meses"
- "crescimento de GMV mês a mês"
- "quanto vamos faturar no próximo mês?"

## What It Shows

**Historical Analysis:**
1. **Revenue Trends** — Monthly/quarterly GMV over last 3/6/12 months
2. **Growth Rates** — Month-over-month and year-over-year growth
3. **By Brand** — Revenue breakdown per brand
4. **By Campaign** — Top revenue-generating campaigns

**Forecasting:**
1. **Linear Projection** — Simple trend-based forecast (1-3 months ahead)
2. **Growth Rate Method** — Project based on average growth rate
3. **Confidence Range** — Min/max estimates based on volatility

## Usage

```bash
# Revenue trend (last 6 months by default)
./revenue-forecasting.sh --trend

# Specific period
./revenue-forecasting.sh --trend --months 12

# Forecast next 3 months
./revenue-forecasting.sh --forecast --periods 3

# By brand
./revenue-forecasting.sh --trend --brand "Brand Name"

# By campaign
./revenue-forecasting.sh --trend --campaign 1234

# Full report (trend + forecast)
./revenue-forecasting.sh --full-report

# JSON output
./revenue-forecasting.sh --trend --format json
```

## Query Details

### Monthly Revenue (MySQL)
```sql
SELECT 
  DATE_FORMAT(cph.date_of_transaction, '%Y-%m') AS month,
  COUNT(DISTINCT cph.campaign_id) AS campaigns,
  COUNT(DISTINCT cph.creator_id) AS creators,
  ROUND(SUM(cph.value), 2) AS revenue_net,
  ROUND(SUM(cph.gross_value), 2) AS revenue_gross,
  cph.value_currency AS currency
FROM creator_payment_history cph
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL ? MONTH)
  AND cph.payment_status IN ('complete', 'partial')
GROUP BY month, currency
ORDER BY month ASC;
```

### Revenue by Brand
```sql
SELECT 
  b.name AS brand,
  DATE_FORMAT(cph.date_of_transaction, '%Y-%m') AS month,
  ROUND(SUM(cph.value), 2) AS revenue_net,
  COUNT(DISTINCT cph.campaign_id) AS campaigns,
  COUNT(DISTINCT cph.creator_id) AS creators
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL ? MONTH)
  AND cph.payment_status IN ('complete', 'partial')
GROUP BY b.id, b.name, month
ORDER BY month ASC, revenue_net DESC;
```

### Top Campaigns by Revenue
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign,
  b.name AS brand,
  DATE_FORMAT(cph.date_of_transaction, '%Y-%m') AS month,
  ROUND(SUM(cph.value), 2) AS revenue_net,
  COUNT(DISTINCT cph.creator_id) AS creators
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL ? MONTH)
  AND cph.payment_status IN ('complete', 'partial')
GROUP BY c.id, c.title, b.name, month
ORDER BY revenue_net DESC
LIMIT 20;
```

## Forecasting Methods

### 1. Linear Regression (Simple Trend)
```
y = mx + b
where m = slope (trend), b = intercept
```
Fit a line to historical monthly revenue, project forward.

### 2. Growth Rate Method
```
forecast = last_month_revenue * (1 + avg_growth_rate)^periods
```
Calculate average monthly growth rate, compound forward.

### 3. Confidence Range
```
min = forecast * (1 - volatility)
max = forecast * (1 + volatility)
```
Volatility = standard deviation / mean of historical growth rates.

## Response Format (Slack)

### Trend Report
```
📈 Tendência de Revenue - Últimos 6 Meses

💰 RESUMO
• Total Período: R$ 2.847.300,00
• Média Mensal: R$ 474.550,00
• Crescimento Médio: +8,3% m/m
• Campanhas Ativas: 127
• Creators Pagos: 1.834

📊 MÊS A MÊS
• 2026-09: R$ 412.300,00 (+12,5%)
• 2026-08: R$ 366.400,00 (+5,2%)
• 2026-07: R$ 348.200,00 (+3,1%)
• 2026-06: R$ 337.700,00 (+9,8%)
• 2026-05: R$ 307.500,00 (+6,4%)
• 2026-04: R$ 289.100,00 (baseline)

🏆 TOP 3 BRANDS
1. Brand A: R$ 847.200,00 (29,7%)
2. Brand B: R$ 612.500,00 (21,5%)
3. Brand C: R$ 488.900,00 (17,2%)
```

### Forecast Report
```
🔮 Projeção de Revenue - Próximos 3 Meses

💡 MÉTODO
• Base: Últimos 6 meses
• Crescimento Médio: +8,3% m/m
• Volatilidade: ±12%

📊 PROJEÇÃO
• 2026-10: R$ 446.500,00 (min: R$ 393.000 | max: R$ 500.000)
• 2026-11: R$ 483.500,00 (min: R$ 425.000 | max: R$ 542.000)
• 2026-12: R$ 523.600,00 (min: R$ 461.000 | max: R$ 586.000)

💰 TOTAL PROJETADO (Q4): R$ 1.453.600,00

⚠️ PREMISSAS
• Mantém crescimento atual de +8,3% m/m
• Não considera sazonalidade (Q4 pode ter aceleração)
• Baseado em campanhas já ativas + pipeline conhecido
```

## Safety
- READ ONLY queries
- Historical data only (no future dates in DB)
- Projections clearly marked as estimates
- Confidence ranges included
- No PII in output
- Currency handling (BRL default, USD when needed)

## Comparison to Existing Skills
- **campaign-performance** → Single campaign dashboard (snapshot)
- **data-query** → Ad-hoc queries (flexible but requires SQL knowledge)
- **revenue-forecasting** → Multi-period trends + forward projection (strategic planning)

Use revenue-forecasting when:
- Planning budgets for next quarter
- Board presentations
- Investor updates
- Strategic decisions based on trends
