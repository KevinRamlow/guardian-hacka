# Guardian Agreement Rate Monitor

Billy skill to monitor Guardian AI moderation agreement rate with human reviewers.

## Quick Start

```bash
# Overall agreement rate (last 7 days)
./scripts/agreement-rate.sh overall 7

# By brand (last 7 days)
./scripts/agreement-rate.sh by-brand 7

# Check alerts (brands/campaigns below 80%)
./scripts/agreement-rate.sh alerts 80

# Daily trend (last 14 days)
./scripts/agreement-rate.sh trend 14
```

## What It Does

Monitors Guardian's agreement with human moderators by analyzing the `proofread_medias` table:
- **Agreement Rate** = correct_answers / (correct_answers + incorrect_answers)
- Tracks trends over time
- Alerts when rates drop below thresholds
- Breakdown by brand, campaign, or overall

## Deployment

**Local development:**
```bash
cd /root/.openclaw/workspace/clawdbots/skills/guardian-agreement-rate
./scripts/agreement-rate.sh overall 7
```

**Deploy to Billy VM:**
```bash
rsync -av /root/.openclaw/workspace/clawdbots/skills/ root@89.167.64.183:/root/.openclaw/workspace/skills/
```

**Test on Billy:**
```bash
ssh root@89.167.64.183 "cd /root/.openclaw/workspace/skills/guardian-agreement-rate && ./scripts/agreement-rate.sh overall 7"
```

## Data Source

- **Table**: `proofread_medias`
- **Database**: MySQL (db-maestro-prod)
- **Connection**: Uses `~/.my.cnf`

## Alert Thresholds

- **High Priority**: < 75% (any brand/campaign), < 75% overall
- **Medium Priority**: < 80% (any brand/campaign), < 80% overall
- **Good**: >= 80%

## Commands Reference

See [SKILL.md](SKILL.md) for detailed usage examples and output formats.
