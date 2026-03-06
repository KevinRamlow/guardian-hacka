# Screen Time and View Retention Analytics

Billy skill for analyzing sequential screen usage across campaigns and ads.

## Quick Start

```bash
# Get overall summary
./scripts/screen-time.sh summary

# See distribution
./scripts/screen-time.sh distribution

# Analyze specific campaign
./scripts/screen-time.sh campaign 123

# Top multi-screen campaigns
./scripts/screen-time.sh top-campaigns 10

# Creators with multi-screen content
./scripts/screen-time.sh creators 123
```

## What It Does

Tracks how campaigns use multi-screen content (Instagram/TikTok stories):
- Overall platform metrics
- Campaign-specific analysis
- Creator behavior patterns
- Screen count distribution

## Requirements

- MySQL access (uses `~/.my.cnf` credentials)
- Bash shell
- Read access to: `ads`, `campaigns`, `moments`, `actions`, `media_content`, `user` tables

## Data Notes

- Based on `ads.number_of_sequential_screens` column
- NULL values treated as 1 (single screen)
- Only includes non-deleted campaigns and ads
- Screen count set at ad creation (briefing requirement)

## For Billy

Billy can answer questions like:
- "What's our multi-screen usage rate?"
- "Show me top campaigns by screen time"
- "Which creators make multi-screen content?"
- "What's the average screen count per ad?"
- "How does campaign X compare on screen usage?"

See `SKILL.md` for full documentation.
