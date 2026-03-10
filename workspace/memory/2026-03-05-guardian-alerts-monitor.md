# Guardian Alerts Monitor - Configuration Issue

**Time:** 2026-03-05 21:19 UTC
**Issue:** Cannot read #guardian-alerts channel - missing Slack API scope

## Problem
The Guardian alerts monitoring cron job failed because the Slack token lacks the `channels:history` scope needed to read channel messages.

## Action Required
Caio needs to:
1. Update Slack app/token permissions to include `channels:history` 
2. Reinstall the app or regenerate token if needed
3. Update the token in OpenClaw config

## Temporary Workaround
Until fixed, Guardian alerts monitoring is non-functional.
