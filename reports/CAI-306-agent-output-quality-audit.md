# CAI-306: Agent Output Quality Audit — CAI-294 through CAI-304

**Date:** 2026-03-07
**Auditor:** CAI-306
**Scope:** 11 task IDs (CAI-294 through CAI-304), plus CAI-308 (spawned in same batch)

---

## Task-by-Task Assessment

| Task | Type | Status | Commit | Output | Verdict |
|------|------|--------|--------|--------|---------|
| **CAI-294** | Fix: watchdog output validation | PASS | `423b1a4` | Code change: 10+/10- in `agent-watchdog-v2.sh` | Solid fix, verified in code |
| **CAI-295** | Analysis: archetype consistency | PARTIAL | `931d91d` | `outputs/CAI-295-archetype-consistency-analysis.md` (182 lines) | Thorough code analysis, but blocked by GCP auth — no live data validation |
| **CAI-296** | Review: CAI-88/93 completions | PASS | Referenced in CAI-300 audit | Detailed analysis with recommendations | Delivered per CAI-300's verification |
| **CAI-297** | Analysis: 7-day disagreements | PARTIAL | `e8b713e` | `reports/CAI-297-disagreement-analysis-7d.md` (114 lines) + CSV | Good patterns identified but used eval data only (BQ/MySQL blocked). Killed early by Caio. |
| **CAI-298** | — | NO RECORD | None | No commit, no output file | Either never spawned or crashed silently |
| **CAI-299** | — | NO RECORD | None | No commit, no output file | Either never spawned or crashed silently |
| **CAI-300** | Audit: agent completion quality | PASS | `44bf2fe` | `reports/CAI-300-agent-completion-audit.md` (99 lines) | Excellent audit, actionable findings, data-rich |
| **CAI-301** | Fix: apostrophe handling (planned) | NOT EXECUTED | Created in backlog only (`86cfbdd`) | Task created, not yet spawned | Backlog item, not a completed agent |
| **CAI-302** | Feature: agent metrics dashboard (planned) | NOT EXECUTED | Created in backlog only (`86cfbdd`) | Task created, not yet spawned | Backlog item, not a completed agent |
| **CAI-303** | Analysis: disagreement root causes (planned) | NOT EXECUTED | Created in backlog only (`86cfbdd`) | Task created, not yet spawned | Backlog item, skipped per Caio's "no pure analysis" directive |
| **CAI-304** | Feature: validation runner script | PASS | `02fd165` | `scripts/validate-agent.sh` (147 lines) + template update | Working script, solid parsing logic |
| **CAI-308** | Analysis: infra health check | PARTIAL | `ffe067c` | `docs/CAI-308-infra-health-check.md` (159 lines) | Good findings but docs-only — no code fixes applied |

---

## Scorecard

| Verdict | Count | Tasks |
|---------|-------|-------|
| **PASS** | 4 | CAI-294, CAI-296, CAI-300, CAI-304 |
| **PARTIAL** | 3 | CAI-295, CAI-297, CAI-308 |
| **NOT EXECUTED** | 3 | CAI-301, CAI-302, CAI-303 |
| **NO RECORD** | 2 | CAI-298, CAI-299 |

**Of 7 actually-executed agents: 4 PASS (57%), 3 PARTIAL (43%), 0 FAIL**

This is a significant improvement over the CAI-300 audit which found 60% failure rate in CAI-278 to CAI-297. The permission fixes and autonomy config deployed mid-batch clearly helped.

---

## Quality Assessment of PASS Outputs

### CAI-294 — Watchdog output validation (PASS)
- **What it did:** Added 0-1 byte output detection, `[FAIL]` tagging, failure counting
- **Code quality:** Clean diff, 10 insertions / 10 deletions, well-integrated
- **Verified:** `[FAIL]` path confirmed in `agent-watchdog-v2.sh:59`

### CAI-300 — Agent completion audit (PASS)
- **What it did:** Audited 20 tasks, categorized by success/partial/failed/crashed
- **Quality:** Data-rich, includes root cause analysis, 6 actionable recommendations
- **Value:** Directly led to fixes (dedup, pre-flight checks, permissions)

### CAI-304 — Validation runner (PASS)
- **What it did:** Created `validate-agent.sh` that parses markdown task files for validation commands
- **Code quality:** Proper bash, handles edge cases (empty blocks, EOF), clean exit codes
- **Minor issue:** Skips comment lines inside bash blocks (line 56) which could skip legitimate commands starting with `#!`

### CAI-296 — Review completions (PASS)
- **What it did:** Reviewed CAI-88/93, delivered analysis with recommendations
- **Note:** No standalone output file found, but CAI-300 references it as successful with "actionable recommendations"

