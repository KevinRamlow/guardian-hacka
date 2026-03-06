# Guardian Evals Skill

Run and manage Guardian evaluation pipelines against BigQuery datasets.

## Overview

Evaluates Guardian agent accuracy by comparing agent decisions against human-reviewed ground truth. Supports iterative experiment loops with automatic result tracking.

## Usage

Guardian evals run inside `guardian-agents-api/` using the eval harness.

### Quick Start

```bash
cd /root/.openclaw/workspace/guardian-agents-api
# Load environment
source .env

# Run eval (general_guidelines, 80 cases)
python -m eval.run --dataset general_guidelines --output /tmp/eval-results.json
```

### Configuration

**Required env vars:**
- `GOOGLE_CLOUD_PROJECT=brandlovers-prod` — Vertex AI (model inference)
- `BIGQUERY_PROJECT=brandlovrs-homolog` — Eval dataset source
- `GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json` — For runs >30 min
- `AGENTS_RETRY_MAX_ATTEMPTS=3` — Balance retry vs skip

**⚠️ CRITICAL:** Always verify config before running. See RELIABILITY-CHECKLIST.md.

## Pre-Flight

Before EVERY eval run, complete the checklist in `RELIABILITY-CHECKLIST.md`:
1. Auth valid (service account for long runs)
2. GCP projects correct (Vertex AI prod, BigQuery homolog)
3. GOOGLE_APPLICATION_CREDENTIALS set in .env
4. Branch correct
5. AGENTS_RETRY_MAX_ATTEMPTS=3

## Error Handling

### Known Issues (from CAI-35, 2026-03-05)

1. **OAuth Expiration:** User tokens expire ~60 min. Use service accounts for evals.
2. **MAX_TOKENS:** Some videos exceed context window. Skip after 3 retries.
3. **tqdm BrokenPipe:** Redirect tqdm to stderr in sub-agent environments.
4. **Config Mismatch:** ALWAYS verify both GOOGLE_CLOUD_PROJECT and BIGQUERY_PROJECT.

### Error Classification

- **Permanent:** MAX_TOKENS (3 retries), corrupt media → skip and log
- **Transient:** Rate limits, server errors → retry with backoff
- **Fatal:** Auth expired, wrong project, dataset missing → abort and report

## Results Tracking

Save progress incrementally to `/tmp/eval-progress.json`:
- After every 5 cases
- On any error
- Includes: completed, skipped (with reasons), partial agreement rate

## Workflow Integration

Uses `guardian-experiment.yaml` workflow template:
1. implement → run-pipeline → analyze → eval-gate → decide
2. Max 5 iterations, 300 min budget
3. Completion promise: +5pp over baseline

## Lessons Learned

- 31.25% of CAI-35 eval cases wasted due to auth + config issues
- Service accounts are non-negotiable for runs >30 min
- AGENTS_RETRY_MAX_ATTEMPTS=3 is the sweet spot (1 too aggressive, 5 too slow)
- Always save partial results — crashes happen
- tqdm + stdout redirection = BrokenPipeError

## Files

- `SKILL.md` — This file
- `RELIABILITY-CHECKLIST.md` — Pre-flight checklist and error patterns
