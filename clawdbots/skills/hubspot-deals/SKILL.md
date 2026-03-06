# HubSpot Deal Pipeline Queries

Query HubSpot deal pipelines, track deal stages, and identify opportunities needing attention.

## Purpose

Monitor sales pipeline across deal stages:
- **Qualified** — Leads that passed initial qualification
- **Proposal** — Quotes/proposals sent
- **Negotiation** — Active negotiations
- **Won** — Closed deals
- **Lost** — Lost opportunities

Alert on deals that may need follow-up:
- Deals stuck in a stage >30 days
- High-value deals with no recent activity
- Deals approaching expected close date

## Usage

### Query Deal Pipeline Status

**Summary by stage:**
```bash
./scripts/deals.sh summary
```

**Deals in specific stage:**
```bash
./scripts/deals.sh stage <stage_name>
# Examples:
./scripts/deals.sh stage proposal
./scripts/deals.sh stage negotiation
```

**Deals stuck in a stage:**
```bash
./scripts/deals.sh stuck <stage_name> <days>
# Examples:
./scripts/deals.sh stuck proposal 30
./scripts/deals.sh stuck negotiation 14
```

**High-value deals needing attention:**
```bash
./scripts/deals.sh alerts
```

**Timeline for specific deal:**
```bash
./scripts/deals.sh timeline <deal_id>
```

### Examples

```bash
# Get overview of all deals by stage
./scripts/deals.sh summary

# Show all deals in proposal stage
./scripts/deals.sh stage proposal

# Find deals stuck in negotiation >14 days
./scripts/deals.sh stuck negotiation 14

# Check all alert conditions (high-value, stuck, closing soon)
./scripts/deals.sh alerts

# View specific deal timeline
./scripts/deals.sh timeline 12345678901
```

## What Gets Tracked

### Deal Stages
- **appointmentscheduled**: Initial contact scheduled
- **qualifiedtobuy**: Lead qualified
- **presentationscheduled**: Demo/presentation scheduled
- **decisionmakerboughtin**: Decision maker engaged
- **contractsent**: Contract/proposal sent
- **closedwon**: Deal won
- **closedlost**: Deal lost

### Alert Conditions

**High Priority:**
- High-value deals (>$50k) stuck >14 days
- Deals in contract stage >30 days without update
- Deals with close date in next 7 days

**Medium Priority:**
- Deals in negotiation >21 days
- Qualified deals >45 days without progression

## Data Source

- **HubSpot API**: Deals, Pipelines, Deal Stages
- **Account ID**: 24386796 (from Slack references)
- **Authentication**: HubSpot API key (needs to be configured)

## API Configuration

To enable HubSpot API access, you need:

1. **HubSpot API Key** or **Private App Token**
   - Go to HubSpot → Settings → Integrations → API Keys
   - Create a Private App with `crm.objects.deals.read` scope
   - Copy the access token

2. **Store credentials:**
   ```bash
   echo "HUBSPOT_API_KEY=your-token-here" >> ~/.hubspot.env
   chmod 600 ~/.hubspot.env
   ```

3. **Test connection:**
   ```bash
   ./scripts/deals.sh test
   ```

## Output Format

### Summary
```
HubSpot Deal Pipeline Summary
==============================
Qualified:        23 deals ($1.2M)
Proposal:         15 deals ($850K)
Negotiation:      8 deals ($450K)
Won:              142 deals ($8.5M)
Lost:             67 deals ($2.1M)
```

### Deals by Stage
```
Deals in 'proposal' stage
==========================
ID            | Deal Name              | Amount   | Days in Stage | Owner
--------------|------------------------|----------|---------------|------------------
12345678901   | Claro Brasil Q1        | $250K    | 12            | João Silva
23456789012   | Americanas Campaign    | $180K    | 25            | Maria Santos
```

### Alerts
```
⚠️  ALERTS - Deals Needing Attention
====================================

HIGH PRIORITY:
- Deal #12345678901: $250K deal stuck in contract stage for 35 days
- Deal #23456789012: Closing in 3 days, no recent activity

MEDIUM PRIORITY:
- Deal #34567890123: In negotiation for 28 days
- Deal #45678901234: Qualified 50 days ago, no progression
```

## Billy Integration

Billy can use this skill to:
- Answer "how many deals are in proposal stage?"
- Show pipeline health metrics
- Alert sales team on stuck deals
- Track high-value opportunities
- Generate weekly pipeline reports

## Notes

- **API Rate Limits**: HubSpot allows 100 requests per 10 seconds
- **Mock Mode**: If API credentials not configured, script returns mock data for testing
- **Stage Names**: Actual stage names depend on your HubSpot pipeline configuration
- **Currency**: Assumes USD, adjust if using other currencies
- **Deal Amount**: Uses `amount` property from HubSpot deals

## Troubleshooting

If you get authentication errors:
1. Verify `~/.hubspot.env` exists and has valid token
2. Check token has `crm.objects.deals.read` scope
3. Test with: `curl -H "Authorization: Bearer YOUR_TOKEN" https://api.hubapi.com/crm/v3/objects/deals`

If stages don't match:
1. Get your pipeline stages: `./scripts/deals.sh pipelines`
2. Update stage names in SKILL.md to match your HubSpot setup
