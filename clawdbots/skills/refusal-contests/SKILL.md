# Refusal Contest Analysis

Analyze creator contest patterns for Guardian AI moderation decisions — identify which brands, campaigns, and guideline types receive the most contests.

## Purpose

Track and analyze creator contests against Guardian moderation decisions:
- **Contest Rate** = total_contests / total_moderation_decisions
- **Approval Rate** = approved_contests / total_contests
- Monitor trends over time (daily, weekly, monthly)
- Identify brands with highest contest rates
- Identify campaigns with highest contest rates
- Breakdown by contest status (approved, reproved, pending)

## Usage

### Overall Contest Stats

**Last 7 days:**
```bash
./scripts/contest-analysis.sh overall 7
```

**Last 30 days:**
```bash
./scripts/contest-analysis.sh overall 30
```

### By Brand

**Show all brands (last 30 days):**
```bash
./scripts/contest-analysis.sh by-brand 30
```

**Specific brand:**
```bash
./scripts/contest-analysis.sh by-brand 30 <brand_id>
```

### By Campaign

**Show all campaigns (last 30 days):**
```bash
./scripts/contest-analysis.sh by-campaign 30
```

**Specific campaign:**
```bash
./scripts/contest-analysis.sh by-campaign 30 <campaign_id>
```

### Contest Status

**Show contest status breakdown:**
```bash
./scripts/contest-analysis.sh status <days>
# Example: Last 30 days
./scripts/contest-analysis.sh status 30
```

### Pending Contests

**Show pending contests that need review:**
```bash
./scripts/contest-analysis.sh pending
```

### Top Contested Brands

**Show brands with most contests:**
```bash
./scripts/contest-analysis.sh top-brands <days> [limit]
# Example: Top 10 brands last 30 days
./scripts/contest-analysis.sh top-brands 30 10
```

### Daily Trend

**Show daily contest trend:**
```bash
./scripts/contest-analysis.sh trend <days>
# Example: Last 14 days
./scripts/contest-analysis.sh trend 14
```

## Key Metrics

**Contest Volume:**
- Total contests submitted
- Contests per day/week
- Contest rate (contests / total moderation decisions)

**Contest Outcomes:**
- Approved: Guardian decision was wrong, creator was right
- Reproved: Guardian decision was correct, creator contest rejected
- Pending: Awaiting analyst review
- Approval rate: % of contests approved

**High Contest Brands:**
- Brands with >30% contest rate need attention
- Low approval rate (<50%) = good Guardian accuracy
- High approval rate (>70%) = Guardian needs improvement

## Data Source

- **MySQL Tables**: 
  - `proofread_media_contest` — Contest records
  - `proofread_medias` — Moderation decisions
  - `brands` — Brand information
  - `campaigns` — Campaign information
- **Key Fields**:
  - `status` — approved, reproved, pending
  - `reason` — Creator's contest explanation
  - `decision_reason` — Analyst's decision reasoning
- **Credentials**: Uses `~/.my.cnf` connection config

## Output Format

### Overall
```
Contest Analysis (Last 30 Days)
================================
Total Contests:       706
├─ Approved:          428 (60.6%)
├─ Reproved:          14 (2.0%)
└─ Pending:           264 (37.4%)

Contest Approval Rate: 96.8% (approved / (approved + reproved))
```

### By Brand
```
Contest Rate by Brand (Last 30 Days)
====================================
Brand ID | Brand Name      | Contests | Approved | Reproved | Approval Rate | Status
---------|-----------------|----------|----------|----------|---------------|--------
882      | Bet MGM         | 98       | 53       | 0        | 100.0%        | ⚠️  HIGH
821      | L'Oréal Vichy   | 41       | 25       | 1        | 96.2%         | ⚠️  HIGH
862      | C&A             | 41       | 25       | 0        | 100.0%        | ⚠️  HIGH
881      | Smart Fit       | 36       | 21       | 1        | 95.5%         | ⚠️  HIGH
```

### Pending Contests
```
Pending Contests Awaiting Review
=================================
Count: 264 contests

Recent Pending (Last 10):
ID    | Brand              | Created At           | Days Pending
------|-------------------|---------------------|-------------
1234  | Bet MGM            | 2026-03-01 14:23:11 | 5 days
1235  | TIM                | 2026-03-02 09:15:33 | 4 days
```

### Trend
```
Daily Contest Trend (Last 14 Days)
==================================
Date       | Contests | Approved | Reproved | Pending | Approval %
-----------|----------|----------|----------|---------|------------
2026-03-05 | 12       | 7        | 0        | 5       | 100.0%
2026-03-04 | 15       | 9        | 1        | 5       | 90.0%
2026-03-03 | 8        | 5        | 0        | 3       | 100.0%
```

## Billy Integration

Billy can use this skill to:
- Answer "which brands have the most contests?"
- Show "contest rate by brand for last month"
- Alert when pending contests > 50
- Generate weekly contest reports
- Identify brands where Guardian needs improvement (high approval rate)
- Show trends: "are contests increasing or decreasing?"

## Interpretation Guide

**High approval rate (>70%):** Guardian might be too strict for this brand/campaign
**Low approval rate (<40%):** Guardian accuracy is good, creators challenging incorrectly
**Many pending (>50):** Analyst backlog, need faster review process
**Contest rate >30%:** Brand/campaign guidelines may be unclear or too restrictive

## Notes

- Approval rate = approved / (approved + reproved), excludes pending
- Only includes non-deleted proofread_medias
- Minimum 5 contests required for brand/campaign to show in reports
- Recent = last 30 days by default
- Pending contests sorted by oldest first (FIFO review queue)
