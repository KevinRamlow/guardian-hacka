# Memory System - How Anton Never Forgets

## The Problem
OpenClaw sessions restart, contexts get compacted, and critical information can be lost. Anton needs persistent memory that survives restarts and summarizes work continuously.

## The Solution

### 1. Core Memory Files (Always Loaded)
These files define who Anton is and are loaded on every session start:

- **SOUL.md** — Core identity, principles, how Anton works
- **IDENTITY.md** — Role definition (Orchestrator + The Hands concept)
- **USER.md** — About Caio (preferences, work patterns, people)
- **TOOLS.md** — Tool configurations, schemas, local notes
- **AGENTS.md** — Session workflow (what to read on startup)
- **HEARTBEAT.md** — Proactive monitoring schedule

### 2. Long-Term Memory (Main Session Only)
- **MEMORY.md** — Curated knowledge base
  - Guardian architecture & pipelines
  - Workflow orchestration system
  - ClawdBots platform details
  - Key decisions & lessons learned
  - Only loaded in main session (privacy)

### 3. Daily Memory Files (Auto-Updated Every 10 Minutes)
- **memory/YYYY-MM-DD.md** — Session logs for each day
  - Key decisions made
  - Tasks started/completed
  - Important context to preserve
  - Current work status
  - Timestamped entries

**Auto-Update Mechanism:**
- Cron job triggers every 10 minutes
- Anton reviews last 10 minutes of conversation
- Updates today's memory file with significant events
- Silent operation (no chat replies)

### 4. Project-Specific Memory
- **workflows/** — State files for running workflows
  - `.openclaw/workflows/<id>-state.md` (human-readable)
  - `.openclaw/workflows/<id>-state.json` (machine-readable)
  - Captures iteration progress, variables, checkpoint results

- **clawdbots/** — Agent-specific context
  - Each agent has its own SOUL.md, TOOLS.md, memory/

## Memory Update Schedule

**Every 10 minutes (Cron):**
- Review recent conversation
- Update `memory/YYYY-MM-DD.md`
- Capture decisions, tasks, status

**Every heartbeat (~30 min during work hours):**
- Check calendar, email, Slack, Linear, GitHub
- Review memory files and curate MEMORY.md if needed

**On significant events:**
- Task completion → update daily memory
- Workflow checkpoint → update workflow state
- New learning → update MEMORY.md

## How Anton Uses Memory

**Session Start:**
1. Read SOUL.md (who I am)
2. Read USER.md (who Caio is)
3. Read memory/YYYY-MM-DD.md (today + yesterday)
4. **In main session:** Also read MEMORY.md (long-term context)

**During Work:**
- Before answering questions about prior work → `memory_search` + `memory_get`
- After completing tasks → update daily memory file
- At decision points → reference MEMORY.md for lessons learned

**Memory Maintenance:**
- Every few days during heartbeat: review recent daily files
- Extract significant learnings and update MEMORY.md
- Remove outdated info from MEMORY.md
- Think of it like a human reviewing their journal and updating mental models

## Memory Hierarchy

```
┌─────────────────────────────────────┐
│  SOUL.md, IDENTITY.md, USER.md      │  ← Core identity (always loaded)
├─────────────────────────────────────┤
│  MEMORY.md                          │  ← Curated knowledge (main session only)
├─────────────────────────────────────┤
│  memory/YYYY-MM-DD.md               │  ← Daily logs (auto-updated every 10 min)
├─────────────────────────────────────┤
│  workflows/<id>-state.md            │  ← Active work state (per workflow)
└─────────────────────────────────────┘
```

## Cron Job Details

**Job ID:** `0f84ec27-940f-4bc1-ba45-2d42064e4149`
**Schedule:** Every 10 minutes (600,000 ms)
**Action:** System event to main session
**Payload:** "[MEMORY UPDATE] Review the last 10 minutes of conversation. Update /root/.openclaw/workspace/memory/2026-03-05.md with: (1) Key decisions made, (2) Tasks started/completed, (3) Important context to preserve, (4) Current work status. Be concise. Include timestamps. If nothing significant happened, write 'No updates.' DO NOT reply in chat — only update the file."

**To check:** `cron list`
**To disable:** `cron update --id 0f84ec27-940f-4bc1-ba45-2d42064e4149 --enabled false`

## Why This Works

1. **Survives restarts** — Files persist across session crashes
2. **Progressive detail** — Recent work in daily files, curated learnings in MEMORY.md
3. **Context aware** — Anton always knows what happened in the last 10 min, yesterday, and long-term
4. **Low overhead** — 10-min updates are fast, don't interrupt work
5. **Human readable** — Caio can read memory files to understand what happened

## Example Daily Memory Entry

```markdown
## 13:43 UTC - Full Context Recovery & Memory System Setup

**Context Restored:**
- Read `last-convo.txt` with full conversation history
- Recovered understanding of Anton's role as orchestrator

**Key Decisions:**
- Created memory update cron (every 10 min)
- Updated SOUL.md with orchestrator principles

**Tasks Completed:**
- ✅ Configured core memory files
- ✅ Set up auto-update system

**Current Status:**
- Ready to resume GUA-1100 with workflow system
- Billy improvements workflow pending

---
```

This system ensures Anton never loses context, even across restarts, compaction, or long gaps between sessions.
