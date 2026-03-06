# Weekly Campaign Reports

Generate automated weekly summaries of campaign activity and performance.

## Purpose

Aggregate campaign metrics over the past 7 days for team updates:
- **New Campaigns**: Campaigns created this week
- **Completions**: Campaigns that reached 'finished' state
- **Top Performers**: Campaigns with most submissions/approvals
- **Issues**: Stuck campaigns, low activity, potential problems

Perfect for Monday morning team sync or Friday wrap-ups.

## Usage

### Generate Weekly Report

**Full weekly summary (default 7 days):**
```bash
./scripts/weekly-report.sh
```

**Custom time range:**
```bash
./scripts/weekly-report.sh <days>
# Example: last 14 days
./scripts/weekly-report.sh 14
```

**Slack-friendly format (no colors):**
```bash
./scripts/weekly-report.sh --slack
./scripts/weekly-report.sh 14 --slack
```

### Specific Sections

**New campaigns only:**
```bash
./scripts/weekly-report.sh --section new
```

**Completions only:**
```bash
./scripts/weekly-report.sh --section completions
```

**Top performers only:**
```bash
./scripts/weekly-report.sh --section top
```

**Issues only:**
```bash
./scripts/weekly-report.sh --section issues
```

### Examples

```bash
# Standard weekly report
./scripts/weekly-report.sh

# Last 30 days for monthly review
./scripts/weekly-report.sh 30

# Slack-friendly format for posting
./scripts/weekly-report.sh --slack

# Just show issues
./scripts/weekly-report.sh --section issues
```

## What Gets Reported

### New Campaigns (Past 7 Days)
- Campaign ID, title, state
- Creation date
- Total count of new campaigns

### Completions (Past 7 Days)
- Campaigns that reached 'finished' state
- Total submissions and approval rate
- Duration from creation to completion

### Top Performers (Past 7 Days)
- Campaigns with most activity
- Ranked by total submissions
- Shows approved/pending/refused breakdown
- Approval rate percentage

### Issues & Alerts
- Published campaigns with 0 submissions in 7+ days
- Draft campaigns stuck >30 days
- Campaigns with low approval rates (<50%)
- Recently paused campaigns

## Data Source

- **MySQL Tables**: `campaigns`, `campaign_states`, `actions`, `media_content`
- **Metrics**: Aggregated from past N days (default 7)
- **Credentials**: Uses `~/.my.cnf` connection config

## Output Format

### Console (with colors)
```
╔════════════════════════════════════════╗
║   WEEKLY CAMPAIGN REPORT (7 days)     ║
║   Period: 2026-02-27 to 2026-03-06    ║
╚════════════════════════════════════════╝

📊 SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• New campaigns:        12
• Completed campaigns:   5
• Total submissions:   234
• Avg approval rate:   78.5%

🆕 NEW CAMPAIGNS (12)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#1234 | Spring Launch 2026        | published | 2026-03-01
#1235 | Winter Campaign           | draft     | 2026-03-02
...

✅ COMPLETIONS (5)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#1100 | Holiday Campaign         | 45 submissions | 82% approved | 23 days
...

🏆 TOP PERFORMERS (by submissions)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. #1150 | Mega Campaign         | 67 submissions | 85% approved
2. #1140 | Product Launch        | 54 submissions | 76% approved
...

⚠️  ISSUES & ALERTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• 3 published campaigns with 0 submissions (>7 days)
• 8 draft campaigns stuck >30 days
• 2 campaigns with approval rate <50%
```

### Slack Format (no colors, simpler)
```
*WEEKLY CAMPAIGN REPORT (7 days)*
_Period: 2026-02-27 to 2026-03-06_

*📊 SUMMARY*
• New campaigns: 12
• Completed campaigns: 5
• Total submissions: 234
• Avg approval rate: 78.5%

*🆕 NEW CAMPAIGNS (12)*
• #1234 Spring Launch 2026 (published) - 2026-03-01
• #1235 Winter Campaign (draft) - 2026-03-02

*✅ COMPLETIONS (5)*
• #1100 Holiday Campaign - 45 submissions, 82% approved, 23 days

*🏆 TOP PERFORMERS*
1. #1150 Mega Campaign - 67 submissions (85% approved)
2. #1140 Product Launch - 54 submissions (76% approved)

*⚠️ ISSUES*
• 3 published campaigns with 0 submissions (>7 days)
• 8 draft campaigns stuck >30 days
• 2 campaigns with approval rate <50%
```

## Billy Integration

Billy can use this skill to:
- Generate Monday morning team reports
- Answer "what happened this week with campaigns?"
- Alert team on weekly performance trends
- Create monthly summaries (30 days)
- Post directly to #tech-gua-ma-internal or relevant channels

## Automation

Can be scheduled via cron for automatic weekly reports:
```bash
# Every Monday at 9 AM
0 9 * * 1 /root/.openclaw/workspace/skills/weekly-reports/scripts/weekly-report.sh --slack
```

## Notes

- Default period is 7 days (past week)
- Campaigns with `deleted_at IS NOT NULL` are excluded
- "Completions" tracked by campaigns that reached 'finished' state in period
- Approval rate calculated as: approved / (approved + refused)
- Top performers ranked by total submissions regardless of approval rate
