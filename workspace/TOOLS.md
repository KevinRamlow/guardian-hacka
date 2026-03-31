# TOOLS.md - Local Notes

## Current Setup

### Slack
- Token: $SLACK_USER_TOKEN (in $OPENCLAW_HOME/.env)
- User: kevin.ramlow (U04PHF0L65P)
- Channels: #tech-gua-ma-internal (team), #guardian-alerts (prod)

### GitHub
- Token: $GITHUB_TOKEN (in $OPENCLAW_HOME/.env)
- Scopes: repo, read:org, read:user, notifications
- Key repos: guardian-agents-api, guardian-api, guardian-ads-treatment (all in brandlovers-team org)
- guardian-agents-api cloned locally at `${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api/`

### GCP / gcloud
- gcloud SDK installed at `/opt/google-cloud-sdk/` (v559.0.0)
- PATH configured in ~/.bashrc
- bq CLI available (v2.1.28)
- Production project: `brandlovers-prod`
- Homolog project: `brandlovrs-homolog`
- Cluster: `bl-cluster` in `us-east1`
- BigQuery for tolerance/error patterns analysis

### Linear
- **Brandlovers** (READ): $LINEAR_API_KEY_BRANDLOVERS (in $OPENCLAW_HOME/.env) | Teams: GUA, PLT, GTM, SMA, DevOps, CTX
- **Sentinel** (R/W): $LINEAR_API_KEY (in $OPENCLAW_HOME/.env) | Team: SENT | Track Sentinel orchestration

### Task Manager (Sentinel's Orchestration Tracking)
- **State file:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json` (single source of truth)
- **Agent logs:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/agent-logs/`
- **Status command:** `bash scripts/task-manager.sh list`

### Few-Shot Database
- **Location:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/few-shot.db`
- **Engine:** sqlite-vec (vector similarity search)
- **Embeddings:** Gemini (gemini-embedding-001)
- **Stores:** eval cases with classification, guideline text, answers, agreement status, error type
- **Query:** `bash scripts/few-shot-db.sh query --classification <type> --type success/failure --limit N`
- **Ingest:** `bash scripts/few-shot-db.sh ingest --run-dir <path-to-eval-run>`
- **Stats:** `bash scripts/few-shot-db.sh stats`

### Langfuse
- URL: https://us.cloud.langfuse.com | Project: cmhdj3t2z088oad08j6wngqhc
- MCP server: `langfuse` in `workspace/config/mcporter.json`
- Access: `mcporter call langfuse.<tool> --output json`
- Discover tools: `mcporter list langfuse --schema`
