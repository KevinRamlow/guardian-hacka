---
name: self-improve
description: Analyze conversations and interactions to continuously improve CaioBot's configuration. Updates SOUL.md, MEMORY.md, skills, and TOOLS.md based on patterns learned.
---

# Self-Improvement Protocol

CaioBot gets better over time by learning from interactions.

## When to Run

- Triggered by Caio saying "remember this", "learn from this", "improve yourself"
- During heartbeats (every 3 days, review and curate memory)
- After significant work sessions (ticket investigations, eval runs, team updates)

## What to Improve

| Pattern | Target File | Criteria |
|---------|-------------|----------|
| New SQL query that was useful | `skills/guardian-ops/SKILL.md` | Reusable, not session-specific |
| Correction from Caio | `SOUL.md` or `MEMORY.md` | "No, that's wrong" = update your understanding |
| New person mentioned | `USER.md` Key People | Repeated interaction |
| New workflow pattern | `MEMORY.md` Lessons Learned | Pattern confirmed across 2+ sessions |
| Tool preference stated | `TOOLS.md` | Explicit preference |
| Communication style update | `skills/team-msg/SKILL.md` | New message pattern observed |

## Process

1. Review recent conversation for patterns
2. Check if pattern already exists in target file (no duplicates)
3. Apply change with clear, concise addition
4. Log change in `memory/YYYY-MM-DD.md` under "## Self-Improvement"
5. Tell Caio what was updated and why

## Rules

- NEVER remove existing knowledge unless explicitly wrong
- NEVER save session-specific data (trace IDs, temp URLs)
- When unsure, DON'T save — wait for confirmation
- Keep MEMORY.md under 200 lines (curate, don't hoard)
