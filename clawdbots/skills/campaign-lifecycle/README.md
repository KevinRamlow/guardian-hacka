# Campaign Lifecycle Tracker - Deployment Summary

**Created:** 2026-03-06 02:34 UTC
**Linear Task:** CAI-95
**Status:** ✅ Deployed and tested

## Overview

Billy skill for tracking campaign lifecycle states and identifying campaigns that need attention.

## Deployment

- **Local:** /root/.openclaw/workspace/clawdbots/skills/campaign-lifecycle/
- **Billy VM:** root@89.167.64.183:/root/.openclaw/workspace/skills/campaign-lifecycle/
- **Deployed via:** rsync

## Commands

```bash
# Summary by state
./scripts/campaign-status.sh summary

# Find stuck campaigns
./scripts/campaign-status.sh stuck <state> <days>

# Campaign timeline
./scripts/campaign-status.sh timeline <campaign_id>

# All alerts
./scripts/campaign-status.sh alerts
```

## Database Schema

**States:**
- draft (130 campaigns, 19.9%)
- published (87 campaigns, 13.3%)
- paused (0 campaigns)
- finished (437 campaigns, 66.8%)

**Key Tables:**
- campaigns (654 active)
- campaign_states (4 states)
- moments, ads, actions, media_content (for submission tracking)

## Alert Thresholds

**High Priority:**
- Published campaigns with 0 submissions in 7+ days
- Draft campaigns unchanged for 30+ days

**Medium Priority:**
- Campaigns updated in last 1-3 days (potential review)

## Testing

All commands tested locally and on Billy VM:
- ✅ summary → 654 total campaigns
- ✅ stuck → Found 20+ high-priority alerts
- ✅ timeline → Shows campaign lifecycle events
- ✅ alerts → Comprehensive alert report

## Billy Integration

Billy can now answer:
- "How many campaigns are in each state?"
- "Which campaigns are stuck?"
- "Show me campaigns that need attention"
- "What's the timeline for campaign X?"

## Future Enhancements

Possible additions if needed:
- Historical state tracking (requires audit table)
- Submission rate trends over time
- Campaign performance metrics
- Automated alerting to Slack channels
