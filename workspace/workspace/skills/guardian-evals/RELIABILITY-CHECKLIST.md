# Guardian Evals Reliability Checklist

> Lessons learned from CAI-35 / GUA-1100 eval execution (2026-03-05).
> Use this checklist before every Guardian eval run.

---

## Pre-Flight Checks

### 1. Authentication & Credentials

- [ ] **GCP Project Config:** Verify `GOOGLE_CLOUD_PROJECT=brandlovers-prod` (Vertex AI) and `BIGQUERY_PROJECT=brandlovrs-homolog` (eval data)
- [ ] **OAuth Token Validity:** Run `gcloud auth application-default print-access-token` — if it fails, re-auth BEFORE starting
- [ ] **Token Lifetime:** OAuth user tokens expire after ~1 hour. If eval takes >30 min, use a **service account** instead
- [ ] **Service Account (Recommended):** Set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json` for unattended runs
- [ ] **GOOGLE_APPLICATION_CREDENTIALS in .env:** Ensure it's set in the eval .env file, not just shell env

### 2. When to Use Service Account vs User OAuth

| Scenario | Auth Method | Why |
|---|---|---|
| Quick test (<15 min) | User OAuth (`gcloud auth`) | Simple, fast |
| Full eval (>30 min) | Service Account JSON | Won't expire mid-run |
| CI/CD pipeline | Service Account JSON | No interactive auth possible |
| One-off debugging | User OAuth | Convenience |

**Rule of thumb:** If eval has >50 cases or takes >30 min, ALWAYS use service account.

### 3. Dataset Validation

- [ ] **Dataset exists:** Verify eval dataset path/table is accessible
- [ ] **Sample count:** Know expected case count (e.g., 80 for general_guidelines)
- [ ] **No stale data:** Check dataset freshness (BigQuery table last modified)

### 4. Environment

- [ ] **Branch correct:** `git status` shows experiment branch
- [ ] **Dependencies installed:** `pip install -r requirements.txt` recent
- [ ] **Env vars loaded:** Source the correct .env file
- [ ] **Disk space:** At least 1GB free for results/logs

---

## Error Handling Patterns

### MAX_TOKENS Errors

**Root Cause:** Some videos/content exceed model context window. Specific videos consistently trigger this (e.g., Nike bonnet video in test_idx 2, 58).

**Solution:**
```
AGENTS_RETRY_MAX_ATTEMPTS=3  (compromise: retries transient errors, gives up on persistent ones)
```

**Do NOT:**
- Set `AGENTS_RETRY_MAX_ATTEMPTS=1` (kills needed transient retries)
- Set `AGENTS_RETRY_MAX_ATTEMPTS=5+` (wastes time on persistent failures)

**Handling pattern:**
1. Detect MAX_TOKENS error on first attempt
2. Retry up to 3 times (may be transient load issue)
3. On 3rd failure, **skip and log** the case
4. Record skipped case in results file with reason
5. Continue eval with remaining cases
6. Report: "X/Y cases evaluated (Z skipped: MAX_TOKENS)"

### OAuth Token Expiration

**Root Cause:** User OAuth tokens expire after ~60 min. Long-running evals (18+ min with 80 cases) can span expiration.

**Detection:**
- HTTP 401 errors mid-eval
- `google.auth.exceptions.RefreshError`
- Sudden cluster of failures after initial successes

**Prevention:**
1. **Best:** Use service account (never expires during run)
2. **Good:** Pre-validate token AND check remaining lifetime before start
3. **Acceptable:** Implement token refresh callback mid-run (complex)

**Recovery:**
- Save partial results immediately on auth failure
- Log which cases completed vs failed
- After re-auth, resume from last failed case (don't re-run completed)

### BrokenPipeError / tqdm Output Issues

**Root Cause:** tqdm progress bars fail when stdout is redirected (common in sub-agent environments).

**Fix:** Redirect tqdm to stderr or disable:
```python
from tqdm import tqdm
for item in tqdm(items, file=sys.stderr, disable=not sys.stderr.isatty()):
    ...
