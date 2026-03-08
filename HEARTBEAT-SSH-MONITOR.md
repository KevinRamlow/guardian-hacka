# HEARTBEAT.md - SSH-Based Monitoring (Son of Anton)

## Role: Observer, NOT Executor

**Anton (Mac)** = Executor — runs agents, evals, auto-queue
**Son of Anton (VPS)** = Observer — monitors Anton's state via SSH

## What NOT to do
- **DO NOT spawn agents locally**
- **DO NOT run evals locally**
- **DO NOT run auto-queue locally**
- All orchestration happens on Mac, I just monitor

## Every heartbeat (5min)

### Priority 1 — Monitor Anton's Auto-Loop
```bash
ssh anton-mac "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status"
```
Check for:
- Loop running? (last heartbeat < 10min ago)
- Queue empty? → nudge to generate backlog
- Failures spiking? → investigate

### Priority 2 — Monitor Active Agents
```bash
ssh anton-mac "bash ~/.openclaw/workspace/scripts/agent-registry.sh list"
```
Check for:
- Agents near timeout → tell Anton to extend
- Failed agents → tell Anton to diagnose
- Completed agents → acknowledge in #replicants

### Priority 3 — Check State Files
```bash
ssh anton-mac "cat ~/.openclaw/workspace/.anton-auto-state.json"
ssh anton-mac "cat ~/.openclaw/workspace/.anton-meta-state.json"
```
Extract:
- Last spawn time
- Success rate (last 24h)
- Budget remaining

### Priority 4 — Report to #replicants (every 4h)
Post summary:
```
[SUPERVISION] @Anton Status Report

Auto-loop: ✅ Active (last run: 3min ago)
Agents: 2 active, 0 failed, 1 completed in last 4h
Success rate: 85% (17/20)
Budget: $12.34 / $50 daily

Recent completions:
- AUTO-123: Guardian eval improvement (+2.3pp)
```

## If Anton goes silent
- No auto-loop activity > 30min → alert in #replicants
- Gateway down → alert immediately
- 3+ consecutive agent failures → alert with pattern

## SSH Shortcuts
Create in `.shortcuts/`:
- `monitor-anton` — full status check
- `check-agents` — agent registry
- `tail-logs` — recent activity

## When to stay quiet
Reply `HEARTBEAT_OK` if:
- Anton's loop healthy
- No failures
- Not time for 4h report
