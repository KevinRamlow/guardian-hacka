# Billy Agent - Deployment Guide

**Status:** Ready for testing
**Date:** 2026-03-05

---

## Prerequisites

### 1. Create Slack App for Billy

Billy needs his own Slack bot token (separate from Anton). Steps:

1. Go to https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. **App Name:** Billy
4. **Workspace:** BrandLovers (or your test workspace)
5. Click **"Create App"**

#### Configure OAuth & Permissions

Under **OAuth & Permissions**, add these **Bot Token Scopes:**
- `app_mentions:read` — See @mentions
- `channels:history` — Read public channel messages (if Billy will be in channels)
- `channels:read` — View basic channel info
- `chat:write` — Send messages
- `files:write` — Upload files (.pptx presentations)
- `im:history` — Read DM messages
- `im:read` — View DMs
- `im:write` — Send DMs
- `reactions:write` — React with emoji (for acks)
- `users:read` — Look up user info

#### Enable Socket Mode (recommended for testing)

1. Go to **Socket Mode** in sidebar
2. Enable Socket Mode
3. Generate an **App-Level Token**:
   - Token Name: `billy-socket`
   - Scopes: `connections:write`
   - Copy the token (starts with `xapp-`)

#### Install to Workspace

1. Go to **Install App** in sidebar
2. Click **"Install to Workspace"**
3. Authorize the permissions
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

#### Enable Events (for mentions and messages)

1. Go to **Event Subscriptions**
2. Enable Events
3. Subscribe to bot events:
   - `app_mention` — When @Billy is mentioned
   - `message.im` — Direct messages to Billy

---

## Deployment Options

### Option A: Local Docker (Quickest for Testing)

Run Billy in a container on this server, separate from Anton.

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy

# 1. Create .env file with secrets
cat > .env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-api03-...  # Caio's key
SLACK_BOT_TOKEN=xoxb-...             # Billy's bot token from above
SLACK_APP_TOKEN=xapp-...             # Billy's app-level token
GEMINI_API_KEY=REDACTED_GEMINI_KEY_2  # For AI presentations
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=
MYSQL_DATABASE=db-maestro-prod
GCP_PROJECT=brandlovers-prod
EOF

# 2. Build Docker image
docker build -t billy-agent:local .

# 3. Run container (port 18790 to avoid conflict with Anton on 18789)
docker run -d \
  --name billy \
  --env-file .env \
  --network=host \
  -v /root/.openclaw/workspace/clawdbots/agents/billy/workspace:/workspace \
  -v /root/.config/gcloud:/root/.config/gcloud:ro \
  billy-agent:local

# 4. Check logs
docker logs -f billy

# 5. Stop Billy
docker stop billy && docker rm billy
```

**Notes:**
- Uses `--network=host` for MySQL Cloud SQL Proxy access
- Binds to port 18790 (Anton uses 18789)
- Shares GCP credentials for BigQuery/Cloud SQL

### Option B: GKE Dev Deployment (Production-Like)

Deploy to `clawdbots-dev` namespace for persistent testing.

```bash
cd /root/.openclaw/workspace/clawdbots

# 1. Set up GCP service account (one-time)
bash agents/billy/k8s/setup-gcp-sa.sh

# 2. Create MySQL read-only user for Billy (one-time)
mysql -e "
CREATE USER 'billy_readonly'@'%' IDENTIFIED BY '<generate-password>';
GRANT SELECT ON \`db-maestro-prod\`.* TO 'billy_readonly'@'%';
FLUSH PRIVILEGES;
"

# 3. Create K8s secrets
kubectl create secret generic clawdbot-billy-secrets \
  --namespace=clawdbots-dev \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
  --from-literal=SLACK_BOT_TOKEN=xoxb-... \
  --from-literal=SLACK_APP_TOKEN=xapp-... \
  --from-literal=GEMINI_API_KEY=AIzaSyD... \
  --from-literal=MYSQL_USER=billy_readonly \
  --from-literal=MYSQL_PASSWORD=<password>

# 4. Deploy using CLI
python3 cli/clawdbot.py deploy billy --env=dev

# 5. Check status
python3 cli/clawdbot.py status billy --env=dev
kubectl logs -f deployment/clawdbot-billy -n clawdbots-dev -c agent

# 6. Remove deployment
python3 cli/clawdbot.py destroy billy --env=dev
```

---

## Testing Billy

### 1. Invite Billy to Slack Channels

**For DM testing (recommended first):**
- Go to Slack → Click on Billy in the Apps section
- Send a message: "Oi Billy!"

**For channel testing:**
- Invite Billy to a test channel: `/invite @Billy`
- Recommended test channel: Create `#billy-testing`

### 2. Test Data Queries

```
# Basic moderation stats
"Quantos conteúdos foram moderados essa semana?"
"Qual a taxa de aprovação dos últimos 30 dias?"

# Campaign lookup
"Me mostra o status da campanha Summer Vibes"
"Quais campanhas estão ativas agora?"

# Campaign comparison
"Compara a performance da campanha X vs campanha Y"

# Creator analytics
"Quantos creators ativos temos?"
"Total de pagamentos do mês?"

# Weekly digest
"Gera o resumo semanal da plataforma"
```

### 3. Test PowerPoint Generation

