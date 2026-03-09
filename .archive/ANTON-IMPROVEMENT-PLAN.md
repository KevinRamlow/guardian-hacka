# ANTON IMPROVEMENT PLAN

> Generated 2026-03-05 from analysis of the full day's work.  
> Purpose: Make Anton a **transparent, parallel, self-aware orchestrator** that never loses track of agents.

---

## 1. Problems Identified (With Evidence from Today)

### 1.1 — The Black Box Problem (CRITICAL)
**What happened:** Caio said *"Without this I can't know if ure working"* — Linear tasks had **zero comments** for hours. Sub-agents ran in silence. Anton reported completions in chat but never logged them to Linear.  
**Root cause:** Logging was manual and depended on Anton remembering to call `linear-log.sh`. No automation existed. The `linear-logger.js` hook was created but there's no evidence it ever fired — the hook API (`subagent:spawn`, `subagent:complete`, `subagent:error`) may not match OpenClaw's actual internal hook system.  
**Impact:** Caio had zero visibility into 3+ hours of agent work.

### 1.2 — Frozen / Disappeared Agents (HIGH)
**What happened:**
- **CAI-35 (GUA-1100):** Claude Code agent ran for 23+ minutes, then "disappeared without reporting." Marked Blocked.
- **CAI-47 (Billy deploy):** Ran 36+ minutes with no output. Killed.
- **CAI-48 (nano-banana prompting):** Ran 43+ minutes. Actually completed but showed as "running." Killed.
- **CAI-56 (Billy pixel art):** Ran 36+ minutes. Killed.

**Root cause:** No timeout enforcement. No periodic health check. No heartbeat from agents. Anton spawned-and-forgot.  
**Impact:** 4 out of ~15 tasks today froze or vanished — a ~27% failure rate.

### 1.3 — Anton Forgot About Running Agents (HIGH)
**What happened:** At 15:07 UTC, Anton discovered that CAI-47 had been running for 29 minutes without checking on it. Multiple agents went unmonitored for 35+ minutes. Anton was busy spawning new tasks while old ones rotted.  
**Root cause:** No dashboard, no periodic sweep, no alerts. The main thread had no discipline about checking agent status before spawning new work.  
**Impact:** Wasted compute, stale work, Caio's frustration.

### 1.4 — Sequential Spawn-and-Wait Pattern (MEDIUM)
**What happened:** Anton often spawned one agent, waited for it, then spawned the next. The main thread got blocked doing actual work (reading files, analyzing) instead of coordinating.  
**Root cause:** SOUL.md says "orchestrator, not worker" but there were no guardrails enforcing it. No workflow engine integration was used — all spawning was ad-hoc.  
**Impact:** Throughput was ~1 agent at a time instead of 3-5 parallel.

### 1.5 — Linear Comment Format Wrong (MEDIUM)
**What happened:** Initial comments were full reports dumped at the end. Caio clarified: *"Linear comments should work as APPLICATION LOGS — continuous, not final reports."*  
**Root cause:** No convention established. Agents didn't know what to log or when.  
**Impact:** When comments did appear, they were walls of text instead of scannable progress updates.

### 1.6 — No CLAUDE.md for Agent Logging (MEDIUM)
**What happened:** Claude Code agents (runtime="acp") had no instructions to log to Linear. Only OpenClaw subagents could be steered mid-run.  
**Root cause:** No CLAUDE.md file was ever created in the repos where agents work.  
**Impact:** Code agents were completely silent in Linear.

---

## 2. What Worked Today

| Area | Details |
|------|---------|
| **Linear infrastructure** | `linear-log.sh` works reliably once manually invoked. CAI workspace (caio-tests) is clean separation from Brandlovers. |
| **Audio transcription skill** | Built in ~10 min, Gemini Flash API, tested successfully. Shows skills can be built fast. |
| **Task creation velocity** | Anton created 25+ Linear tasks in one session. The spawn-and-track pattern works when Anton remembers to track. |
| **nano-banana fix** | Python wrapper for image gen works. Iterative improvement happened fast. |
| **Workflow engine** | `engine.py` exists with solid architecture (checkpoints, gates, decisions, loops, budgets). Never used today. |
| **Hook skeleton** | `linear-logger.js` has correct structure. Just needs to actually work. |

---

## 3. Proposed Solutions

### 3.1 — Agent Lifecycle Hooks (Auto-Logging to Linear)

**Goal:** Every sub-agent automatically logs to Linear on spawn, checkpoint, completion, and failure — zero manual intervention.

#### 3.1.1 — OpenClaw Subagent Hooks

