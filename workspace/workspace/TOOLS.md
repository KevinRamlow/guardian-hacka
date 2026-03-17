# TOOLS.md - Local Notes

## Current Setup

### Slack
- Token: $SLACK_USER_TOKEN (in $OPENCLAW_HOME/.env)
- User: caio.fonseca (U04PHF0L65P)
- Channels: #tech-gua-ma-internal (team), #guardian-alerts (prod), Luca DM (U0388ARSD9N)

### Google (GOG)
- Accounts: caio.fonseca@brandlovrs.com, caiobragadafonseca@gmail.com
- Keyring: $GOG_KEYRING_PASSWORD (in $OPENCLAW_HOME/.env)

### GitHub
- Account: fonsecabc
- Token: $GITHUB_TOKEN (in $OPENCLAW_HOME/.env)
- Scopes: repo, read:org, read:user, notifications
- Key repos: guardian-agents-api, guardian-api, guardian-ads-treatment (all in brandlovers-team org)
- guardian-agents-api cloned locally at `${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api/`

### GCP / gcloud
- gcloud SDK installed at `/opt/google-cloud-sdk/` (v559.0.0)
- PATH configured in ~/.bashrc
- bq CLI available (v2.1.28)

### Linear
- **Brandlovers** (READ): $LINEAR_API_KEY_BRANDLOVERS (in $OPENCLAW_HOME/.env) | Teams: GUA, PLT, GTM, SMA, DevOps, CTX
- **caio-tests** (R/W): $LINEAR_API_KEY (in $OPENCLAW_HOME/.env) | Team: AUTO | Track Anton orchestration

### Task Manager (Anton's Orchestration Tracking)
- **State file:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json` (single source of truth)
- **Agent logs:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/agent-logs/`
- **Status command:** `bash scripts/task-manager.sh list`

### GCP
- Production project: `brandlovers-prod`
- Homolog project: `brandlovrs-homolog`
- Cluster: `bl-cluster` in `us-east1`
- BigQuery for tolerance/error patterns analysis

### MySQL
- Instance: brandlovers-prod:us-east1 (Cloud SQL 8.0) | DB: db-maestro-prod
- Connection: Direct TCP via `mcporter call mysql-creator-ads.*` or `mcporter call mysql-catalyst.*`
- Config: `workspace/config/mcporter.json` (env vars: CREATOR_ADS_DB_*, DB_CATALYST_*)
- Tables: proofread_medias, media_content, actions, campaigns, guidelines
- Join: proofread_medias.action_id → actions.id ← media_content.action_id

### Metabase
- URL: https://metabase.brandlovers.ai
- MCP server: `metabase` in `workspace/config/mcporter.json`
- Access: `mcporter call metabase.<tool> --output json`
- Discover tools: `mcporter list metabase --schema`

### Langfuse
- URL: https://us.cloud.langfuse.com | Project: cmhdj3t2z088oad08j6wngqhc
- MCP server: `langfuse` in `workspace/config/mcporter.json`
- Access: `mcporter call langfuse.<tool> --output json`
- Discover tools: `mcporter list langfuse --schema`
- Note: Anton's own project (NOT Guardian's) | 256K+ traces