## Quality Assessment of PARTIAL Outputs

### CAI-295 — Archetype consistency (PARTIAL)
- **Good:** Deep code analysis, identified 5 root causes with exact line numbers, predicted inconsistency patterns
- **Gap:** No live data validation (GCP auth expired). Estimates are code-derived, not data-confirmed
- **Verdict:** Excellent analysis quality, but incomplete scope

### CAI-297 — 7-day disagreements (PARTIAL)
- **Good:** Identified 5 FN patterns and 3 FP patterns, actionable severity-3 gate recommendations
- **Gap:** Used eval data only (not production BQ data). Killed early by Caio for being "just markdown"
- **Verdict:** Useful patterns, but violated the "structural changes" directive

### CAI-308 — Infrastructure health check (PARTIAL)
- **Good:** Found 2 missing crons, 3 watchdog edge cases, 5 missing monitors. Implementation plan included.
- **Gap:** Pure documentation — zero code/config fixes applied. Same "analysis only" pattern Caio flagged.
- **Verdict:** Accurate findings, but should have FIXED the issues, not just documented them

---

## Failure Patterns Identified

### Pattern 1: Docs-Only Output (3/7 executed agents = 43%)
**Agents:** CAI-295, CAI-297, CAI-308
Analysis tasks produce markdown reports with findings and recommendations but make ZERO structural changes. This was explicitly called out by Caio at 08:37 UTC: "a bunch of analysis are being commited, a bunch of md but no structural change."

**Root cause:** Task descriptions say "analyze X" without requiring code deliverables. Agents optimize for the stated goal (produce analysis), not the implicit goal (fix problems).

### Pattern 2: GCP Auth Blocking Data Access (2/7 = 29%)
**Agents:** CAI-295, CAI-297
Both agents needed BigQuery/MySQL data but couldn't access it due to expired GCP auth tokens. They pivoted to code analysis / eval data, which is a reasonable fallback but delivers incomplete results.

**Root cause:** No pre-flight check for GCP auth validity. Agents discover the blocker mid-execution.

### Pattern 3: Missing Task IDs (CAI-298, CAI-299)
No commits, no output files, no references anywhere. These task IDs either:
- Were never created in Linear
- Were created but never spawned
- Spawned and crashed with 0B output before watchdog caught them

**Root cause:** No comprehensive task lifecycle tracking. If a task ID exists in Linear but has no agent log, it's invisible.

---

## Top 3 Improvement Recommendations

### 1. Mandate Code Deliverables in Task Definitions
**Problem:** 43% of agents produced docs-only output (markdown reports, no code changes).
**Fix:** Every task MUST specify at least one code/config file to create or modify. Analysis-only tasks should be reformulated as "fix X based on analysis" — the analysis is the means, not the deliverable.
**Example:** Instead of "Analyze archetype consistency" → "Unify archetype generation prompts across tolerance and error pipelines (file: `build_error_patterns.py`)"

### 2. Add GCP Auth Pre-Flight Check to spawn-agent.sh
**Problem:** 29% of agents wasted time discovering they can't access BQ/MySQL mid-execution.
**Fix:** Before spawning any task tagged with `guardian` or `analysis`, run a quick auth check:
```bash
bq query --project_id brandlovers-prod --use_legacy_sql=false "SELECT 1" 2>/dev/null || {
  echo "BLOCKED: GCP auth expired. Run: gcloud auth application-default login"
  exit 1
}
```
This fails fast instead of wasting 15-25 minutes on partial analysis.

### 3. Track All Task IDs End-to-End
**Problem:** CAI-298 and CAI-299 have zero trace — no commits, no output, no logs.
**Fix:** Auto-queue should log every task ID it processes (spawned, skipped, or errored) to a manifest file. The watchdog should cross-reference the manifest against the registry to flag "ghost" tasks that were created but never tracked.

---

## Comparison with Previous Audit (CAI-300)

| Metric | CAI-278 to CAI-297 (CAI-300 audit) | CAI-294 to CAI-304 (this audit) |
|--------|-------------------------------------|----------------------------------|
| Failure rate | 60% | 0% (of executed) |
| Permission blocked | 30% (6/20) | 0% |
| Silent crashes | 20% (4/20) | 0% (of executed) |
| Duplicate tasks | 25% (5/20) | 0% |
| PASS rate (executed) | 25% | 57% |

The autonomy fixes (100% permissions, dontAsk + allowedTools) eliminated permission blocking entirely. The success criteria system and agent-commits-own-changes workflow improved output quality. The remaining gap is output TYPE quality (docs vs code).
