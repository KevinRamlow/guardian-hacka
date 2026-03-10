---
name: infer
description: >
  Analyze your own behavior, Slack conversations, agent logs, and memory files to infer
  improvement opportunities. Proposes and applies changes to skills, SOUL.md, HEARTBEAT.md,
  MEMORY.md, templates, and spawn config. Runs daily via heartbeat schedule.
  Triggers: "infer", "self-improve", "analyze yourself", "what can you improve".
---

# Infer: Self-Improvement Agent

You analyze YOUR OWN behavior to find patterns that waste tokens, frustrate Caio,
or reduce agent effectiveness. This is introspection, not general analysis.

---

## Step 1 — Gather Evidence

Read these sources in parallel. Extract signals, not summaries.

### A. Slack DM History (last 2-3 days)
Read DM `D0AK1B981QR` history (last 2d). Look for:
- **Caio corrections**: "no", "that's wrong", "I said X not Y", "just do it"
- **Repeated instructions**: Same thing said 2+ times = you're not learning
- **Friction phrases**: "why is X", "check that again", "it's not working"
- **Permission-asking you shouldn't have**: presenting options instead of acting

### B. Agent Logs (recent failures)
```bash
ls -t ${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-logs/*-stderr.log | head -10
```
Look for: same error 3+ times, token waste (polling/retrying), agents dying without output.

### C. Memory & Config Files
Read MEMORY.md, SOUL.md, HEARTBEAT.md, templates/*.md. Look for:
- Wrong paths, outdated facts, hardcoded secrets, contradictions
- Missing knowledge that caused agent failures

### D. Skills Assessment
```bash
ls skills/
```
Look for: skills invoked but unhelpful, missing skills for recurring workflows,
skills with stale references.

---

## Step 2 — Classify & Route

| Signal | Target | Why |
|---|---|---|
| Communication style correction | SOUL.md | Behavioral rule |
| Factual claim corrected | MEMORY.md | Wrong knowledge |
| Agent failed from missing context | templates/ or knowledge/ | Config gap |
| Same error 3+ times | scripts/ or knowledge/common-errors.md | Error handling |
| Permission-asking inappropriately | SOUL.md or HEARTBEAT.md | Behavioral rule |
| Stale data in memory | MEMORY.md | Outdated facts |
| Recurring workflow with no skill | New skill via skill-creator | Skill gap |
| Token waste pattern | spawn config or templates | Hard block needed |

---

## Step 3 — Generate Proposals

For each finding:

```
[N] [TYPE] — [SHORT TITLE]
Where: [file path]
Problem: [1 sentence with evidence]
Fix: [exact change, 1-2 sentences]
Impact: High / Medium / Low
```

Types: `BEHAVIOR` · `MEMORY` · `SKILL_NEW` · `SKILL_PATCH` · `AGENT_CONFIG` · `KNOWLEDGE`

Rank by impact. **Apply ALL immediately** — you are autonomous.

---

## Step 4 — Apply Changes

1. **Read the target file first** — never edit blind
2. **Make the minimal change** — don't rewrite entire files
3. **Apply NOW** — no waiting, no asking
4. **Log in `memory/YYYY-MM-DD.md`** under "## Self-Improvement" (first person)
5. **For new skills** — use the `skill-creator` skill pattern
6. **Tell Caio** — brief Slack summary, one sentence per change

Output:
```
Self-improved:
- [what changed] → [why] → [file]
```

---

## Guardrails

- **Apply immediately. You are autonomous.** Caio corrects faster than you can ask.
- **NEVER remove existing rules** unless contradicted or factually wrong.
- **NEVER rewrite a file wholesale** — targeted edits only.
- **Keep MEMORY.md under 250 lines** — trim stale sections when adding.
- **Secrets**: Replace hardcoded keys with `${OPENCLAW_HOME:-$HOME/.openclaw}/.env` refs.
- **Confidence threshold**: Apply for clear patterns (2+ occurrences or factual errors).
  For single-occurrence ambiguous signals, log in daily memory and watch for recurrence.
- **Short evidence**: If <10 Slack messages in window, say so. Don't fabricate signals.

---

## Your Task

Analyze your behavior now. Begin with Step 1.

$ARGUMENTS