The `linear-logger.js` hook exists at `/root/.openclaw/hooks/linear-logger.js` and is registered in `openclaw.json`. However, it may not be firing because:
1. The hook event names (`subagent:spawn`, `subagent:complete`, `subagent:error`) may not match OpenClaw's actual hook API
2. The `--status` flag syntax in the shell call is wrong (positional arg, not flag)

**Fix plan:**
```
1. Verify OpenClaw hook event names:
   - Run `openclaw hooks --help` or check OpenClaw source
   - Map actual events to our handler functions
   
2. Fix linear-logger.js:
   - Correct the shell command syntax (positional args, not flags)
   - Add retry logic (1 retry, 3s timeout)
   - Add structured log format: "[TIMESTAMP] EMOJI message"
   - Extract task ID from label OR task description OR spawn metadata
   
3. Add new events:
   - subagent:heartbeat (if supported) → periodic "still running" logs
   - subagent:steer → log when Anton steers an agent
   - subagent:kill → log when Anton kills an agent
```

**Proposed linear-logger.js v2:**
```javascript
// Key improvements:
// 1. Correct event names (verify against OpenClaw docs)
// 2. Fixed shell arg syntax
// 3. Structured log format
// 4. Timeout and error handling
// 5. Task ID extraction from multiple sources

function extractTaskId(context) {
  // Check label first (most reliable: "CAI-42-some-task")
  const sources = [
    context.label,
    context.task,
    context.metadata?.linearTaskId,
    context.metadata?.taskId
  ];
  for (const src of sources) {
    const match = src?.match(/\b(CAI-\d+)\b/i);
    if (match) return match[1].toUpperCase();
  }
  return null;
}

function logToLinear(taskId, message, status) {
  // Use positional args: linear-log.sh TASK_ID "message" [status]
  const args = [taskId, message];
  if (status) args.push(status);
  // ... exec with timeout
}
```

#### 3.1.2 — Claude Code Agent Logging (CLAUDE.md)

Claude Code agents (runtime="acp") run in their own session and read `CLAUDE.md` from the working directory. We need a `CLAUDE.md` that instructs them to log to Linear.

**Create `/root/.openclaw/workspace/CLAUDE.md`** (workspace-level, inherited by all agents):

```markdown
# CLAUDE.md - Agent Instructions

## Linear Logging (MANDATORY)

You are a sub-agent managed by Anton. Every task you work on has a Linear task ID (format: CAI-XX).

### Logging Script
```bash
/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]
```

### When to Log
1. **On start:** `linear-log.sh CAI-XX "🚀 Starting: [brief description]" progress`
2. **On checkpoint:** `linear-log.sh CAI-XX "📍 [what you just completed]"`
3. **On completion:** `linear-log.sh CAI-XX "✅ Done: [1-3 line summary of results]" done`
4. **On failure:** `linear-log.sh CAI-XX "❌ Failed: [reason]" blocked`
5. **On blocked:** `linear-log.sh CAI-XX "🚧 Blocked: [what you need]" blocked`

### Log Format
- Keep messages SHORT (1-3 lines)
- Think of these as application logs, not reports
- Include data: file paths, line counts, test results, error messages
- Example: "📍 Fixed 3 failing tests in test_archetypes.py. Running eval suite now."

### Status Values
- `progress` = In Progress
- `done` = Done
- `blocked` = Blocked (need input)
- `todo` = Todo (not started)

### Rules
- ALWAYS log on start and completion
- Log every 5-10 minutes of work (not less frequently)
- If you can't find the task ID in your instructions, log to the workspace daily file instead
- Never skip logging — Anton and Caio rely on these to track your work
```

#### 3.1.3 — Spawn Convention (Anton's Discipline)

Every time Anton spawns an agent, the task description MUST include:
```
Linear Task: CAI-XX
Log with: /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh CAI-XX "message" [status]
```

This ensures both OpenClaw subagents AND Claude Code agents know which task to log to.

### 3.2 — Agent Health Monitor (Anti-Freeze)

**Goal:** Never let an agent run for 30+ minutes unmonitored.

#### 3.2.1 — Heartbeat Sweep

Add to `HEARTBEAT.md`:
```markdown
## Agent Health Check
Every heartbeat:
1. Run `subagents list` 
2. For each running agent:
   - If running > 20 min with no recent Linear log → steer: "Status update? Log to Linear."
   - If running > 30 min with no response → kill + log "⏱️ Timed out" + mark Blocked
   - If running > 45 min → kill unconditionally
3. For each completed agent without a Linear "Done" comment → add completion log
4. Update /root/.openclaw/tasks/state.json with current agent states
```

