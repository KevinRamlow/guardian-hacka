# HEARTBEAT.md

## Timed Checks (Sao Paulo Timezone)

### 9 AM Morning Check
- **Today's calendar** (events from 9 AM onwards, both accounts)
- **Linear updates** (Guardian team GUA, assigned issues, any blocked items)
- **GitHub activity** (unread notifications, PR review requests on guardian repos)
- **Gmail** unanswered messages (both work and personal accounts)
- **Slack** unread DMs and mentions
- **Guardian alerts** — check #guardian-alerts for any overnight incidents

### 2 PM Midday Check
- **Slack threads** — any unresolved discussions in #tech-gua-ma-internal
- **Linear** — any status changes on GUA issues
- **PR reviews** — any pending reviews assigned to Caio

### 6 PM Evening Check
- Same as 9 AM, plus:
- Summary of what Caio discussed/accomplished today in Slack
- List of unresolved discussions or follow-ups needed
- Tomorrow's calendar preview
- Any Guardian moderation metrics alerts (agreement rate drops, contest spikes)

## Monitoring Schedule

**During work hours (08:00-23:00):**
- 9:00 AM: Morning work check
- 2:00 PM: Midday check
- 6:00 PM: Evening check + summary

**Outside work hours:** HEARTBEAT_OK (no proactive checks)

## Guardian-Specific Monitoring

If I detect any of these patterns, alert Caio immediately:
- Guardian pod restarts or crashes (check #guardian-alerts)
- Spike in contest rate (> 2x normal)
- Agreement rate drop below 70%
- Any "Error moderating content" alerts
- Pipeline failures (tolerance/error patterns)

## Agent Health Sweep (ONLY IF ACTIVE AGENTS)

**Critical:** Check running sub-agents to prevent freeze/disappearance issues.

1. **Check if any agents active:** `subagents list` - if no active agents, skip and reply HEARTBEAT_OK
2. **If active agents exist:** Continue with health checks

2. **For each running agent:**
   
   **Check Linear log freshness:**
   - Query Linear API for task's last comment timestamp
   - If last comment > 15 min ago AND agent running > 20 min:
     - Steer: "Status update required. You've been running X min with no Linear updates since {timestamp}. Report NOW: what iteration, what's happening, results/stuck status. Log to Linear immediately."
     - Log to Linear: "🔄 [HH:MM UTC] Steered: {X}min with no updates. Requested status report."
   
   **Timeout enforcement:**
   - **If running > 30 min with no Linear response after steer:**
     - Kill agent
     - Log to Linear: "⏱️ [HH:MM UTC] Timed out after 30+ min"
     - Mark Linear task as Blocked
     - Report to Caio
   - **If running > 45 min:**
     - Kill unconditionally (frozen)
     - Log timeout + mark Blocked

3. **For each recently completed agent:**
   - Verify Linear task has "✅ Done" comment
   - If missing, add completion log from agent output
   - Verify Linear status is Done/Blocked/Homolog (not In Progress)

4. **Update tracking:**
   - Update `/root/.openclaw/tasks/state.json` with current states
   - Track agent runtime in memory file

**Linear log freshness query:**
```bash
source /root/.openclaw/workspace/.env.linear && \
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issue(id:\"CAI-XX\"){comments(first:1 orderBy:createdAt){nodes{createdAt}}}}"}' | \
  jq -r '.data.issue.comments.nodes[0].createdAt'
```

**If 2+ agents frozen:** Alert Caio immediately with summary.

**Agent freeze prevention:**
- Automatically steer agents with stale logs (>15 min)
- Kill agents that don't respond (>30 min)
- Never rely on manual monitoring

## Self-Improvement Trigger

Every 3 days during a heartbeat, review:
1. Recent `memory/YYYY-MM-DD.md` files
2. Update MEMORY.md with significant learnings
3. Check if any new patterns should be added to skills

## Agent Status Check Protocol (LEARNED 2026-03-05)

**ALWAYS check BOTH sources for complete picture:**

1. **Actual sub-agent runtime** (source of truth for current state):
```bash
subagents list
```
Look for:
- `startedAt` timestamp (when current run started)
- `runtime` / `runtimeMs` (actual elapsed time)
- `status` (running/done/timeout/error)

2. **Linear task comments** (communication history):
```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issue(id:\"CAI-XX\"){comments(first:3 orderBy:createdAt){nodes{createdAt body}}}}"}'
```
Look for:
- Last update timestamp
- What agent reported
- Progress indicators

**Cross-reference:**
- If agent running 30 min BUT last Linear comment is 25 min ago → agent may be stuck (steer)
- If agent just restarted (startedAt recent) BUT Linear shows old progress → agent lost context (may need restart)
- If agent shows "done" BUT Linear has no completion → missed logging (add it manually)

**Never assume:**
- ❌ Don't infer agent survived restart from Linear comments alone
- ❌ Don't assume continuous runtime without checking startedAt
- ❌ Don't trust Linear timestamps as agent runtime

**Always verify:**
- ✅ Check subagents list for actual current state
- ✅ Check Linear for what agent communicated
- ✅ Cross-reference timestamps between both
