# Linear Incomplete Tasks - Analysis & Recovery Plan

**Generated:** 2026-03-05 18:20 UTC  
**Purpose:** Review tasks we started but never finished, understand gaps, plan recovery agents

---

## Summary

**Total Incomplete:** 7 tasks (5 Blocked, 1 Todo, 2 In Progress)  
**Main themes:**
1. Billy bot deployment (4 tasks - all stalled)
2. Guardian improvements (2 tasks - 1 disappeared, 1 active)
3. Infrastructure testing (1 task - abandoned mid-test)

---

## Task Breakdown

### 🔴 HIGH PRIORITY: Billy Bot (4 tasks, all blocked/todo)

#### CAI-47: Deploy Billy bot (isolated)
- **Status:** Blocked
- **What was done:** Attempted isolated workspace deployment without Docker
- **What failed:** Killed after 36+ min (frozen agent)
- **What's needed:** 
  - Billy now on separate VM (89.167.64.183)
  - OpenClaw installing right now
  - Need: finish install → configure → test
- **Recovery:** Continue current Billy deployment on VM (already in progress)

#### CAI-58: Billy bot - complete setup + start
- **Status:** Blocked
- **What was done:** Adding audio transcription skill, configuring tokens
- **What failed:** Killed after 15+ min (frozen)
- **What's needed:**
  - Audio transcription skill already built (CAI-57 complete)
  - Tokens configured (.env updated)
  - Need: integrate audio skill + start Billy
- **Recovery:** Merge with CAI-47 (same goal)

#### CAI-59: Debug Billy Slack - can't send messages
- **Status:** Blocked
- **What was done:** Investigated Slack connection issues
- **What failed:** Killed after 14+ min
- **Root cause:** Billy needs Slack App Home Messages Tab enabled (Caio fixed this)
- **What's needed:** Billy running + Caio DM test
- **Recovery:** Will resolve when CAI-47 completes

#### CAI-56: Billy pixel art - restyle
- **Status:** Todo
- **What was done:** Agent spawned, ran 36+ min
- **What failed:** Frozen, killed
- **What's needed:** Generate Billy profile pic in clean anime style (like Anton v2)
- **Dependencies:** nano-banana skill works (CAI-57 proves it)
- **Recovery:** Quick 5-min task once Billy deployment done

**Billy Recovery Plan:**
1. ✅ VM provisioned (89.167.64.183)
2. ⏳ OpenClaw installing (in progress)
3. Next: Copy Billy config → start gateway → test DM → profile pic
4. **Consolidate:** Close CAI-58, CAI-59 as duplicates of CAI-47

---

### 🟡 MEDIUM PRIORITY: Guardian Improvements

#### CAI-35: GUA-1100 Archetype Eval Loop
- **Status:** Blocked
- **What was done:** Claude Code agent (Opus) worked 60+ min on archetype standardization
- **Goal:** +5pp agreement rate improvement (76.8% → 81.8%+)
- **What failed:** Agent disappeared without reporting (likely crashed or timed out)
- **What's needed:**
  - Check if any code was committed
  - Review what was changed (if anything)
  - Run eval to see current state
  - Decide: continue or abandon
- **Recovery:** Spawn investigation agent to check git history + run eval

#### CAI-62: Guardian reprocess skill
- **Status:** In Progress (active now)
- **What's being done:** Building skill to trigger Guardian for orphaned media
- **Agent:** Opus, 2+ min runtime
- **What's needed:** Wait for completion
- **Recovery:** Already active, no action needed

**Guardian Recovery Plan:**
1. **CAI-62:** Wait for current agent (should complete in ~15-20 min)
2. **CAI-35:** After CAI-62 done, spawn investigation agent to:
   - Check guardian-agents-api git log (last 7 days)
   - Look for commits from March 5
   - If code exists: run eval and report
   - If no code: mark task as failed, document learnings

---

### 🟢 LOW PRIORITY: Infrastructure Testing

#### CAI-61: Test Hook and logging infrastructure
- **Status:** In Progress (but actually abandoned)
- **What was done:** Test agent spawned to verify linear-logger.js hook
- **What failed:** Killed after 1 min (manual stop for real task test)
- **What we learned:**
  - Hook did NOT fire (linear-logger.js not recognized by OpenClaw)
  - CLAUDE.md approach also didn't work (agents didn't self-log)
  - Manual logging works perfectly
