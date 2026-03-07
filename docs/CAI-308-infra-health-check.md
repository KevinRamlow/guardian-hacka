# CAI-308: Infrastructure Health Check Report

**Date:** 2026-03-07
**Status:** Current health = FAIR (functional but gaps exist)

---

## Current Infrastructure Overview

### Cron Jobs (4 active)
| Job | Frequency | Script | Status |
|-----|-----------|--------|--------|
| Watchdog | 60s | agent-watchdog-v2.sh | Running, logs healthy |
| Auto-queue | 5min | auto-queue-v2.sh | Running, spawning correctly |
| Linear sync | 15min | linear-sync-v2.sh | Running, detecting orphans |
| Gateway respawn | 60s | gateway-respawn.sh | Running, gateway stable |

### NOT in Crontab (should be)
| Job | Script | Issue |
|-----|--------|-------|
| Health check | health-check.sh | Script exists but cron never installed |
| Auto-push | auto-push.sh | Script exists but cron never installed |

**Root cause:** `install-cron-v2.sh` was never re-run after gateway-respawn was added manually. Current crontab is out of sync with install script.

---

## Watchdog Edge Cases Found

### 1. ACP Bridge Orphan Killer is Overly Aggressive (lines 119-130)
Kills ALL `claude-agent-acp` processes without checking if they belong to registered agents. If an agent's bridge is still alive and registered, it gets killed anyway.

**Fix:** Check `bridgePid` from registry before killing.

### 2. False Completion Detection (line 53)
An agent that writes >1 byte to output and crashes is marked as "DONE" + Linear status set to "done". The only check is `output_size > 1`, not whether the output indicates actual success.

**Fix:** Check for a completion marker (e.g., `TaskOutput` or exit code) rather than just file size.

### 3. ORPHANED Counter Always Shows 0 (linear-sync-v2.sh line 75)
The `ORPHANED` variable is incremented inside a `while read` loop fed by a pipe, which runs in a subshell. The final `echo` always prints 0.

**Fix:** Use process substitution or a here-string instead of pipe.

---

## Linear Sync Gaps

### Missing State Transitions
- Only handles: **In Progress (no agent) -> Todo**
- Does NOT handle:
  - Task manually moved to **Done** while agent still running (wasted compute)
  - Task moved to **Blocked** or **Cancelled** externally (agent keeps running)
  - Task moved from **Done** back to **Todo** (won't re-queue if already processed)

### Race Condition
Agent can complete between registry read (line 35-48) and the Linear API check (line 53-72). Brief window where a just-completed task gets moved back to Todo.

---

## Gateway Respawn Issues

1. **Dead Slack alerting:** `SLACK_WEBHOOK_URL=""` (line 12) is empty. The webhook path is dead code. The `SLACK_BOT_TOKEN` fallback (line 62) relies on an env var that may not be set in cron environment.
2. **Hardcoded sleep 8** (line 42): If gateway takes longer to start, verification fails and logs a false "FAILED to restart" even though it will come up.
3. **No max restart cap:** Will restart forever. Good for availability, but could mask a deeper issue (crash loop).

---

## Top 5 Missing Monitors (Priority Order)

### 1. CRITICAL: health-check.sh Not Running
**Impact:** All the health checks (registry integrity, stale PIDs, overtime agents, log sizes, lock files) exist in code but never execute. This is the biggest gap — we built the monitor but forgot to turn it on.

**Fix:**
```bash
# Add to crontab
*/5 * * * * /bin/bash /root/.openclaw/workspace/scripts/health-check.sh >> /root/.openclaw/tasks/agent-logs/health-check.log 2>&1
```

### 2. HIGH: No Log Rotation
**Impact:** Logs grow unbounded. Currently 1.9MB (safe), but `watchdog.log` runs every 60s and will hit multi-GB in weeks. `master.log` is already 88KB after <1 day.

**Fix:**
```bash
# /etc/logrotate.d/openclaw-agents
/root/.openclaw/tasks/agent-logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    size 10M
}
```

### 3. HIGH: No Disk Space Monitor
**Impact:** Disk at 64% used. No alerts before it fills up. Logs, agent output files, and session data accumulate.

**Fix:** Add a disk check to health-check.sh or a standalone cron:
```bash
# Alert if disk >85%
USAGE=$(df / --output=pcent | tail -1 | tr -d ' %')
[ "$USAGE" -gt 85 ] && alert "CRITICAL" "Disk usage at ${USAGE}%"
```

### 4. MEDIUM: No Linear API Key Validation
**Impact:** If `LINEAR_API_KEY` expires or `.env.linear` is deleted, both auto-queue and linear-sync silently fail (auto-queue sources with `|| true`, linear-sync exits but nobody notices).

**Fix:** Health check should validate Linear API connectivity:
```bash
# Quick API health ping
curl -s -o /dev/null -w "%{http_code}" -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -d '{"query":"{viewer{id}}"}' | grep -q "200"
```

### 5. MEDIUM: No Agent Success Rate Tracking
**Impact:** Watchdog logs completions/failures/timeouts per cycle, but there's no aggregated metric. Can't answer "what % of agents succeed?" without grepping logs.

**Fix:** Append to a metrics file each cycle:
```bash
echo "$(date +%s),$completions,$failures,$timeouts" >> /root/.openclaw/tasks/agent-logs/metrics.csv
```

---

## Implementation Plan

### Phase 1 — Quick Wins (< 30 min)
1. Re-run `install-cron-v2.sh` with gateway-respawn + health-check + auto-push included
2. Fix the ORPHANED counter subshell bug in linear-sync-v2.sh
3. Set up logrotate config for agent logs

### Phase 2 — Reliability Fixes (1-2 hours)
4. Fix ACP bridge orphan killer to respect registered bridgePids
5. Add disk space check to health-check.sh
6. Add Linear API key validation to health-check.sh
7. Fix gateway-respawn Slack alerting (use linear-log.sh instead of dead webhook)

### Phase 3 — Observability (2-3 hours)
8. Add agent success rate metrics CSV output to watchdog
9. Improve completion detection (check for success markers, not just file size)
10. Add reverse sync: kill agents whose Linear tasks were manually moved to Done/Cancelled
11. Build a daily summary cron that aggregates metrics and posts to Slack

---

## Summary

| Category | Status |
|----------|--------|
| Cron jobs running | 4/6 (health-check + auto-push missing) |
| Watchdog | Functional, 3 edge cases |
| Linear sync | Functional, missing reverse sync + subshell bug |
| Gateway respawn | Functional, dead Slack alerting |
| Log rotation | None (risk grows over time) |
| Disk monitoring | None |
| API health checks | None |
| Agent metrics | None |