```
"Faz uma apresentação da campanha [nome] pra reunião"
"Cria um report semanal em PowerPoint"
"Gera um brand review da [marca]"
```

Billy will query the data and upload a `.pptx` file to Slack.

### 4. Test Uncertainty/Escalation

```
"Qual o CPM das campanhas de TikTok?"  # Billy doesn't have this data
```

Billy should respond with:
- "Não tenho essa informação nos dados que acesso."
- Post to `#billy-questions` (need to create this channel first)

**Create #billy-questions channel:**
```
1. Create a new Slack channel: #billy-questions
2. Invite data team + engineering
3. Purpose: "Billy posts here when he needs help from humans"
```

### 5. Verify MySQL Access

Billy should be able to query:
- `proofread_medias` — Content moderation results
- `campaigns` — Campaign data
- `actions` — Creator submissions
- `creator_payment_history` — Payment data
- `brands`, `moments`, `ads`, `creator_groups`

Test with: `"Me lista as 5 campanhas com mais volume na última semana"`

### 6. Verify BigQuery Access (via Workload Identity)

Billy should access `brandlovers-prod.analytics.*` tables.

Test with: `"Tem algum dado de analytics no BigQuery?"`

---

## Configuration Files

### Billy's openclaw.json
```json
{
  "$schema": "https://openclaw.dev/schema/config.json",
  "version": "1.0",
  "agent": {
    "name": "billy",
    "description": "Non-tech team helper: data queries + presentation generation",
    "model": "anthropic/claude-sonnet-4-5"
  },
  "channels": {
    "slack": {
      "enabled": true,
      "allowedChannels": [],
      "allowedUsers": []
    }
  },
  "tools": [
    "bigquery",
    "mysql",
    "presentations"
  ],
  "workspace": "./workspace"
}
```

**Note:** `allowedChannels` and `allowedUsers` are empty = Billy responds everywhere. For production, restrict to specific channels/users.

---

## Monitoring

### Docker Logs
```bash
docker logs -f billy
```

### K8s Logs
```bash
kubectl logs -f deployment/clawdbot-billy -n clawdbots-dev -c agent
kubectl logs -f deployment/clawdbot-billy -n clawdbots-dev -c cloudsql-proxy
```

### Check Pod Status
```bash
kubectl get pods -n clawdbots-dev -l app=clawdbot-billy
kubectl describe pod <pod-name> -n clawdbots-dev
```

---

## Troubleshooting

### Billy Not Responding in Slack

**Check:**
1. Bot token is valid: `curl -H "Authorization: Bearer $SLACK_BOT_TOKEN" https://slack.com/api/auth.test`
2. Socket mode is connected (check logs for "Connected to Slack")
3. Billy is invited to the channel (for channel messages)
4. Event subscriptions are enabled (for mentions)

### MySQL Connection Failed

**Check:**
1. Cloud SQL Proxy is running (K8s sidecar or local `cloud-sql-proxy`)
2. Billy's DB user exists and has SELECT grants
3. `MYSQL_HOST=localhost` and `MYSQL_PORT=3306` in env

### BigQuery Access Denied

**Check:**
1. Workload Identity is bound: `gcloud iam service-accounts get-iam-policy billy@brandlovers-prod.iam.gserviceaccount.com`
2. SA has `bigquery.dataViewer` and `bigquery.jobUser` roles
3. K8s SA annotation points to GCP SA

### PowerPoint Generation Errors

**Check:**
1. `python-pptx` installed: `pip list | grep python-pptx`
2. Gemini API key is valid (optional, Billy works without it)
3. Output directory is writable

---

## Next Steps After Testing

1. **Restrict Access** — Update `allowedUsers` in openclaw.json to specific team members
2. **Create #billy-questions** — For human escalation
3. **Schedule Weekly Digest** — Cron job to auto-post every Monday 9am
4. **Document Common Questions** — Build a FAQ in Billy's memory
5. **Monitor Usage** — Track query patterns, most-asked questions
6. **Production Deployment** — Move to `clawdbots-prod` namespace when stable

---

## How Caio Interacts with Billy

### DM with Billy (Private Questions)
```
Caio: "Quantos creators foram pagos no último mês?"
Billy: [queries DB] "128 creators receberam pagamento em fevereiro, totalizando R$ 1,2M..."
```

### In #marketing or #sales (Team Questions)
```
Caio: "@Billy qual a taxa de aprovação da campanha X?"
Billy: [queries DB] "Campanha X teve 1.245 conteúdos com 82,3% de aprovação..."
```

### Request a Presentation
```
Caio: "@Billy faz um report da marca Renault pra reunião"
Billy: [queries campaigns/moderation data] [generates PPTX] [uploads file]
```

### Billy Doesn't Know
```
Caio: "Qual o ROI das campanhas de Instagram?"
Billy: "Não tenho dados de ROI nas minhas fontes. Vou perguntar pro time." 
[Posts to #billy-questions with anonymized question]
```

**Billy's personality:**
- Warm, approachable, never condescending
- pt-BR by default
- Explains "so what?" not just numbers
- Admits uncertainty and escalates instead of guessing
- Strong privacy rules for DM conversations

---

**Status:** Billy is ready to deploy. Just need Slack bot token from Caio, then run Option A (Docker) for immediate testing.