- **Current solution:** Manual logging mandated in SOUL.md
- **What's needed:** Nothing urgent - hooks are "nice to have"
- **Recovery:** Close as incomplete, document findings in memory

**Infrastructure Recovery Plan:**
1. Close CAI-61 with status report: hooks don't work, manual logging works
2. Document in MEMORY.md: "Hook system needs proper OpenClaw docs/integration"
3. Future task: Research hook API properly (low priority)

---

## Recovery Agent Plan

### Agent 1: Billy Deployment Completion (CAI-47)
**Priority:** 🔴 HIGH  
**Type:** OpenClaw subagent  
**Duration:** 15 min  
**Dependencies:** OpenClaw install on VM (in progress)  
**Tasks:**
1. Wait for npm install to complete
2. Copy Billy config to VM
3. Start Billy gateway
4. Test DM from Caio
5. Close CAI-47, CAI-58, CAI-59 as complete

### Agent 2: Billy Profile Pic (CAI-56)
**Priority:** 🟡 MEDIUM  
**Type:** OpenClaw subagent  
**Duration:** 5 min  
**Dependencies:** nano-banana skill, style reference  
**Tasks:**
1. Generate Billy pixel art (clean anime style)
2. Save to Billy assets
3. Close CAI-56

### Agent 3: GUA-1100 Investigation (CAI-35)
**Priority:** 🟡 MEDIUM  
**Type:** OpenClaw subagent  
**Duration:** 15 min  
**Dependencies:** CAI-62 completion  
**Tasks:**
1. Check guardian-agents-api git log (last 7 days)
2. Look for archetype-related commits
3. If found: run eval, compare to baseline
4. If not found: document as failed experiment
5. Close CAI-35 with findings

### Agent 4: CAI-61 Closure (Infrastructure Test)
**Priority:** 🟢 LOW  
**Type:** Manual (Anton does it)  
**Duration:** 2 min  
**Tasks:**
1. Log completion to CAI-61 with findings
2. Mark as Done with "hooks investigation incomplete"

---

## Execution Order

1. **Now:** Continue Billy VM install (automatic, just monitor)
2. **Next (5 min):** Close CAI-61 manually
3. **Next (after Billy install):** Spawn Agent 1 (Billy deployment)
4. **After Agent 1:** Spawn Agent 2 (Billy profile pic)
5. **After CAI-62 done:** Spawn Agent 3 (GUA-1100 investigation)

---

## Expected Completion Timeline

- **CAI-61:** 2 min (manual)
- **CAI-62:** 15 min (current agent)
- **Billy deployment (CAI-47, 58, 59):** 15 min (Agent 1)
- **Billy pic (CAI-56):** 5 min (Agent 2)
- **GUA-1100 investigation (CAI-35):** 15 min (Agent 3)

**Total:** ~50 min to clear all incomplete tasks

---

## Success Criteria

✅ **Billy fully deployed** on VM, responding to Caio's DMs, has profile pic  
✅ **Guardian reprocess skill** built and tested  
✅ **GUA-1100** investigated with clear outcome (improved/failed/abandoned)  
✅ **Infrastructure test** documented with findings  
✅ **All 7 tasks** moved to Done or Canceled with clear status

---

## Tasks to Create (Post-Recovery)

After clearing incomplete work, consider these follow-ups:

1. **Workflow engine integration** - Use engine.py for structured experiments (Phase 3 from improvement plan)
2. **Hook system research** - Proper OpenClaw hook documentation/examples
3. **Agent dashboard** - Real-time agent status view (from improvement plan Phase 2)
4. **Billy skills expansion** - Add remaining 3 skills from original Billy spec

---

## Key Learnings

**What went wrong:**
- Agents froze without timeouts (35+ min unmonitored)
- No automatic logging (hooks didn't work)
- Complex deployments attempted in one shot (should break into steps)
- Lost track of running agents (no dashboard)

**What worked:**
- Audio transcription skill (CAI-57) - completed successfully
- Linear manual logging - works perfectly
- Small, focused tasks - easier to complete
- Opus for deep analysis - good for investigations

**Applied improvements:**
- Manual logging now mandatory (SOUL.md updated)
- Timeout rules enforced (5/15/25 min)
- Agent health sweeps (HEARTBEAT.md)
- Watchdog monitoring (every 10 min)
