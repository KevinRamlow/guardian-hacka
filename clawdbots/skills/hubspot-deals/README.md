# HubSpot Deals Skill for Billy

Query HubSpot deal pipelines to help sales and business teams track opportunities.

## Quick Start

```bash
# Get pipeline summary
./scripts/deals.sh summary

# Show deals in a specific stage
./scripts/deals.sh stage proposal

# Find stuck deals
./scripts/deals.sh stuck negotiation 14

# Show high-priority alerts
./scripts/deals.sh alerts
```

## Setup

### Option 1: With HubSpot API (Production)

1. Get HubSpot API token:
   - Go to HubSpot → Settings → Integrations → Private Apps
   - Create app with `crm.objects.deals.read` scope
   - Copy the access token

2. Configure credentials:
   ```bash
   echo "HUBSPOT_API_KEY=pat-na1-your-token-here" > ~/.hubspot.env
   chmod 600 ~/.hubspot.env
   ```

3. Test connection:
   ```bash
   ./scripts/deals.sh test
   ```

### Option 2: Mock Mode (Testing)

If no API key is configured, the skill automatically uses mock data. Perfect for:
- Testing Billy integration
- Demo purposes
- Development without API access

## Billy Use Cases

Billy can help teams by:
- "How many deals are in proposal stage?"
- "Show me deals stuck in negotiation"
- "What high-value deals need attention?"
- "Give me a pipeline summary"

## Files

- `SKILL.md` - Full documentation
- `scripts/deals.sh` - Main query script
- `README.md` - This file

## Deployment

Deploy to Billy VM:
```bash
rsync -av /root/.openclaw/workspace/clawdbots/skills/ root@89.167.64.183:/root/.openclaw/workspace/skills/
```

## Notes

- Mock mode is automatic when API key not found
- Real API requires HubSpot Private App token
- Stage names may vary by HubSpot configuration
- Account ID: 24386796 (from Brandlovrs)
