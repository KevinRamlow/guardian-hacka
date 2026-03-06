# Revenue Forecasting Skill

Historical revenue analysis and forward projection for Brandlovrs campaigns.

## Quick Start

```bash
# View revenue trend for last 6 months (default)
./revenue-forecasting.sh --trend

# Forecast next 3 months
./revenue-forecasting.sh --forecast

# Full report (trend + forecast)
./revenue-forecasting.sh --full-report
```

## Options

### Mode
- `--trend` — Show historical revenue trends (default)
- `--forecast` — Project future revenue
- `--full-report` — Combined trend + forecast

### Filters
- `--months N` — Historical period (default: 6)
- `--periods N` — Forecast periods (default: 3)
- `--brand "Name"` — Filter by brand
- `--campaign ID` — Filter by campaign

### Output
- `--format slack` — Human-readable (default)
- `--format json` — Machine-readable

## Examples

### Strategic Planning
```bash
# Board presentation: last 12 months + next quarter forecast
./revenue-forecasting.sh --full-report --months 12 --periods 3

# Investor update: revenue trend with top brands
./revenue-forecasting.sh --trend --months 12
```

### Brand Analysis
```bash
# How is this brand trending?
./revenue-forecasting.sh --trend --brand "Pantene" --months 6

# Project next quarter for specific brand
./revenue-forecasting.sh --forecast --brand "Pantene" --periods 3
```

### Campaign Performance
```bash
# Campaign revenue over time
./revenue-forecasting.sh --trend --campaign 1234 --months 3
```

### API/Automation
```bash
# JSON output for dashboards
./revenue-forecasting.sh --trend --format json > revenue.json
./revenue-forecasting.sh --forecast --format json > forecast.json
```

## Forecasting Methods

### Linear Growth Projection
- Calculates average monthly growth rate from historical data
- Projects forward using compound growth
- Includes confidence range based on historical volatility

### Assumptions
- Maintains current growth trajectory
- Does not account for seasonality
- Based on campaigns already active/known
- Volatility capped at ±25% for realistic ranges

## Data Sources

**MySQL Tables:**
- `creator_payment_history` — Payment transactions
- `campaigns` — Campaign details
- `brands` — Brand information

**Payment Status Included:**
- `complete` — Fully paid
- `partial` — Partially paid
- Excludes `in_process` (pending)

## Billy Integration

Billy automatically:
1. Recognizes revenue/GMV questions
2. Selects appropriate mode (trend vs forecast)
3. Applies filters based on context
4. Returns formatted results in pt-BR

### Example Queries
- "qual foi a receita dos últimos 6 meses?" → `--trend --months 6`
- "forecast de GMV próximo trimestre" → `--forecast --periods 3`
- "tendência de revenue da marca Pantene" → `--trend --brand "Pantene"`
- "quanto vamos faturar no próximo mês?" → `--forecast --periods 1`

## Safety

- READ ONLY queries (no data modifications)
- Historical data only (no future dates in DB)
- Projections clearly marked as estimates
- Currency handling (BRL default)
- No PII in output

## Testing

```bash
# Smoke test
./revenue-forecasting.sh --trend --months 3

# Full validation
./revenue-forecasting.sh --full-report --months 6 --periods 3

# JSON format
./revenue-forecasting.sh --trend --format json | jq .
```

## Troubleshooting

**No data returned:**
- Check time period (may be no payments in that window)
- Verify brand/campaign filters are correct
- Confirm MySQL credentials in ~/.my.cnf

**Wild forecast numbers:**
- High volatility in recent data causes wide ranges
- Try longer historical period (--months 12)
- Review actual trends first (--trend) before trusting forecast

**Currency issues:**
- Script assumes BRL by default
- Mixed currencies in DB are summed (be cautious)
- For USD campaigns, filter by specific campaign/brand
