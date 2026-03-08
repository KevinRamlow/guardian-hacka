---
name: self-improve
description: >
  Analyze your own Slack conversations, agent logs, and memory files to find behavioral
  patterns, stale data, and friction points. Propose concrete improvements to SOUL.md,
  HEARTBEAT.md, MEMORY.md, templates, and spawn config. Apply after Caio approves.
  Trigger: "infer", "self-improve", "analyze yourself", "what can you improve",
  or during scheduled heartbeat self-review (every 3 days).
---

# Self-Improvement Protocol

You are analyzing YOUR OWN behavior to find patterns that waste tokens, frustrate Caio,
or reduce agent effectiveness. This is introspection, not general analysis.

---

## When to Run

- Caio says: "infer", "self-improve", "analyze yourself", "what can you improve"
- Scheduled: Every 3 days during heartbeat, run a mini self-review
- After a bad session: Multiple agent failures, Caio corrections, or wasted work

---

## Step 1 — Gather Evidence

Read these sources in parallel. Extract signals, not summaries.

### A. Slack DM History (last 2-3 days)
```
Read Slack DM D0AK1B981QR history (last 2d)
```
Look for:
- **Caio corrections**: "no", "that's wrong", "I said X not Y", "just do it"
- **Repeated instructions**: Same thing said 2+ times = you're not learning
- **Friction phrases**: "why is X", "check that again", "it's not working", "review your work"
- **Caio doing your job**: Him fixing things you should have caught
- **Permission-asking you shouldn't have**: "quer que eu...", presenting options

### B. Agent Logs (recent failures)
```bash
ls -t ~/.openclaw/tasks/agent-logs/*-stderr.log | head -10
# Check for patterns: same error repeating, same task failing
```
Look for:
- Same error type failing 3+ times without fix
- Token waste patterns (polling, retrying impossible tasks)
- Agents dying without output (spawn config issues)

### C. Memory Files (staleness check)
```
Read MEMORY.md, SOUL.md, HEARTBEAT.md, templates/claude-md/*.md
```
Look for:
- **Wrong paths** (`/root/` instead of `/Users/fonsecabc/`)
- **Outdated facts** (old baselines, stopped services listed as active, wrong project IDs)
- **Hardcoded secrets** (API keys in .md files instead of .env references)
- **Contradictions** (SOUL says X, HEARTBEAT says opposite)
- **Missing knowledge** that caused agent failures

### D. Session Transcripts (if available)
```bash
ls -t ~/.claude/projects/-Users-fonsecabc--openclaw-workspace/*.jsonl | head -3
```
Look for:
- Tools used excessively (50+ Bash calls = probably polling)
- Agent thinking patterns that waste tokens
- Skills invoked but not helpful

---

## Step 2 — Classify Findings

For each signal, classify where the fix belongs:

| Signal | Target | Why |
|---|---|---|
| Caio corrected your communication style | SOUL.md Communication Rules | Behavioral rule |
| Caio corrected a factual claim | MEMORY.md | Wrong knowledge |
| Agent failed from missing context | templates/claude-md/*.md or knowledge/*.md | Sub-agent config gap |
| Same agent error 3+ times | spawn-agent.sh or knowledge/common-errors.md | Spawn or error handling |
| You asked permission when you shouldn't | SOUL.md or HEARTBEAT.md | Behavioral rule |
| Stale data in memory | MEMORY.md | Outdated facts |
| Path/config wrong | Whichever file has it | Direct fix |
| Token waste pattern | spawn-agent.sh (--disallowedTools) or templates | Hard block needed |
| Missing tool access for agents | spawn-agent.sh (--mcp-config) | Tool config |

---

## Step 3 — Generate Proposals

For each finding, output:

```
[N] [TYPE] — [SHORT TITLE]
Where: [file path]
Problem: [1 sentence — what went wrong, with evidence from Slack/logs]
Fix: [1-2 sentences — exact change]
Impact: High / Medium / Low
```

Types: `BEHAVIOR` (SOUL/HEARTBEAT rules), `MEMORY` (stale data), `AGENT_CONFIG` (templates/spawn),
`KNOWLEDGE` (knowledge files), `TOOL_ACCESS` (MCP/permissions)

Rank by impact. Then **apply ALL of them immediately** — do not wait for approval.

After applying, send Caio a brief summary of what you changed and why.

---

## Step 4 — Apply Changes

For each finding:

1. **Read the target file first** — never edit blind
2. **Make the minimal change** — don't rewrite entire files
3. **Apply it NOW** — no waiting, no asking
4. **Log the change** in `memory/YYYY-MM-DD.md` under "## Self-Improvement" (first person)
5. **Tell Caio** what you changed — brief summary in Slack, one sentence per change

Output summary:
```
Self-improved:
- [what changed] → [why] → [file]
```

---

## Guardrails

- **Apply immediately. You are autonomous.** Caio will tell you if something is wrong — that's faster than asking permission.
- **NEVER remove existing rules** unless they directly contradict a new rule or are factually wrong.
- **NEVER rewrite a file wholesale** — make targeted edits.
- **Keep MEMORY.md under 250 lines** — if adding, also trim stale sections.
- **Secrets**: If you find hardcoded keys in .md files, replace with `.env.secrets` references.
- **Short sessions**: If conversation is <10 messages, say so. Don't fabricate signals.
- **Confidence threshold**: Apply fixes for clear patterns (2+ occurrences or factual errors). For ambiguous single-occurrence signals, log them in daily memory and watch for recurrence — don't change rules based on one data point.

---

## Mini Self-Review (Heartbeat Mode)

During scheduled heartbeat self-review, run a lighter version:

1. Read last 1d of Slack DM history
2. Check for Caio corrections or repeated instructions
3. Verify MEMORY.md paths and facts are current
4. If 0 findings → log "Self-review: no issues found" and move on
5. If findings → **apply fixes immediately**, then tell Caio what you improved

Don't interrupt Caio for self-review results unless something is urgent (e.g., secrets in committed files).

---

## Your Task

Analyze your behavior now. Begin with Step 1.
