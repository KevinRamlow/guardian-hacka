# Weekly Campaign Reports

Automated weekly summaries of campaign activity and performance for Billy.

## Quick Start

```bash
# Standard weekly report (last 7 days)
./scripts/weekly-report.sh

# Slack-friendly format
./scripts/weekly-report.sh --slack

# Last 30 days
./scripts/weekly-report.sh 30 --slack

# Just show issues
./scripts/weekly-report.sh --section issues
```

## What It Reports

- **New Campaigns**: Created in the past N days
- **Completions**: Campaigns that reached 'finished' state
- **Top Performers**: Ranked by submission volume
- **Issues**: Stuck campaigns, low approval rates, alerts

## Setup

Requires MySQL access with credentials in `~/.my.cnf`. Billy VM is already configured.

## Output Formats

- **Console**: Colored output with formatting
- **Slack**: Plain text with emoji, ready to paste

## Billy Integration

Billy can:
- Generate Monday morning reports
- Answer "what happened this week?"
- Alert team on campaign issues
- Create monthly summaries

## Automation

Add to cron for automatic reports:

```bash
# Every Monday at 9 AM
0 9 * * 1 /root/.openclaw/workspace/skills/weekly-reports/scripts/weekly-report.sh --slack
```

## Files

- `SKILL.md` - Full documentation
- `scripts/weekly-report.sh` - Main report generator
- `README.md` - This file

## Dependencies

- MySQL client
- Bash 4+
- Access to `campaigns`, `campaign_states`, `actions`, `media_content` tables

## Notes

- Default period: 7 days
- Excludes deleted campaigns (`deleted_at IS NOT NULL`)
- Approval rate: approved / (approved + refused)
- Top performers ranked by total submissions

---

Created: 2026-03-06
Task: CAI-84
Deployed to: Billy VM (89.167.64.183)
