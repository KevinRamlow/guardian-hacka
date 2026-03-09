# Agent Completion Quality Audit: CAI-278 to CAI-297

**Date:** 2026-03-07
**Auditor:** CAI-300 (automated)
**Scope:** 20 tasks (CAI-278 through CAI-297)

## Summary

| Metric | Count | % |
|--------|-------|---|
| **Full success** (working deliverable, verified) | 5 | 25% |
| **Partial success** (some output, incomplete) | 3 | 15% |
| **Failed** (no deliverable despite "done" status) | 10 | 50% |
| **Crashed** (died immediately, 0B output) | 2 | 10% |

**Incomplete rate: 60%** — far exceeds the 20% threshold. Improvement task required.

## Task-by-Task Assessment

### FULL SUCCESS (5/20)

| Task | Description | Evidence |
|------|-------------|----------|
| **CAI-290** | Disagreement analysis | `reports/CAI-290-disagreement-analysis.md` (9.5KB) exists, actionable findings |
| **CAI-292** | Health check script | `scripts/health-check.sh` + `install-cron-v2.sh` exist, tested |
| **CAI-293** | Add Glob,Grep to allowedTools | Commit `6ac2e92` verified, code change confirmed |
| **CAI-294** | Output validation in watchdog | Commit `423b1a4` verified, `[FAIL]` tag in code confirmed |
| **CAI-296** | Review CAI-88/93 completions | Detailed analysis delivered with actionable recommendations |

### PARTIAL SUCCESS (3/20)

| Task | Description | Issue |
|------|-------------|-------|
| **CAI-291** | Extract test scenarios | Script created (`scripts/extract-test-scenarios.py`), test file in `guardian-agents-api/tests/unit/` but NOT committed to workspace repo |
| **CAI-295** | Archetype consistency analysis | Commit `931d91d` exists, but analysis based on code review only — no live data (GCP auth expired) |
| **CAI-297** | 7-day disagreement analysis | Commit `e8b713e` exists, but 0B output log — unclear what was actually analyzed |

### FAILED — Permission Blocked (6/20)

| Task | Description | Root Cause |
|------|-------------|------------|
| **CAI-278** | Fix apostrophe in auto-queue | Write permission denied |
| **CAI-280** | Fix apostrophe (retry #2) | Write permission denied |
| **CAI-282** | Fix apostrophe (retry #3) | Write permission denied |
| **CAI-284** | Fix apostrophe (retry #4) | Write permission denied |
| **CAI-285** | Add regression tests | Write permission denied |
| **CAI-286** | Fix shell quote escaping | Write permission denied |

**Note:** CAI-278/280/282/284/286 are the SAME apostrophe fix spawned 5 times. The auto-queue kept re-creating the same task without checking if previous attempts were permission-blocked.

### FAILED — DB Access Blocked (2/20)

| Task | Description | Root Cause |
|------|-------------|------------|
| **CAI-283** | Guardian moderation error analysis | MySQL CLI blocked by sandbox + no MCP tool |
| **CAI-287** | Guardian moderation analysis | MySQL CLI blocked by sandbox |

### FAILED — Empty Output / Crash (4/20)

| Task | Description | Root Cause |
|------|-------------|------------|
| **CAI-279** | Guardian moderation analysis | 1B output — silent failure |
| **CAI-281** | Review recent guardian | 1B output — silent failure |
| **CAI-288** | Unknown | 0B output, died in <1 min |
| **CAI-289** | Unknown | 0B output, died in <1 min |

## Failure Patterns

### 1. Permission Blocking (6/20 = 30%)
Agents spawn without write permissions and cannot complete file edits. They diagnose the problem correctly but can't apply fixes. The auto-queue then re-spawns the same task, wasting cycles.

### 2. Duplicate Task Spawning (5/20 = 25%)
The apostrophe fix was spawned 5 separate times (CAI-278, 280, 282, 284, 286) — all failed identically. No dedup logic in auto-queue prevents re-spawning blocked tasks.

### 3. Silent Agent Death (4/20 = 20%)
Four agents produced 0-1B output with no error diagnostics. No pre-flight checks catch this.

### 4. Missing DB Access (2/20 = 10%)
Analysis tasks requiring MySQL/BigQuery fail because GCP auth is expired and MySQL MCP isn't configured for sub-agents.

## Root Causes

1. **spawn-agent.sh `--allowedTools`** was missing Glob/Grep (fixed by CAI-293), but Write was always listed — the sandbox itself was blocking writes, not the tool config.
2. **auto-queue-v2.sh** has no dedup: it re-queues tasks that failed with the same root cause.
3. **No pre-flight checks**: agents don't verify they can write/query before starting work.
4. **GCP auth expired**: all BigQuery/MySQL queries fail silently.

## Recommendations

1. **Add dedup to auto-queue**: Before spawning, check if a task with the same title was recently blocked/failed. Skip or escalate instead of retrying blindly.
2. **Pre-flight permission check**: At agent start, verify write access to workspace and DB access before doing analysis work.
3. **Fix sandbox permissions**: Ensure spawned agents can write to `/root/.openclaw/workspace/` — this is the #1 failure cause.
4. **Refresh GCP auth**: Run `gcloud auth login` to unblock all analysis tasks.
5. **Add output validation** (partially done by CAI-294): Flag 0-1B outputs as failures, don't mark them "done" in Linear.
6. **Cap retries**: If a task fails 2x with the same error pattern, mark it as `blocked` and stop retrying.

## Verdict

**60% failure rate is critical.** The system is burning compute cycles on duplicate blocked tasks. The 5 successful tasks (CAI-290, 292, 293, 294, 296) show agents CAN deliver when permissions/access work. The fix is infrastructure (permissions, dedup, pre-flight checks), not agent capability.
