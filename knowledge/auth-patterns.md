# Auth Patterns — Known Issues and Fixes

## GCP RAPT (Re-Authentication Policy)

GCP enforces periodic re-authentication. When tokens expire:
```bash
gcloud auth login --update-adc
gcloud auth print-access-token  # verify it works
```

## Eval Environment Setup

Always source the eval env file FIRST:
```bash
source ~/.openclaw/workspace/.env.guardian-eval
```
This sets `GOOGLE_CLOUD_PROJECT=brandlovers-prod` and other required vars.

## Service Account Credentials

- File: `~/.openclaw/workspace/.gcp-credentials.json`
- Used when ADC (Application Default Credentials) is not available
- wire.py can decode base64-encoded credentials from `GOOGLE_ACCOUNT_CREDENTIALS` env var

## Common Auth Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| 403 PERMISSION_DENIED on GCS | Wrong project or expired token | `source .env.guardian-eval` then re-auth |
| 403 on prod GCS buckets | Using homolog SA | Switch to prod credentials |
| "Agent execution failed unexpectedly" | Usually auth | Check `gcloud auth print-access-token` |
| Cloud SQL connection refused | Proxy not running | Start Cloud SQL Proxy first |

## Quick Auth Test

```bash
gcloud auth print-access-token > /dev/null 2>&1 && echo "OK" || echo "NEED RE-AUTH"
```
