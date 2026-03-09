# TOOLS.md - Local Notes

## Current Setup

### Slack
- Token: $SLACK_USER_TOKEN (see .env.secrets)
- User: caio.fonseca (U04PHF0L65P)
- Channels: #tech-gua-ma-internal (team), #guardian-alerts (prod), Luca DM (U0388ARSD9N)

### Google (GOG)
- Accounts: caio.fonseca@brandlovrs.com, caiobragadafonseca@gmail.com
- Keyring: $GOG_KEYRING_PASSWORD (see .env.secrets)
- Env: source ~/.openclaw/workspace/.env.gog

### GitHub
- Account: fonsecabc
- Token: $GITHUB_TOKEN (see .env.secrets)
- Scopes: repo, read:org, read:user, notifications
- Key repos: guardian-agents-api, guardian-api, guardian-ads-treatment (all in brandlovers-team org)
- guardian-agents-api cloned locally at `/root/.openclaw/workspace/guardian-agents-api/`

### GCP / gcloud
- gcloud SDK installed at `/opt/google-cloud-sdk/` (v559.0.0)
- PATH configured in ~/.bashrc
- **AUTH NOT YET CONFIGURED** — need service account key from Caio
- bq CLI available (v2.1.28)

### Linear
- **Brandlovers** (READ): $LINEAR_API_KEY_BRANDLOVERS (see .env.secrets) | Teams: GUA, PLT, GTM, SMA, DevOps, CTX
- **caio-tests** (R/W): $LINEAR_API_KEY (see .env.secrets) | Team: CAI | Track Anton orchestration
- Config: /root/.openclaw/workspace/.env.linear

### Task Manager (Anton's Orchestration Tracking)
- **Location:** `/root/.openclaw/workspace/skills/task-manager/`
- **Tracking method:** Local files (NOT Brandlovers Linear workspace)
- **Active tasks:** `/root/.openclaw/tasks/active.md`
- **History:** `/root/.openclaw/tasks/history/YYYY-MM-DD.md`
- **State file:** `/root/.openclaw/tasks/state.json`
- **Quick view:** `cat /root/.openclaw/tasks/active.md` or `./.shortcuts/tasks`
- **Status command:** `./skills/task-manager/scripts/task-manager.sh status`
- **Note:** Anton's orchestration work stays separate from company product tasks

### GCP
- Production project: `brandlovers-prod`
- Homolog project: `brandlovrs-homolog`
- Cluster: `bl-cluster` in `us-east1`
- BigQuery for tolerance/error patterns analysis

### MySQL
- Instance: brandlovers-prod:us-east1 (Cloud SQL 8.0) | DB: db-maestro-prod
- Connection: `mysql -e "query"` (creds in ~/.my.cnf)
- Tables: proofread_medias, media_content, actions, campaigns, guidelines
- Join: proofread_medias.action_id → actions.id ← media_content.action_id

### Metabase
- URL: https://metabase.brandlovers.ai (behind Cloudflare Access — not directly reachable)
- API Key: $METABASE_API_KEY (see .env.secrets)
- MCP config at: /root/.claude/mcp_config.json
- mcporter configured at: /root/.openclaw/workspace/config/mcporter.json
- **Status**: Not usable from server (Cloudflare Access blocks API calls)

### Langfuse
- URL: https://us.cloud.langfuse.com | Project: cmhdj3t2z088oad08j6wngqhc
- Public: $LANGFUSE_PUBLIC_KEY (see .env.secrets)
- Secret: $LANGFUSE_SECRET_KEY (see .env.secrets)
- Note: Anton's own project (NOT Guardian's)
- Usage: Guardian agent trace analysis (256K+ traces)
