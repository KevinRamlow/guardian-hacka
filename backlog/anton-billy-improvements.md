# Anton + Billy Improvement Backlog

## Anton (Orchestrator) Improvements

### 1. Agent Validation System (CRITICAL)
**Problem:** 0% real validation - just forward "done" messages
**Solution:** Automated validation runner
- Read success criteria from task
- Run validation commands
- Compare output vs expected
- Report ✅/❌ with proof
**Impact:** Catch fake completions before marking Done

### 2. Agent Output Quality Scoring
**Problem:** No way to measure if agent output is good/complete
**Solution:** Quality score (0-100)
- File count changed
- Lines of code/text produced
- Test pass rate
- Commits made
**Impact:** Objective agent performance tracking

### 3. Smart Task Retry Logic
**Problem:** Failed tasks just sit Blocked forever
**Solution:** Auto-retry with improved context
- Detect retry-able failures (permissions, timeouts)
- Add failure context to retry task
- Max 2 retries, then escalate to Caio
**Impact:** Reduce manual intervention

### 4. Anton Self-Improvement Loop
**Problem:** Anton doesn't learn from mistakes systematically
**Solution:** Weekly self-analysis cron
- Review failed agents
- Identify patterns
- Update SOUL.md/AGENTS.md/templates
- Test improvements
**Impact:** Continuous improvement without manual work

## Billy (ClawdBots) Improvements

### 5. Billy Boost Configuration Skill
**Problem:** Users can't see/edit boost configs (currently manual DB)
**Solution:** Conversational boost config interface
- "show boost config for brand X"
- "update boost limit for Y to 500 per month"
- "disable boost for campaign Z"
**Impact:** Self-service for non-tech team

### 6. Billy Campaign Performance Reports
**Problem:** Users ask "how is campaign X doing?"
**Solution:** Natural language campaign reports
- Parse campaign name from message
- Query MySQL: metrics, creator performance, content stats
- Generate concise report with key numbers
**Impact:** Instant insights without SQL

### 7. Billy Auto-Presentation Generator
**Problem:** nano-banana generates images but manual assembly
**Solution:** End-to-end presentation creation
- User: "create presentation about campaign X results"
- Billy: queries data, generates charts, assembles slides
- Output: Google Slides link or PowerPoint download
**Impact:** 10min task → 30sec

### 8. Billy Proactive Campaign Monitoring
**Problem:** Billy waits for questions, doesn't alert
**Solution:** Daily campaign health checks
- Check campaigns with issues (low approval rate, slow creator response)
- Alert team in Slack with summary
- Suggest actions
**Impact:** Catch problems before they escalate

## Priority Order (Based on Impact)

**P0 (This Week):**
1. Agent Validation System (Anton) - fixes fake completions
2. Billy Boost Configuration Skill - immediate user value

**P1 (Next Week):**
3. Agent Output Quality Scoring (Anton) - better monitoring
4. Billy Campaign Performance Reports - high user demand

**P2 (Following Week):**
5. Smart Task Retry Logic (Anton) - reduce manual work
6. Billy Auto-Presentation Generator - big time saver

**P3 (Later):**
7. Anton Self-Improvement Loop - long-term improvement
8. Billy Proactive Monitoring - nice-to-have

## Implementation Strategy

**For Anton improvements:** Spawn agents, validate outputs myself
**For Billy improvements:** SSH to Billy VM, test directly, validate with sample queries

**Validation criteria for each:**
- P0 tasks: Manual validation + test cases
- P1-P3: Agent validation with spot checks
