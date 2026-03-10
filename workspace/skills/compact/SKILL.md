---
name: compact
description: Trigger session compaction to reduce context size and improve response speed
---

# Compact Skill

Triggers manual compaction of the current session to compress the conversation history.

## When to use

- When the session context is bloated (>100k tokens)
- Response times are slow
- Before long-running tasks
- Periodically via cron (recommended: every 2-4 hours during work hours)

## How it works

Uses OpenClaw's `/compact` command to:
1. Summarize the conversation history
2. Reduce token count while preserving key context
3. Speed up future responses

## Usage

Just mention "compact" or "compress the session" and I'll trigger it.

## Periodic compaction via cron

This skill is configured to run automatically every 2 hours during work hours (8 AM - 11 PM São Paulo time).
