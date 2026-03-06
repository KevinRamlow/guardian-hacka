# Campaign Lifecycle Tracker

Track campaign status transitions and identify campaigns that need attention.

## Purpose

Monitor campaign lifecycle across states:
- **draft** — Initial creation, not published yet
- **published** — Active campaigns with creators
- **paused** — Temporarily stopped
- **finished** — Completed campaigns

Alert on campaigns that may be stuck:
- Published campaigns with no media submissions >7 days
- Campaigns stuck in draft >30 days
- Recently updated campaigns that need review

## Usage

### Query Current Campaign Status

**Summary by state:**
```bash
./scripts/campaign-status.sh summary
```

**Campaigns stuck in a state:**
```bash
./scripts/campaign-status.sh stuck <state> <days>
# Examples:
./scripts/campaign-status.sh stuck draft 30
./scripts/campaign-status.sh stuck published 7
```

**Timeline of recent state changes:**
```bash
./scripts/campaign-status.sh timeline <campaign_id>
```

**Campaigns needing attention:**
```bash
./scripts/campaign-status.sh alerts
```

### Examples

```bash
# Get overview of all campaigns by state
./scripts/campaign-status.sh summary

# Find published campaigns with no activity >7 days
./scripts/campaign-status.sh stuck published 7

# Find draft campaigns older than 30 days
./scripts/campaign-status.sh stuck draft 30

# Check all alert conditions
./scripts/campaign-status.sh alerts

# View specific campaign timeline
./scripts/campaign-status.sh timeline 123
```

## What Gets Tracked

### Campaign States
- **draft**: Campaigns being prepared
- **published**: Active campaigns
- **paused**: Temporarily stopped
- **finished**: Completed campaigns

### Alert Conditions

**High Priority:**
- Published campaigns with no media submissions in 7+ days
- Draft campaigns unchanged for 30+ days

**Medium Priority:**
- Published campaigns with low submission rate
- Campaigns updated recently (potential review needed)

## Data Source

- **MySQL Table**: `campaigns` (joined with `campaign_states`)
- **Related Tables**: `media_content`, `actions` (for submission tracking)
- **Credentials**: Uses `~/.my.cnf` connection config

## Output Format

### Summary
```
Campaign Status Summary
=======================
draft:     130 campaigns
published: 87 campaigns
paused:    0 campaigns
finished:  437 campaigns
```

### Stuck Campaigns
```
Campaigns stuck in 'published' >7 days
========================================
ID    | Title                    | Days | Last Update
------|--------------------------|------|------------
1234  | Spring Campaign 2026     | 14   | 2026-02-20
5678  | Winter Launch            | 21   | 2026-02-13
```

### Alerts
```
⚠️  ALERTS - Campaigns Needing Attention
========================================

HIGH PRIORITY:
- Campaign #1234: Published 14 days ago, 0 submissions
- Campaign #2345: Draft for 45 days, no updates

MEDIUM PRIORITY:
- Campaign #3456: Updated 2 days ago (check if review needed)
```

## Billy Integration

Billy can use this skill to:
- Answer "how many campaigns are in draft?"
- Alert team on stuck campaigns
- Show campaign lifecycle for specific campaigns
- Generate reports on campaign health

## Notes

- Campaigns with `deleted_at IS NOT NULL` are excluded
- "Stuck" is based on `updated_at` timestamp
- Submission tracking requires join with `actions` and `media_content` tables
- Timeline reconstruction uses `created_at` and `updated_at` (no full audit log)
