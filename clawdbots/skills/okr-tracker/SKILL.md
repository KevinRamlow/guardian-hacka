# OKR Progress Tracker

Track progress on team OKRs by querying relevant metrics and calculating completion percentages.

## Purpose

Monitor key results for different teams:
- **Campaign OKRs** — Active campaigns, completion rate, time-to-publish
- **Moderation OKRs** — Review volume, approval rate, response time, accuracy
- **Creator OKRs** — Active creators, submission rate, retention
- **Brand OKRs** — Active brands, campaigns per brand, engagement

Generate progress reports showing current value, target, and completion percentage.

## Usage

### Query OKR Progress

**Summary of all OKRs:**
```bash
./scripts/okr-progress.sh summary
```

**Campaign team OKRs:**
```bash
./scripts/okr-progress.sh campaigns
```

**Moderation team OKRs:**
```bash
./scripts/okr-progress.sh moderation
```

**Creator team OKRs:**
```bash
./scripts/okr-progress.sh creators
```

**Brand team OKRs:**
```bash
./scripts/okr-progress.sh brands
```

**Custom date range:**
```bash
./scripts/okr-progress.sh summary --days 30
./scripts/okr-progress.sh campaigns --days 90
```

### Examples

```bash
# Get overview of all OKRs
./scripts/okr-progress.sh summary

# Check campaign team progress
./scripts/okr-progress.sh campaigns

# Get moderation metrics for Q1 (90 days)
./scripts/okr-progress.sh moderation --days 90

# View creator engagement metrics
./scripts/okr-progress.sh creators
```

## Tracked Metrics

### Campaign OKRs
- **Active campaigns** — Published campaigns in last N days
- **Campaign completion rate** — % of campaigns reaching finished state
- **Time to publish** — Average days from creation to publication
- **Campaigns per brand** — Average active campaigns per brand

### Moderation OKRs
- **Review volume** — Total proofread_medias processed
- **Approval rate** — % approved vs refused
- **Response time** — Average time from submission to first review
- **Proofread accuracy** — Quality metrics (if available)

### Creator OKRs
- **Active creators** — Creators with submissions in period
- **Submission rate** — Average submissions per active creator
- **Creator retention** — % of creators with repeat submissions
- **New creator onboarding** — New creators joining platform

### Brand OKRs
- **Active brands** — Brands with active campaigns
- **Campaigns per brand** — Average campaigns per brand
- **Brand satisfaction** — Based on repeat campaigns
- **New brand acquisition** — New brands onboarded

## Data Sources

- **MySQL Tables**: campaigns, proofread_medias, media_content, actions, brands, creator_groups
- **Credentials**: Uses `~/.my.cnf` connection config
- **Date Range**: Defaults to last 30 days, configurable with --days flag

## Output Format

### Summary
```
OKR Progress Report - Last 30 Days
===================================

CAMPAIGNS
---------
Active campaigns: 87 / 100 target → 87% ✓
Completion rate: 68% / 70% target → 97% 
Time to publish: 4.2 days / 5 days target → 120% ✓✓

MODERATION
----------
Review volume: 3,005 / 3,000 target → 100% ✓
Approval rate: 76% / 75% target → 101% ✓
Response time: 1.8 hours / 2 hours target → 111% ✓

CREATORS
--------
Active creators: 245 / 300 target → 82% 
Submission rate: 12.3 / 10 target → 123% ✓✓
Creator retention: 68% / 65% target → 105% ✓

BRANDS
------
Active brands: 42 / 50 target → 84% 
Campaigns per brand: 2.1 / 2.0 target → 105% ✓
New brands: 8 / 10 target → 80% 
```

### Individual Team View
```
Campaign Team OKRs - Last 30 Days
=================================

Objective: Increase campaign velocity and brand engagement

Key Results:
1. Active campaigns: 87 / 100 target
   Progress: [████████░░] 87%
   Status: On track ✓

2. Completion rate: 68% / 70% target
   Progress: [█████████░] 97%
   Status: Nearly there

3. Time to publish: 4.2 days / 5 days target
   Progress: [██████████] 120% ✓✓
   Status: Exceeded! 

Overall: 101% average progress → ON TRACK ✓
```

## Billy Integration

Billy can use this skill to:
- Answer "What's our progress on Q1 OKRs?"
- Show team-specific OKR status
- Generate weekly/monthly OKR reports
- Alert on OKRs falling behind
- Celebrate milestones when targets are hit

## Configuration

Default targets are hardcoded in the script. To customize:
1. Edit `scripts/okr-progress.sh`
2. Update TARGET_* variables at the top
3. Or pass custom targets via environment variables

Example:
```bash
TARGET_ACTIVE_CAMPAIGNS=120 ./scripts/okr-progress.sh campaigns
```

## Notes

- Progress >100% means target exceeded
- Status indicators: ✓ (met), ✓✓ (exceeded), ⚠ (behind)
- Default period: last 30 days (1 month)
- Use --days flag for custom periods (7, 30, 90 days typical)
- OKRs should be reviewed and updated quarterly
