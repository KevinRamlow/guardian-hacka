# Screen Time and View Retention Analytics

Track sequential screen usage and multi-screen content metrics across campaigns.

## Purpose

Analyze how campaigns use multi-screen content (Instagram/TikTok stories with multiple slides):
- **Single-screen ads** — Simple, one-screen content
- **Multi-screen ads** — Stories with 2+ sequential screens
- **Screen distribution** — Understand typical content length
- **Campaign comparisons** — Which campaigns use more engaging multi-screen content

Key insights:
- Multi-screen content typically has higher engagement
- Understand creator behavior (who creates longer content)
- Identify campaigns that might benefit from multi-screen guidance

## Usage

### Overall Summary

Get platform-wide screen time metrics:
```bash
./scripts/screen-time.sh summary
```

Shows:
- Total campaigns and ads
- Multi-screen usage percentage
- Average screens per ad
- Breakdown by campaign state

### Screen Distribution

See how screen counts are distributed:
```bash
./scripts/screen-time.sh distribution
```

Shows:
- Histogram of screen counts
- Usage ranges (single, short, medium, long, extended)
- Percentage breakdown

### Campaign Analysis

Analyze a specific campaign's screen usage:
```bash
./scripts/screen-time.sh campaign <campaign_id>
```

Shows:
- Campaign-level metrics
- Individual ads with screen counts
- Submissions per ad
- Screen distribution within campaign

### Top Multi-Screen Campaigns

Find campaigns with most multi-screen content:
```bash
./scripts/screen-time.sh top-campaigns [limit]
# Default limit: 10
```

Shows:
- Campaigns ranked by multi-screen ad count
- Multi-screen percentage
- Average screens per ad

### Creator Analysis

See which creators produce multi-screen content:
```bash
./scripts/screen-time.sh creators <campaign_id>
```

Shows:
- Creators with multi-screen submissions
- Action counts
- Media submissions
- Average screens per creator

## Data Source

- **MySQL Table**: `ads` (column: `number_of_sequential_screens`)
- **Related Tables**: `campaigns`, `moments`, `actions`, `media_content`, `user`
- **Credentials**: Uses `~/.my.cnf` connection config

## Interpretation

### Screen Count Meanings

- **1 screen** — Single image/video (simple content)
- **2-3 screens** — Short story sequence (quick message)
- **4-6 screens** — Medium story (typical engaging content)
- **7-10 screens** — Long story (detailed narrative)
- **10+ screens** — Extended content (rare, highly engaged)

### Typical Patterns

- **Single-screen dominant**: Traditional campaigns (single post requirement)
- **Mixed usage**: Flexible guidelines allowing creativity
- **Multi-screen heavy**: Story-focused campaigns (higher engagement potential)

### What to Look For

**Good indicators:**
- 30-50% multi-screen usage = healthy engagement
- Average 3-5 screens = optimal story length
- Creators consistently using multi-screen = engaged, quality creators

**Red flags:**
- 100% single-screen in story campaigns = creators not following brief
- Very high averages (>8 screens) = potential overly complex content
- No multi-screen content = missed engagement opportunity

## Billy Integration

Billy can use this skill to:
- Answer "what's our multi-screen usage rate?"
- Show top campaigns by screen time
- Analyze creator engagement patterns
- Report on campaign screen metrics
- Compare campaigns (single vs multi-screen performance)

## Output Format

### Summary
```
Screen Time Analytics Summary
==============================

Overall Metrics:
total_campaigns | total_ads | multi_screen_ads | multi_screen_percentage | avg_screens_per_ad | max_screens
654            | 2341      | 892             | 38.10                  | 2.73              | 15

By Campaign State:
state      | total_ads | multi_screen_ads | avg_screens
draft      | 430       | 124              | 2.12
published  | 687       | 298              | 3.45
finished   | 1224      | 470              | 2.58
```

### Distribution
```
Screen Count Distribution
=========================

screens | ad_count | distribution
1       | 1449     | ████████████████████████████████████████████████
2       | 412      | ██████████████
3       | 231      | ████████
4       | 156      | █████
5       | 93       | ███

Screen Usage Ranges:
range               | count | percentage
1 screen (single)   | 1449  | 61.90
2-3 screens (short) | 643   | 27.46
4-6 screens (medium)| 205   | 8.76
7-10 screens (long) | 44    | 1.88
```

## Future Enhancements

When BigQuery access is available, extend to include:
- **Actual view retention** — How many viewers complete all screens
- **Drop-off rates** — Where viewers stop watching
- **Engagement metrics** — Likes, shares, completion rates by screen count
- **Time spent** — Average viewing duration per screen
- **Performance correlation** — Screen count vs campaign success

## Notes

- `NULL` in `number_of_sequential_screens` is treated as 1 (single screen)
- Only counts non-deleted campaigns and ads
- Multi-screen content is typically Instagram/TikTok Stories format
- Screen count is set at ad creation (briefing requirement)
- Does not track actual viewer behavior (requires social platform data)
