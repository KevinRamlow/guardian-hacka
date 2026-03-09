# Agent Cost Analysis & Optimization Report

**Date:** 2026-03-07 | **Task:** CAI-318 | **Scope:** 219 spawned agents (all time)

## Key Findings

### 1. Waste Rate: 24.2% of agents produce zero useful output

- **53/219 agents failed** (exit code != 0 or empty output)
- **47 agents (21.5%) produced <=1 byte of output** — total waste
- **27.5% of prompt input bytes were wasted** on failed agents
- Exit codes: 204 unknown (`?`), 6 exit-code-1, 7 exit-code-0, 2 killed (137)

### 2. Repetitive tasks burn tokens on the same problems

| Theme | Tasks | Wasted | Waste % |
|---|---|---|---|
| Guardian disagreement analysis | 32 | 8 | 25% |
| Apostrophe escaping fixes | 16 | 1 | 6% |
| Agent audit/review | 16 | 2 | 12% |
| Watchdog | 12 | 0 | 0% |
| Backlog/queue | 11 | 3 | 27% |
| Guardian tolerance | 11 | 3 | 27% |
| Monitoring | 9 | 1 | 11% |
| Health checks | 8 | 1 | 12% |
| Dashboard/metrics | 7 | 2 | 29% |

**16 agents** were spawned to fix the same apostrophe escaping bug. **32 agents** ran guardian disagreement analysis (many overlapping).

### 3. All agents default to Opus — no model tiering

- Every agent uses `claude-opus-4-6` (default when no `--model` flag)
- Fallback chain exists (opus -> sonnet -> haiku) but only triggers on API limits
- **No smart routing**: analysis tasks, test tasks, and simple fixes all use the most expensive model
- Opus: ~$30/M tokens blended. Sonnet: ~$9/M (3.3x cheaper). Haiku: ~$1/M (30x cheaper).

### 4. CLAUDE.md injection adds 3.3KB to every prompt

- CLAUDE.md: 3,280 bytes injected into every spawn task file
- Across 219 tasks: **718KB of repeated boilerplate** (~180K tokens at 4 chars/token)
- Average prompt size: 2,136B (actual task) + 3,280B (CLAUDE.md) = ~5.4KB per spawn
- This is ~60% overhead per task just for the instructions

### 5. Cost tracking is broken

- Dashboard shows `totalTokensToday: 194,603` and `estimatedCostToday: $2,919` but all recent agents show `tokens=0, cost=$0`
- Token counting relies on `g.usage?.total || g.totalTokens` which returns 0 for `--print` mode agents
- **We have no actual visibility into per-agent token spend**

---

## Optimization Recommendations

### R1: Route simple tasks to Sonnet/Haiku (est. 60-70% cost reduction)

Tasks that DON'T need Opus:
- Analysis/monitoring tasks (read-only, no complex code) -> **Sonnet** (3.3x cheaper)
- Test tasks, health checks, simple queries -> **Haiku** (30x cheaper)
- Repetitive re-runs of the same analysis -> **Haiku**

Tasks that DO need Opus:
- Complex code implementation (multi-file changes, architecture)
- Eval pipelines with iterative reasoning
- Tasks requiring deep codebase understanding

**Implementation:** Add `--model` flag to backlog-generator.sh based on task emoji/type:
- `analysis/monitor/review` -> `claude-sonnet-4-6`
- `test/health/simple query` -> `claude-haiku-4-5-20251001`
- `feature/fix/implement` -> `claude-opus-4-6` (default)

### R2: Deduplicate before spawning (est. 15-20% reduction)

The auto-queue spawns overlapping tasks without checking if a similar task recently ran:
- 16x apostrophe fix attempts (should have been 1-2)
- 32x guardian disagreement analysis (weekly is enough)
- Multiple overlapping health checks

**Implementation:** Before spawning, check last N completed tasks for similar descriptions. Skip if a matching task completed successfully in the last 6h.

### R3: Fail-fast with cost cap per agent (est. 10-15% reduction)

47 agents produced zero output but still consumed input tokens (CLAUDE.md + task prompt).
Each wasted spawn costs ~$0.15-0.30 in input tokens alone (5.4KB * $30/M tokens).

**Implementation:**
- Add `--max-tokens` flag to claude CLI calls (cap output at 4096 for analysis, 8192 for code)
- Kill agents that produce no output after 2 minutes (currently waits full timeout)
- Pre-validate task requirements (e.g., does the DB connection work?) before spawning

### R4: Shrink CLAUDE.md injection (est. 5-10% reduction)

3.3KB of instructions on every spawn is wasteful. Most of it is generic context the agent doesn't need.

**Implementation:**
- Create a minimal `CLAUDE-AGENT.md` (~500B) with just: commit format, logging format, forbidden actions
- Move detailed context to project-level CLAUDE.md (loaded automatically by claude CLI)
- Saves ~2.8KB * N_agents of input tokens

### R5: Fix token tracking (no direct savings, enables optimization)

Current dashboard shows $0 cost for all agents because `--print` mode doesn't report token usage.

**Implementation:**
- Parse claude CLI's stderr for usage stats (if available)
- Or: estimate from prompt file size + output log size using model-specific token ratios
- Track per-category spend to validate R1-R4 savings

---

## Estimated Impact

| Optimization | Effort | Est. Savings |
|---|---|---|
| R1: Model tiering | Medium | 60-70% |
| R2: Task dedup | Low | 15-20% |
| R3: Fail-fast | Low | 10-15% |
| R4: Shrink CLAUDE.md | Low | 5-10% |
| R5: Fix tracking | Medium | Enables measurement |

**Combined estimated savings: 65-75%** (R1 dominates since model cost is the biggest lever).

At ~200 agents/day using Opus ($30/M tokens), switching 70% of tasks to Sonnet ($9/M) would reduce daily spend by roughly 50-60%.
