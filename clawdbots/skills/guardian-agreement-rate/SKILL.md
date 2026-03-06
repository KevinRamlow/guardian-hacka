# Guardian Agreement Rate Monitor

Monitor Guardian AI moderation agreement rate with human reviewers across brands and campaigns.

## Purpose

Track Guardian's agreement with human moderators:
- **Agreement Rate** = correct_answers / (correct_answers + incorrect_answers)
- Monitor trends over time (daily, weekly)
- Alert when agreement rate drops below threshold
- Breakdown by brand, campaign, or overall

## Usage

### Overall Agreement Rate

**Last 7 days:**
```bash
./scripts/agreement-rate.sh overall 7
```

**Last 30 days:**
```bash
./scripts/agreement-rate.sh overall 30
```

### By Brand

**Show all brands (last 7 days):**
```bash
./scripts/agreement-rate.sh by-brand 7
```

**Specific brand:**
```bash
./scripts/agreement-rate.sh by-brand 7 <brand_id>
```

### By Campaign

**Show all campaigns (last 7 days):**
```bash
./scripts/agreement-rate.sh by-campaign 7
```

**Specific campaign:**
```bash
./scripts/agreement-rate.sh by-campaign 7 <campaign_id>
```

### Alerts

**Check for drops below threshold:**
```bash
./scripts/agreement-rate.sh alerts <threshold>
# Example: Alert if any brand/campaign below 80%
./scripts/agreement-rate.sh alerts 80
```

### Daily Trend

**Show daily agreement rate trend:**
```bash
./scripts/agreement-rate.sh trend <days>
# Example: Last 14 days
./scripts/agreement-rate.sh trend 14
```

## Alert Conditions

**High Priority:**
- Overall agreement rate < 75%
- Any brand/campaign < 70%
- Rate dropped >10pp in 24h

**Medium Priority:**
- Overall agreement rate < 80%
- Any brand/campaign < 75%
- Rate dropped >5pp in 24h

## Data Source

- **MySQL Table**: `proofread_medias`
- **Key Fields**:
  - `correct_answers` — Guardian matched human decision
  - `incorrect_answers` — Guardian disagreed with human
  - `brand_id`, `campaign_id` — Grouping dimensions
- **Credentials**: Uses `~/.my.cnf` connection config

## Output Format

### Overall
```
Guardian Agreement Rate (Last 7 Days)
=====================================
Total Evaluations: 545
Correct Answers:   3,954
Incorrect Answers: 713
Agreement Rate:    84.7%
```

### By Brand
```
Agreement Rate by Brand (Last 7 Days)
======================================
Brand ID | Brand Name         | Evaluations | Rate   | Status
---------|-------------------|-------------|--------|--------
12       | Nike              | 120         | 87.3%  | ✅ OK
45       | Adidas            | 98          | 72.1%  | ⚠️  LOW
78       | Puma              | 87          | 91.2%  | ✅ OK
```

### Alerts
```
⚠️  Agreement Rate Alerts
==========================

HIGH PRIORITY:
- Brand #45 (Adidas): 72.1% (threshold: 75%)
- Campaign #234: 68.5% (threshold: 70%)

MEDIUM PRIORITY:
- Brand #67: 77.8% (threshold: 80%)
- Overall rate dropped 6.2pp in last 24h
```

### Trend
```
Daily Agreement Rate Trend (Last 14 Days)
=========================================
Date       | Evals | Correct | Incorrect | Rate   | Change
-----------|-------|---------|-----------|--------|--------
2026-03-05 | 82    | 595     | 107       | 84.8%  | +1.2pp
2026-03-04 | 79    | 573     | 112       | 83.6%  | -0.5pp
2026-03-03 | 75    | 541     | 98        | 84.7%  | +2.1pp
```

## Billy Integration

Billy can use this skill to:
- Answer "what's Guardian's agreement rate today?"
- Alert when agreement drops below threshold
- Show which brands/campaigns need attention
- Generate weekly agreement reports
- Compare trends across time periods

## Notes

- Agreement rate = correct / (correct + incorrect)
- Only includes records with non-null correct_answers and incorrect_answers
- Deleted records (deleted_at IS NOT NULL) are excluded
- Minimum 10 evaluations required for brand/campaign to show in reports
- Alerts check both current rate and 24h delta
