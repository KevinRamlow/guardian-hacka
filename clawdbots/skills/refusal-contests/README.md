# Refusal Contest Analysis

Analyze creator contest patterns for Guardian AI moderation decisions.

## What It Does

This skill helps Billy answer questions about:
- Which brands have the most contests?
- What's the contest approval rate?
- How many pending contests need review?
- Contest trends over time

## Quick Examples

```bash
# Overall stats for last 30 days
./scripts/contest-analysis.sh overall 30

# Top 10 brands by contest volume
./scripts/contest-analysis.sh top-brands 30 10

# Pending contests awaiting review
./scripts/contest-analysis.sh pending

# Daily contest trend
./scripts/contest-analysis.sh trend 14
```

## Usage with Billy

Billy can trigger this skill when users ask:
- "Show me contest data for Bet MGM"
- "Which brands have the most contests?"
- "What's the contest approval rate?"
- "How many pending contests do we have?"
- "Contest trends last 2 weeks"

See [SKILL.md](./SKILL.md) for full documentation.
