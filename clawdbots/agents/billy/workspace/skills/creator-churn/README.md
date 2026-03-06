# Creator Churn Prediction

Automated detection of creators at risk of churning from the platform.

## Quick Start

```bash
# Check all creators for churn risk
./creator-churn.sh

# Check specific creator
./creator-churn.sh --creator 12345

# Only show critical cases
./creator-churn.sh --critical-only

# JSON output for automation
./creator-churn.sh --format json
```

## What It Detects

1. **Critical Silent**: Previously active creators (>5 submissions) who haven't submitted anything in 30+ days
2. **Critical Gap**: Creators with 60+ days since last submission
3. **High Risk**: 30-60 days gap since last submission
4. **Medium Risk**: 50%+ decline in submission frequency (last 30d vs prior 30d)
5. **Low Risk**: 14-30 days gap since last submission

## Configuration

Adjust thresholds via environment variables:

```bash
# Alert if submissions dropped by >40% (default: 50%)
CHURN_DECLINE_PCT=40 ./creator-churn.sh

# Consider "active" if >10 submissions (default: 5)
CHURN_MIN_ACTIVE=10 ./creator-churn.sh

# Alert after 21 days gap (default: 30)
CHURN_GAP_ALERT=21 ./creator-churn.sh
```

All thresholds:
- `CHURN_DECLINE_PCT` - Decline % to trigger alert (default: 50)
- `CHURN_MIN_ACTIVE` - Min submissions to be "active" (default: 5)
- `CHURN_MIN_PRIOR` - Min submissions in prior period (default: 3)
- `CHURN_GAP_WARN` - Warning gap in days (default: 14)
- `CHURN_GAP_ALERT` - Alert gap in days (default: 30)
- `CHURN_GAP_CRITICAL` - Critical gap in days (default: 60)

## Automation

Schedule weekly reports:

```bash
# Add to crontab (Monday 9am)
0 9 * * 1 cd /path/to/skills/creator-churn && ./creator-churn.sh --critical-only
```

Or integrate with Billy's heartbeat for proactive alerts.

## Output Examples

### Summary (text)
```
🔴 Creator Churn Alert — 24 creators em risco

🚨 CRÍTICO (anteriormente ativos, agora silenciosos)
• Creator #12345 — 0 submissões nos últimos 30d (tinha 47 total | última: 15/01/2026, 50 dias atrás)
• Creator #67890 — 0 submissões nos últimos 30d (tinha 32 total | última: 08/01/2026, 57 dias atrás)

🟡 MÉDIO (queda >50% nas submissões)
• Creator #55555 — 20 → 6 submissões (queda de 70% nos últimos 30d)
```

### Specific Creator (text)
```
📊 Análise de Risco — Creator #12345

**Tendência de Submissões:**
• Últimos 30d: 6 submissões
• 30-60d atrás: 20 submissões
• Total histórico: 142 submissões

**Status:**
• Última submissão: 2026-03-02 (4 dias atrás)
• Campanhas participadas: 28

🔴 **RISCO: MÉDIO** — Queda de 70% na atividade recente
```

### JSON Output
```json
{
  "status": "at_risk",
  "at_risk_count": 24,
  "breakdown": {
    "critical_silent": 5,
    "critical_gap": 2,
    "high": 7,
    "medium": 8,
    "low": 2
  },
  "creators": [
    {
      "creator_id": 12345,
      "total_submissions": 47,
      "last_30d": 0,
      "prior_30d": 0,
      "last_submission": "2026-01-15",
      "days_since_last": 50,
      "risk_level": "CRITICAL_SILENT"
    }
  ]
}
```

## Privacy

- Always uses creator_id only (never names or emails)
- In group channels, aggregate counts are shared
- Individual creator details only in authorized DMs
- Read-only queries - no data modification

## Integration with Billy

Billy automatically invokes this skill when users ask:
- "quais creators estão em risco de churn?"
- "creators inativos"
- "creators que pararam de participar"
- "alerta de churn"

See `SKILL.md` for full query details and patterns.