#### 3.2.2 — Cron-Based Agent Watchdog

Create a cron job (every 10 min) that:
1. Lists all running subagents
2. Checks their age (spawn time vs now)
3. Logs a warning to a local file if any agent exceeds 25 min
4. Anton picks up warnings in next heartbeat

**Script: `/root/.openclaw/workspace/scripts/agent-watchdog.sh`**
```bash
#!/bin/bash
# Agent watchdog - runs every 10 min via cron
# Checks for stuck/frozen agents

AGENTS_DIR="/root/.openclaw/tasks"
STATE_FILE="$AGENTS_DIR/state.json"
ALERT_FILE="$AGENTS_DIR/alerts.json"

# Write alerts for Anton to pick up in heartbeat
# (Implementation: query subagents API or parse state file)
```

#### 3.2.3 — Spawn-Time Timeout

When spawning agents, ALWAYS set reasonable timeouts:
- Image generation: 5 min
- Research/analysis: 15 min
- Code implementation: 25 min max
- Complex multi-step: 30 min max (break into smaller tasks instead)

Add to SOUL.md:
```
**Agent timeout rules:**
- Never spawn without a timeout expectation
- Image/simple tasks: 5 min
- Analysis/research: 15 min
- Code work: 25 min
- If it needs >30 min, break it into sub-tasks
```

### 3.3 — Linear Status Auto-Sync

**Goal:** Linear task status always reflects reality.

#### 3.3.1 — Status Mapping

