# Daily Digest Skill

Proactive daily platform summary for Billy — generates a concise Slack-ready digest of yesterday's activity, alerts, and upcoming deadlines.

## Quick Start

```bash
# Generate yesterday's digest
python3 generate.py

# JSON output
python3 generate.py --format json

# Specific date
python3 generate.py --date 2026-03-05
```

## What It Includes

- **Volume Overview**: Total moderated, approval/rejection rates, contests
- **New Campaigns**: Campaigns published in last 24h
- **Completed Campaigns**: Campaigns that finished yesterday
- **Top Campaigns**: Most active campaigns by volume
- **Alerts**: High rejection rates, stalled campaigns
- **Upcoming Deadlines**: Campaigns/moments ending in 2-3 days

## Automation

For daily proactive delivery, add to cron:

```bash
# Daily at 9:00 AM São Paulo time (12:00 UTC)
0 12 * * * cd /root/.openclaw/workspace/skills/daily-digest && python3 generate.py >> /var/log/billy/daily-digest.log 2>&1
```

## Integration with Billy

Billy can invoke this skill when users ask:
- "resumo de hoje" / "como está o dia?"
- "daily digest" / "daily report"
- "o que rolou hoje?"

## Output Format

Slack-friendly markdown with:
- Emoji section headers
- Thousands separators (pt-BR: 1.234)
- Delta indicators (↑/↓) for week-over-week comparison
- Bold campaign names
- Concise alerts with clear context

## Database

Queries MySQL `db-maestro-prod` (READ ONLY):
- `proofread_medias` — moderation data
- `campaigns`, `brands` — campaign context
- `moments` — deadlines
- `proofread_media_contest` — contest tracking

Credentials from `~/.my.cnf`

## Files

- `SKILL.md` — Full documentation
- `generate.py` — Main script
- `README.md` — This file

## Notes

- Queries run in ~2-3 seconds total
- Default: yesterday's data (configurable via --date)
- Alerts: >50% rejection rate OR >7 days stalled
- Deadlines: 2-3 days window

Built 2026-03-06 for CAI-96
