# Common Errors — Quick Reference

| Error | Cause | Fix |
|-------|-------|-----|
| `403 PERMISSION_DENIED` | Wrong GCP project or expired credentials | `source .env.guardian-eval` then `gcloud auth login --update-adc` |
| `429 RESOURCE_EXHAUSTED` / rate limit | Too many API requests | Wait 30s, retry up to 3x. Reduce `--workers` |
| `MAX_TOKENS` / token limit exceeded | Content too long for model context | Skip item, eval continues automatically |
| `ModuleNotFoundError` | Virtual env not activated or missing deps | `source .venv/bin/activate && pip install -e .` |
| `ENOTFOUND` / DNS resolution | Network connectivity issue | Retry once; check VPN/DNS |
| `idle_killed` | Agent timeout while doing background work | Increase timeout in spawn config |
| `"Agent execution failed unexpectedly"` | Auth expired or config missing | Check auth: `gcloud auth print-access-token`; check env vars sourced |
| `FileNotFoundError: Config file` | Wrong path to eval.yaml | Run from repo root: `cd guardian-agents-api-real` |
| `FileNotFoundError: Dataset` | Wrong dataset path | Use relative path from config dir, or absolute path |
| `ValueError: Unsupported runner` | Typo in eval.yaml runner name | Must be `content_moderation` or `critique_guidelines` |
| `Authentication failed (Langfuse)` | Langfuse credentials missing | Eval uses `enable_langfuse=False`; check if running via app instead |
| `Cloud SQL connection refused` | Cloud SQL Proxy not running | Start proxy: `cloud-sql-proxy <instance>` |
| `google.auth.exceptions.RefreshError` | GCP RAPT policy re-auth needed | `gcloud auth login --update-adc` |
