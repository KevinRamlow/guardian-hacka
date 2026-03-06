# Anton Dashboard Fixes - CAI-71

## Completed: 2026-03-06 15:49 UTC

### Problem 1: Stats Persistence ✅ FIXED
**Issue:** Stats reset to 0 on gateway restart
**Solution:** 
- Added `stats-history.json` file at `/root/.openclaw/workspace/dashboard/stats-history.json`
- Stats saved on every poll cycle (8s)
- Stats loaded on startup
- Automatic midnight UTC reset for daily stats
- Structure includes: `completedToday`, `failedToday`, `totalTokensToday`, `estimatedCostToday`, `recentAgents[]`

**Files Modified:** `server.js`
**Functions Added:**
- `loadStatsFromDisk()` - Load stats on startup
- `saveStatsToDisk()` - Save after each poll
- `checkMidnightReset()` - Reset daily stats at midnight UTC

### Problem 2: Langfuse Wrong Traces ✅ FIXED
**Issue:** Showing BigQuery infrastructure traces with 0 tokens
**Solution:**
- Changed from `/api/public/traces` to `/api/public/observations?type=GENERATION`
- Query now fetches actual LLM generation calls (not infrastructure spans)
- Filter: Guardian/moderation/content/severity keywords OR totalTokens > 0
- Limit: 100 (API max)
- Result: Now showing 800K+ tokens from real Guardian LLM traces

**Before:** 20 traces, 0 tokens (BigQuery infra)
**After:** 100 traces, 800,332 tokens (Guardian LLM calls)

### Problem 3: Recent Agents Persistence ✅ FIXED
**Issue:** Recent agents list empty after restart
**Solution:**
- Recent agents now stored in `stats-history.json` under `recentAgents[]`
- Merged with CLI output (`openclaw subagents list --json`)
- Deduplication by sessionKey
- Keeps last 20 agents
- Updates on every poll cycle

**Behavior:**
- When agents complete: Added to `recentAgents[]` and saved
- On restart: Recent agents loaded from disk
- Dashboard shows persistent history even when no active agents

### Files Modified
- `/root/.openclaw/workspace/dashboard/server.js`

### Verification Commands
```bash
# Check stats file exists and has data
cat /root/.openclaw/workspace/dashboard/stats-history.json

# Verify API response
curl -s http://localhost:8765/api/state | python3 -m json.tool

# Check Langfuse showing real traces
curl -s http://localhost:8765/api/state | jq '.langfuse | {totalTraces, totalTokens, avgLatency}'

# Test persistence: restart and verify stats maintained
pkill -f "dashboard/server.js" && sleep 2 && cd /root/.openclaw/workspace/dashboard && node server.js &
sleep 5 && curl -s http://localhost:8765/api/state | jq '.stats'
```

### Current State
- Dashboard running on http://localhost:8765
- Stats: 0 completed (no agents run yet)
- Langfuse: 100 traces, 800,332 tokens, $0.38 cost
- Recent agents: 0 (will populate when agents run)

### Notes
- Langfuse query changed from traces to observations/GENERATION
- This captures actual LLM calls with token usage
- Filter includes: guardian, moderation, content, severity keywords
- Stats persist across gateway restarts
- Midnight UTC auto-reset for daily metrics