| Agent Event | Linear Status | Log Message |
|-------------|---------------|-------------|
| Agent spawned | In Progress | 🚀 Starting: {label} |
| Agent steered | In Progress | 🔄 Steered: {reason} |
| Agent checkpoint | In Progress | 📍 {checkpoint description} |
| Agent completed (success) | Done | ✅ {completion summary} |
| Agent completed (failed) | Blocked | ❌ {error reason} |
| Agent killed (timeout) | Blocked | ⏱️ Timed out after {N}min |
| Agent killed (manual) | Canceled | 🛑 Manually stopped |
| Caio requests stop | Canceled | 🛑 Stopped by Caio |
| Agent needs input | Blocked | 🚧 Blocked: {what's needed} |
| Caio approves/moves to test | Homolog | 🧪 Caio testing |

#### 3.3.2 — Implementation in linear-logger.js

Extend the hook to handle all events above. The `logToLinear` function already accepts a status parameter — just need to wire up the correct events.

### 3.4 — Parallel Execution Framework

**Goal:** Anton runs 3-5 agents simultaneously with clear tracking.

#### 3.4.1 — Spawn Batch Pattern

Instead of spawning one agent and waiting, Anton should:
```
1. Review all pending work
2. Batch spawn 3-5 agents simultaneously
3. Return main thread to Caio ("3 agents running: CAI-XX, CAI-YY, CAI-ZZ")
4. On completion announcements, process results and decide next steps
```

#### 3.4.2 — Agent Dashboard Command

Create a quick-status command Anton can run:
```bash
# /root/.openclaw/workspace/scripts/agent-dashboard.sh
# Shows: agent label | Linear task | runtime | status | last log time
```

Output example:
```
🟢 CAI-42 gua-implement    | 12min | Last log: 2min ago
🟡 CAI-43 billy-deploy     | 25min | Last log: 18min ago ⚠️
🔴 CAI-44 pixel-art        | 38min | Last log: 35min ago 🔥
✅ CAI-41 audio-skill       | Done  | 8min ago
```

#### 3.4.3 — SOUL.md Rules for Parallelism

Add to SOUL.md:
```
**Parallel execution rules:**
- Always have 2-4 agents running when work exists
- Never wait for one agent to finish before spawning the next
- Use completion announcements (push-based), don't poll
- When an agent completes, immediately assess: spawn next task OR report to Caio
- Batch related spawns in a single turn
- Main thread response after spawning: list what's running, ETA, then free for Caio
```

### 3.5 — Structured Spawn Templates

**Goal:** Standardize how agents are spawned so logging always works.

#### 3.5.1 — Spawn Template

Every agent spawn must include this context block:
```
## Task Context
- **Linear Task:** CAI-XX
- **Timeout:** {N} minutes
- **Priority:** {high|medium|low}

## Logging (MANDATORY)
Log script: /root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh
- Start: `linear-log.sh CAI-XX "🚀 Starting: {brief}" progress`
- Progress: `linear-log.sh CAI-XX "📍 {update}"`  (every 5-10 min)
- Done: `linear-log.sh CAI-XX "✅ {summary}" done`
- Failed: `linear-log.sh CAI-XX "❌ {reason}" blocked`

## Task
{actual task description}
```

#### 3.5.2 — SOUL.md Integration

Add spawn checklist to SOUL.md:
```
**Before spawning any agent, verify:**
1. ☐ Linear task created (or reusing existing)
2. ☐ Task ID included in spawn description
3. ☐ Logging instructions included
4. ☐ Timeout expectation set
5. ☐ Type correct (acp for code, subagent for non-code)
```

---

## 4. Implementation Steps (Prioritized)

### Phase 1: Immediate (Today/Tomorrow) — LOGGING WORKS

| # | Task | Files | Time |
|---|------|-------|------|
| 1.1 | **Verify OpenClaw hook event names** — Check docs/source for actual event names the hook system fires | N/A | 15 min |
| 1.2 | **Fix linear-logger.js** — Correct event names, fix shell arg syntax, add error handling | `/root/.openclaw/hooks/linear-logger.js` | 30 min |
| 1.3 | **Create CLAUDE.md** — Workspace-level agent instructions with logging mandate | `/root/.openclaw/workspace/CLAUDE.md` | 15 min |
| 1.4 | **Test hook end-to-end** — Spawn a test agent, verify Linear comment appears automatically | N/A | 15 min |
| 1.5 | **Update SOUL.md** — Add spawn checklist, timeout rules, parallelism rules | `/root/.openclaw/workspace/SOUL.md` | 15 min |

### Phase 2: This Week — MONITORING WORKS

| # | Task | Files | Time |
|---|------|-------|------|
| 2.1 | **Create agent-dashboard.sh** — Quick status view of all running agents | `/root/.openclaw/workspace/scripts/agent-dashboard.sh` | 30 min |
| 2.2 | **Update HEARTBEAT.md** — Add agent health sweep to heartbeat routine | `/root/.openclaw/workspace/HEARTBEAT.md` | 15 min |
| 2.3 | **Create agent-watchdog cron** — 10-min cron that flags stuck agents | `/root/.openclaw/workspace/scripts/agent-watchdog.sh` + cron | 30 min |
| 2.4 | **Add spawn templates to task-manager** — Standardized spawn helper | `/root/.openclaw/workspace/skills/task-manager/scripts/spawn-template.sh` | 20 min |

### Phase 3: Next Week — WORKFLOWS INTEGRATED

| # | Task | Files | Time |
|---|------|-------|------|
| 3.1 | **Integrate workflow engine with Linear** — Workflow checkpoints auto-create/update Linear tasks | `workflows/engine.py` | 2h |
| 3.2 | **Add workflow templates for common patterns** — deploy, experiment, analysis, image-gen | `workflows/templates/` | 1h |
| 3.3 | **Workflow → Linear bidirectional sync** — Caio can move Linear cards, workflow reacts | Hook + Linear webhook | 2h |
| 3.4 | **Agent report parser** — Parse completion messages into structured Linear comments | New hook | 1h |

---

## 5. Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `/root/.openclaw/workspace/CLAUDE.md` | Workspace-level Claude Code agent instructions (logging, reporting) |
| `/root/.openclaw/workspace/scripts/agent-dashboard.sh` | Quick agent status overview |
| `/root/.openclaw/workspace/scripts/agent-watchdog.sh` | Cron-based stuck agent detector |
| `/root/.openclaw/workspace/HEARTBEAT.md` | Heartbeat routine with agent health sweep |

### Modified Files
| File | Changes |
|------|---------|
| `/root/.openclaw/hooks/linear-logger.js` | Fix event names, shell syntax, add retry, structured format |
| `/root/.openclaw/workspace/SOUL.md` | Add spawn checklist, timeout rules, parallelism rules, logging mandate |
| `/root/.openclaw/workspace/AGENTS.md` | Add agent lifecycle documentation |
| `/root/.openclaw/workspace/skills/task-manager/SKILL.md` | Add spawn template, logging conventions |
| `/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh` | Add timestamp prefix, validation, retry |
| `/root/.openclaw/openclaw.json` | Verify/fix hook configuration |

---

## 6. Success Criteria

### Immediate (Phase 1)
- [ ] Spawning a subagent with "CAI-XX" in the label → Linear comment appears within 30 seconds (automated, not manual)
- [ ] Claude Code agent reads CLAUDE.md and logs at least START + DONE to Linear
- [ ] Zero tasks end with 0 comments

### Monitoring (Phase 2)
- [ ] No agent runs for >30 min without Anton noticing
- [ ] `agent-dashboard.sh` shows all running agents with last-log age
- [ ] Heartbeat sweep catches and steers/kills stuck agents
- [ ] Caio can check Linear at any time and see current status of all work

### Workflows (Phase 3)
- [ ] Workflow checkpoints auto-create Linear sub-tasks
- [ ] Workflow completion auto-closes Linear parent task
- [ ] 3+ concurrent agents running smoothly with clear Linear trail

### Overall
- [ ] Agent freeze rate drops from ~27% to <5%
- [ ] Caio never asks "what are you working on?" — Linear shows it all
- [ ] Average time between agent spawn and first Linear log: <60 seconds
- [ ] Every agent task has at least 3 Linear comments: start, progress, done/failed

---

## 7. Architecture Summary

```
                    ┌─────────────┐
                    │    Caio     │
                    │  (Linear UI) │
                    └──────┬──────┘
                           │ reads
                           ▼
                    ┌─────────────┐
                    │   Linear    │
                    │  (CAI team) │
                    └──────┬──────┘
                           │ auto-updated by
                    ┌──────┴──────┐
            ┌───────┤    Hooks    ├───────┐
            │       └─────────────┘       │
            ▼                             ▼
   ┌────────────────┐          ┌────────────────┐
   │  linear-logger │          │   CLAUDE.md    │
   │   (OpenClaw    │          │  (Claude Code  │
   │   hook, auto)  │          │  agents, self) │
   └───────┬────────┘          └───────┬────────┘
           │                           │
    ┌──────┴──────┐             ┌──────┴──────┐
    │  OpenClaw   │             │ Claude Code │
    │  Subagents  │             │   Agents    │
    └─────────────┘             └─────────────┘
           │                           │
           └───────────┬───────────────┘
                       │
                ┌──────┴──────┐
                │    Anton    │
                │ (Orchestr.) │
                │             │
                │ • Spawns    │
                │ • Monitors  │
                │ • Steers    │
                │ • Reports   │
                └──────┬──────┘
                       │
              ┌────────┴────────┐
              │   Heartbeat +   │
              │   Watchdog      │
              │   (health)      │
              └─────────────────┘
```

**Flow:**
1. Anton spawns agent → hook fires → Linear gets "🚀 Starting" comment + In Progress status
2. Agent works → logs checkpoints via `linear-log.sh` → Linear gets "📍 Progress" comments
3. Agent completes → hook fires → Linear gets "✅ Done" comment + Done status
4. If agent freezes → watchdog alerts → Anton steers/kills → Linear gets "⏱️ Timed out"
5. Caio reads Linear at any time → full visibility into all work

**Two logging paths:**
- **Automated (hooks):** OpenClaw fires events → `linear-logger.js` catches → logs to Linear. Zero effort from Anton.
- **Self-logging (CLAUDE.md):** Claude Code agents read CLAUDE.md → call `linear-log.sh` themselves during work. Agent effort, but reliable.

Both paths use the same `linear-log.sh` script as the final logging mechanism.

---

## 8. Key Lessons from Today

1. **"Fire and forget" doesn't work.** Every spawn needs a monitoring plan.
2. **Infrastructure beats discipline.** Anton "should" log to Linear but forgot. Hooks don't forget.
3. **Logs, not reports.** Continuous small updates > one big dump at the end.
4. **Break tasks smaller.** 5-15 min tasks rarely freeze. 30+ min tasks freeze ~27% of the time.
5. **Push > poll.** Use completion announcements, don't busy-wait.
6. **The workflow engine exists but wasn't used.** Ad-hoc spawning led to chaos. Workflows enforce structure.
7. **Main thread discipline.** Anton got pulled into doing work (analyzing files, reading code) instead of coordinating. Sub-agents exist for a reason.
8. **Two logging paths needed.** OpenClaw subagents get hooks (automatic). Claude Code agents need CLAUDE.md (self-service). Both must converge on Linear.

---

## 9. Quick Wins (Can Do Right Now)

1. **Create CLAUDE.md** with logging instructions → 15 min, immediate impact on next Claude Code spawn
2. **Fix linear-log.sh arg in linear-logger.js** (remove `--status`, use positional) → 5 min
3. **Add spawn checklist to SOUL.md** → 10 min, prevents "forgot to include task ID" problem
4. **Create HEARTBEAT.md with agent sweep** → 10 min, catches frozen agents every 30 min
5. **Set maxConcurrent in openclaw.json to 5** → Already set to 8, good

Total: ~40 minutes for massive improvement in transparency and reliability.