```

---

## Error Classification

### Permanent Errors (Skip Immediately)

- MAX_TOKENS after 3 retries on same content
- Invalid/corrupt media file
- Missing required fields in test case
- Content type not supported

### Transient Errors (Retry Up to 3x)

- HTTP 429 (rate limit) — add exponential backoff
- HTTP 500/502/503 (server error)
- Network timeout
- OAuth refresh needed (if using refresh mechanism)

### Fatal Errors (Abort Eval)

- OAuth expired with no refresh mechanism
- Dataset not found
- Wrong GCP project config
- Critical dependency missing

---

## Partial Results Tracking

### Progress File

Save progress incrementally to avoid losing completed work:

```python
# After each case completion
progress = {
    "eval_id": "gua-1100-iter1",
    "timestamp": datetime.utcnow().isoformat(),
    "total_cases": 80,
    "completed": 58,
    "skipped": 3,
    "failed": 0,
    "skipped_reasons": {
        "test_idx_2": "MAX_TOKENS (3 retries)",
        "test_idx_58": "MAX_TOKENS (3 retries)",
        "test_idx_71": "MAX_TOKENS (3 retries)"
    },
    "partial_results": {
        "agrees": 42,
        "disagrees": 13,
        "agreement_rate": 0.764
    }
}
# Write after every 5 cases or on any error
with open("/tmp/eval-progress.json", "w") as f:
    json.dump(progress, f)
```

### Resume Capability

Design evals to support resume:
1. Track completed case IDs
2. On restart, load progress file
3. Skip already-completed cases
4. Merge results at end

---

## Logging Requirements

### Minimum Logging

Every eval run MUST log:
1. **Start:** timestamp, config, dataset, expected case count
2. **Progress:** Every 10 cases or every 5 minutes (whichever first)
3. **Errors:** Every error with case ID, error type, retry count
4. **Skips:** Every skipped case with reason
5. **End:** timestamp, total results, agreement rate, skipped count

### Log Format

```
[EVAL] 2026-03-05T20:00:00Z START dataset=general_guidelines cases=80 config=prod
[EVAL] 2026-03-05T20:03:00Z PROGRESS 10/80 completed, 0 skipped, 0 errors
[EVAL] 2026-03-05T20:05:00Z ERROR case=2 type=MAX_TOKENS retry=1/3
[EVAL] 2026-03-05T20:05:30Z ERROR case=2 type=MAX_TOKENS retry=2/3
[EVAL] 2026-03-05T20:06:00Z SKIP case=2 reason=MAX_TOKENS_PERSISTENT
[EVAL] 2026-03-05T20:18:00Z END 55/80 valid (22 auth_fail, 3 max_tokens) agreement=76.4%
```

### Linear Updates

Log to Linear task every 5 min during eval:
```bash
linear-log.sh CAI-XX "📍 Eval progress: 40/80 cases, 2 skipped (MAX_TOKENS), current agreement: 78.2%"
```

---

## Recovery Mechanisms

### If OAuth Expires Mid-Run

1. Catch auth error immediately
2. Save partial results to `/tmp/eval-progress.json`
3. Log: "OAuth expired at case N/M. Partial results saved."
4. Report to Linear with partial results
5. After re-auth: resume from case N

### If Agent Crashes

1. Progress file persists in `/tmp/eval-progress.json`
2. New agent reads progress file
3. Resumes from last checkpoint
4. Merges results

### If MAX_TOKENS Overwhelms

If >20% of cases hit MAX_TOKENS:
1. Stop eval
2. Investigate: is the model context too small?
3. Consider: chunking strategy, content pre-filtering, or model upgrade
4. Re-run with adjusted parameters

---

## Pre-Run Checklist (Copy-Paste Version)

```
## Guardian Eval Pre-Flight — [DATE]

- [ ] GCP config: GOOGLE_CLOUD_PROJECT=brandlovers-prod
- [ ] GCP config: BIGQUERY_PROJECT=brandlovrs-homolog  
- [ ] Auth: Service account key set (for runs >30 min)
- [ ] Auth: Token valid (`gcloud auth print-access-token`)
- [ ] Auth: GOOGLE_APPLICATION_CREDENTIALS in .env
- [ ] Dataset: Accessible and fresh
- [ ] Branch: Correct experiment branch checked out
- [ ] Config: AGENTS_RETRY_MAX_ATTEMPTS=3
- [ ] Config: tqdm output redirected to stderr
- [ ] Progress: /tmp/eval-progress.json writeable
- [ ] Logging: Linear task ID known
- [ ] Timeout: Estimated runtime < auth token lifetime
```

---

## Metrics from CAI-35 (Reference)

| Metric | Value | Notes |
|---|---|---|
| Total cases | 80 | general_guidelines dataset |
| Auth failures | 22 (27.5%) | OAuth expired ~60 min into run |
| MAX_TOKENS | 3 (3.75%) | Consistent videos (test_idx 2, 58) |
| Valid results | 55 (68.75%) | Only 55/80 usable |
| Agreement rate | 76.4% | vs 76.8% baseline = neutral |
| Runtime | ~18 min | Per eval iteration |
| Config issues | 2 | Wrong project + missing GOOGLE_APPLICATION_CREDENTIALS |

**Lesson:** 31.25% of eval cases were wasted due to preventable issues (auth + config).

---

*Last updated: 2026-03-05*
*Created from: CAI-35 / GUA-1100 post-mortem*
