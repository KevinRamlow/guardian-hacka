# Sales Enablement Skill

**Purpose:** Generate pitch-ready campaign success stories with metrics (ROI, engagement, creator counts, approval rates) for sales presentations.

## Quick Start

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/sales-enablement

# Top 10 campaigns (last 6 months, by approval rate)
./sales-enablement.sh --top 10

# Best campaigns for a specific brand
./sales-enablement.sh --brand "Natura"

# Single campaign success story
./sales-enablement.sh --campaign-id 501092

# Top campaigns sorted by different metrics
./sales-enablement.sh --top 5 --metric creators
./sales-enablement.sh --top 5 --metric approval_rate
./sales-enablement.sh --top 5 --metric roi
```

## Usage Examples

### Example 1: Top Performing Campaigns
```bash
./sales-enablement.sh --top 5
```
**Output:** List of top 5 campaigns with:
- Creator count & content volume
- Approval rate
- Investment & duration
- Key highlights

### Example 2: Brand Performance Summary
```bash
./sales-enablement.sh --brand "Bacio Di Latte"
```
**Output:** Brand overview with:
- All campaigns from last 12 months
- Aggregate stats (total creators, content, investment)
- Top 3 performing campaigns
- Pitch-ready narrative

### Example 3: Single Campaign Deep Dive
```bash
./sales-enablement.sh --campaign-id 501092
```
**Output:** Full campaign story with:
- Performance metrics vs platform baseline
- ROI indicators
- Success factors analysis
- Pitch-ready narrative

### Example 4: Year-Specific Brand Analysis
```bash
./sales-enablement.sh --brand "Natura" --year 2025
```
**Output:** Brand performance for specific year

## Deployment to Billy VM

```bash
# From Anton's workspace
rsync -av /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/sales-enablement/ \
  root@89.167.64.183:/root/.openclaw/workspace/skills/sales-enablement/

# Or deploy all skills at once
rsync -av /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/ \
  root@89.167.64.183:/root/.openclaw/workspace/skills/
```

## What Billy Should Do

When user asks questions like:
- "me mostra cases de sucesso"
- "top 10 campanhas"
- "melhores campanhas da Natura"
- "estatísticas da campanha X para pitch"
- "campanhas com ROI alto"

Billy should:
1. Parse the intent (top campaigns / brand / specific campaign)
2. Run the appropriate command
3. Return the formatted narrative output

## Output Format

All outputs are **bullet-point narratives** (no tables) designed for:
- Slack messages to sales team
- Client pitch decks
- Quarterly business reviews
- Investor updates

Metrics always include **platform baseline** for comparison.

## Data Sources

- **MySQL:** db-maestro-prod
- **Tables:** campaigns, brands, proofread_medias, creator_payment_history, proofread_media_contest
- **Credentials:** ~/.my.cnf (already configured)

## Success Metrics Explained

- **Approval Rate:** % of content approved on first submission (higher = better brief quality)
- **Contest Rate:** % of content creators contested (lower = clearer guidelines)
- **Budget Utilization:** % of allocated budget actually spent
- **Campaign Velocity:** Days from publish to completion (faster = higher engagement)
- **Creator Engagement:** Total unique creators participating

## Maintenance Notes

- Queries filter campaigns with **≥10 creators** and **≥30 content pieces** (quality threshold)
- Default timeframe: **6 months** for top campaigns, **12 months** for brand summaries
- Platform baseline recalculated on each query (last 6 months avg)

## Future Enhancements

- [ ] Google Sheets export integration (via nano-banana)
- [ ] Chart generation for pitch decks
- [ ] Email digest for top campaigns (weekly)
- [ ] Integration with Linear for tracking campaign launches
