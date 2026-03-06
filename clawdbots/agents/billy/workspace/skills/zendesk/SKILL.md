---
name: zendesk
description: Zendesk ticket analytics for CS team workload, status, and response metrics.
homepage: https://www.zendesk.com
metadata: {"clawdis":{"emoji":"🎫","requires":{"env":["ZENDESK_SUBDOMAIN","ZENDESK_EMAIL","ZENDESK_API_TOKEN"]}}}
---

# Zendesk Ticket Analytics

Get CS team ticket metrics, workload distribution, and response time analytics.

## Setup

```bash
export ZENDESK_SUBDOMAIN="your-subdomain"  # e.g., "brandlovrs" for brandlovrs.zendesk.com
export ZENDESK_EMAIL="agent@company.com"    # Your Zendesk email
export ZENDESK_API_TOKEN="your-api-token"   # Generate at Admin > Channels > API
```

**Generate API Token:**
1. Go to Zendesk Admin Center
2. Navigate to Apps and integrations > APIs > Zendesk API
3. Click "Add API token"
4. Copy the token (save it securely — you won't see it again)

**Mock Mode:** If credentials are not configured, the script runs in mock mode with sample data for testing.

## Quick Commands

```bash
# Ticket Status
{baseDir}/scripts/zendesk.sh status           # Tickets by status (open/pending/solved)
{baseDir}/scripts/zendesk.sh status --json    # JSON output for parsing

# Categories & Tags
{baseDir}/scripts/zendesk.sh tags             # Top 10 ticket tags
{baseDir}/scripts/zendesk.sh categories       # Tickets by category/group

# Response Metrics
{baseDir}/scripts/zendesk.sh response-time    # Average response times by priority
{baseDir}/scripts/zendesk.sh sla              # SLA compliance metrics

# Team Workload
{baseDir}/scripts/zendesk.sh workload         # Ticket distribution by agent
{baseDir}/scripts/zendesk.sh workload --open  # Only open tickets per agent

# Time Ranges
{baseDir}/scripts/zendesk.sh status --days 7   # Last 7 days (default: 30)
{baseDir}/scripts/zendesk.sh workload --days 1 # Today only
```

## Common Use Cases

### Morning Standup
"Quantos tickets temos abertos hoje?"
```bash
{baseDir}/scripts/zendesk.sh status --days 1
```

### Weekly Review
"Como está a distribuição de carga do time essa semana?"
```bash
{baseDir}/scripts/zendesk.sh workload --days 7
```

### SLA Check
"Estamos dentro do SLA de resposta?"
```bash
{baseDir}/scripts/zendesk.sh sla
```

### Category Analysis
"Quais as principais categorias de tickets esse mês?"
```bash
{baseDir}/scripts/zendesk.sh categories
```

## Response Format

All outputs are formatted as **bullet-point summaries** (no tables) for easy reading in chat:

### Example: Status Query
> **Tickets — Últimos 30 dias**
> 
> • Abertos: 47 tickets
> • Pendentes: 23 tickets (aguardando resposta do cliente)
> • Resolvidos: 312 tickets
> • Taxa de resolução: 82%
> 
> _Fonte: Zendesk API • brandlovrs.zendesk.com_

### Example: Workload Query
> **Distribuição de Carga — Time CS**
> 
> • Ana Silva: 12 tickets abertos (3 high priority)
> • João Santos: 8 tickets abertos (1 high priority)
> • Maria Costa: 15 tickets abertos (5 high priority)
> • Pedro Lima: 10 tickets abertos (2 high priority)
> 
> **Total:** 45 tickets • **Média por agente:** 11 tickets
> 
> _Atualizado: 2026-03-06 12:45 UTC_

### Example: Response Time Query
> **Tempo de Resposta Médio — Últimos 7 dias**
> 
> • Urgent: 18 minutos
> • High: 1.2 horas
> • Normal: 4.5 horas
> • Low: 12 horas
> 
> **Meta de SLA:** ✅ 94% dentro do prazo
> 
> _Fonte: Zendesk SLA metrics_

## Query Capabilities

The skill supports:

### Ticket Counts by Status
- **Open** — active tickets needing attention
- **Pending** — waiting for customer response
- **On-hold** — paused/waiting for internal action
- **Solved** — resolved by agent
- **Closed** — verified resolved by customer

### Tickets by Category/Tag
- Top 10 most common tags
- Tickets by support group
- Tickets by priority (urgent/high/normal/low)

### Response Time Metrics
- First response time (by priority)
- Full resolution time
- Agent reply time
- Customer wait time

### CS Team Workload
- Tickets per agent (open/pending/total)
- Tickets by priority per agent
- Agent availability status
- Ticket assignment balance

## Mock Mode

When API credentials are not configured, the script generates realistic sample data:
- Randomized ticket counts
- Realistic agent names
- Plausible response times
- Sample tags and categories

**Mock mode indicator:** All responses include `[MOCK DATA]` prefix.

## API Details

- **Endpoint:** `https://{subdomain}.zendesk.com/api/v2/`
- **Auth:** Basic Auth (email + API token)
- **Rate Limit:** 700 requests/minute (Zendesk Enterprise)
- **Data Freshness:** Real-time (API queries on-demand)

## Safety & Privacy

- READ ONLY — no ticket modifications
- Agent names visible to team members only
- Customer PII (names, emails) NOT exposed
- Only aggregate metrics shared in chat
- API token stored securely in environment variables

## Troubleshooting

### "Authentication failed"
- Check `ZENDESK_SUBDOMAIN` matches your Zendesk URL
- Verify `ZENDESK_EMAIL` is correct
- Regenerate `ZENDESK_API_TOKEN` if expired

### "No tickets found"
- Try expanding time range: `--days 90`
- Check if your API user has permission to view tickets
- Verify tickets exist in the specified status

### "Rate limit exceeded"
- Zendesk API limits: 700 req/min (Enterprise), 200 req/min (Pro)
- Wait 60 seconds and retry
- Reduce query frequency

## Attribution

Built for Billy — AI assistant for non-tech teams at Brandlovrs.
