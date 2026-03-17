# GKE Deployment Runbook — Anton & Billy OpenClaw Gateways

> Status: **Ready for execution** | Last updated: 2026-03-10

## Overview

Deploy Anton (orchestrator) and Billy (data assistant) as always-on pods in `bl-cluster-prod` (us-east1, project `brandlovers-prod`), following the same ArgoCD + Kustomize + sm-k8s patterns used by guardian-agents-api, chat-agents, etc.

## Pre-flight Checklist

- [ ] GCP admin access to `brandlovers-prod`
- [ ] Write access to `brandlovers-team/cicd-k8s` repo
- [ ] Write access to `brandlovers-team/sm-k8s` repo (or whoever manages it)
- [ ] ArgoCD dashboard access
- [ ] `kubectl` configured for `bl-cluster-prod`
- [ ] OpenClaw Docker image tag verified (see Step 0)

---

## Step 0: Verify OpenClaw Docker Image

```bash
# Check if the image exists and what tags are available
gcloud container images list-tags gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw --limit=5
```

**Image source:** Custom Dockerfile in `replicants-anton` repo, built by `reusable-workflows-ci` and pushed to `gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw`. ArgoCD image-updater auto-deploys new builds.

---

## Step 1: Create GCP Service Accounts + IAM

### 1.1 Create Service Accounts

```bash
# Anton
gcloud iam service-accounts create anton-openclaw \
  --display-name="Anton OpenClaw Gateway" \
  --project=brandlovers-prod

# Billy
gcloud iam service-accounts create billy-openclaw \
  --display-name="Billy OpenClaw Gateway" \
  --project=brandlovers-prod
```

### 1.2 Grant IAM Roles

Both agents need the same roles:

```bash
for SA in anton-openclaw billy-openclaw; do
  for ROLE in \
    roles/bigquery.dataViewer \
    roles/bigquery.jobUser \
    roles/aiplatform.user \
    roles/logging.logWriter \
    roles/storage.objectViewer \
    roles/storage.objectCreator; do
    gcloud projects add-iam-policy-binding brandlovers-prod \
      --member="serviceAccount:${SA}@brandlovers-prod.iam.gserviceaccount.com" \
      --role="${ROLE}" \
      --quiet
  done
done
```

### 1.3 Workload Identity Binding

```bash
for SA in anton-openclaw billy-openclaw; do
  gcloud iam service-accounts add-iam-policy-binding \
    ${SA}@brandlovers-prod.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:brandlovers-prod.svc.id.goog[prod/${SA}]"
done
```

**Verify Workload Identity is enabled on the cluster:**
```bash
gcloud container clusters describe bl-cluster-prod \
  --zone=us-east1 --project=brandlovers-prod \
  --format="value(workloadIdentityConfig.workloadPool)"
# Expected: brandlovers-prod.svc.id.goog
```

If Workload Identity is NOT enabled, use the SA key fallback (see Appendix B).

---

## Step 2: Create Secrets in sm-k8s

### 2.1 Anton secrets file

Create `secrets-prod/anton-openclaw.properties` in the `sm-k8s` repo:

```properties
# ── OpenClaw Core ──
OPENCLAW_GATEWAY_TOKEN="<generate-new-token>"

# ── LLM Provider ──
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"

# ── GCP (Vertex AI / BigQuery) ──
GOOGLE_CLOUD_PROJECT="brandlovers-prod"
GOOGLE_CLOUD_LOCATION="us-east1"

# ── Slack Channel Integration ──
SLACK_BOT_TOKEN="<anton-slack-bot-token>"
SLACK_APP_TOKEN="<anton-slack-app-token>"

# ── Integrations ──
GITHUB_TOKEN="$GITHUB_TOKEN"
LINEAR_API_KEY="$LINEAR_API_KEY"
GEMINI_API_KEY="<gemini-api-key>"

# ── Observability ──
LANGFUSE_SECRET_KEY="<anton-langfuse-secret>"
LANGFUSE_PUBLIC_KEY="<anton-langfuse-public>"
LANGFUSE_BASE_URL="https://us.cloud.langfuse.com"

# ── Database (for MCP tools) ──
DB_MAESTRO_HOST="$DB_MAESTRO_HOST"
DB_MAESTRO_NAME="$DB_MAESTRO_NAME"
DB_MAESTRO_PASSWORD="$DB_MAESTRO_PASSWORD"
DB_MAESTRO_PORT="$DB_MAESTRO_PORT"
DB_MAESTRO_USER="$DB_MAESTRO_USER"

# ── Notion ──
NOTION_API_KEY="<notion-api-key>"

# ── Metabase ──
METABASE_API_KEY="<metabase-api-key>"
```

### 2.2 Billy secrets file

Create `secrets-prod/billy-openclaw.properties` in the `sm-k8s` repo:

```properties
# ── OpenClaw Core ──
OPENCLAW_GATEWAY_TOKEN="<generate-new-token>"

# ── LLM Provider ──
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"

# ── GCP ──
GOOGLE_CLOUD_PROJECT="brandlovers-prod"
GOOGLE_CLOUD_LOCATION="us-east1"

# ── Slack Channel Integration ──
SLACK_BOT_TOKEN="<billy-slack-bot-token>"
SLACK_APP_TOKEN="<billy-slack-app-token>"

# ── Integrations ──
GEMINI_API_KEY="<gemini-api-key>"

# ── Database (for MCP tools) ──
DB_MAESTRO_HOST="$DB_MAESTRO_HOST"
DB_MAESTRO_NAME="$DB_MAESTRO_NAME"
DB_MAESTRO_PASSWORD="$DB_MAESTRO_PASSWORD"
DB_MAESTRO_PORT="$DB_MAESTRO_PORT"
DB_MAESTRO_USER="$DB_MAESTRO_USER"

# ── Metabase ──
METABASE_API_KEY="<metabase-api-key>"
```

### 2.3 Variable Source Map

Where to get each `<placeholder>` value:

| Variable | Source |
|----------|--------|
| `OPENCLAW_GATEWAY_TOKEN` | Generate new: `openssl rand -hex 32` |
| `ANTHROPIC_API_KEY` | Already in sm-k8s as GitHub env secret `$ANTHROPIC_API_KEY` |
| `SLACK_BOT_TOKEN` (Anton) | Slack App "Anton" → OAuth & Permissions → Bot User OAuth Token |
| `SLACK_APP_TOKEN` (Anton) | Slack App "Anton" → Basic Information → App-Level Tokens |
| `SLACK_BOT_TOKEN` (Billy) | Slack App "Billy" → same |
| `SLACK_APP_TOKEN` (Billy) | Slack App "Billy" → same |
| `GITHUB_TOKEN` | Already in sm-k8s as `$GITHUB_TOKEN` |
| `LINEAR_API_KEY` | Linear → Settings → API → Personal API Keys (Anton's) |
| `GEMINI_API_KEY` | Google AI Studio → API Keys |
| `LANGFUSE_*` | Langfuse → Settings → API Keys (Anton project) |
| `NOTION_API_KEY` | Notion → My Integrations → Anton integration |
| `METABASE_API_KEY` | Metabase → Admin → API Keys |
| `DB_MAESTRO_*` | Already in sm-k8s as GitHub env secrets |

---

## Step 3: Add Manifests to cicd-k8s

Copy the validated manifests from `infra/k8s/` into the `cicd-k8s` repo.

### 3.1 File structure to create

```
apps/prod/
├── anton-openclaw.yaml              ← ArgoCD Application CRD (from argocd-app.yaml)
├── anton-openclaw/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   └── serviceaccount.yaml
├── billy-openclaw.yaml              ← ArgoCD Application CRD
├── billy-openclaw/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   └── serviceaccount.yaml
```

### 3.2 Commands

```bash
cd /path/to/cicd-k8s

# Anton
mkdir -p apps/prod/anton-openclaw
cp <source>/infra/k8s/anton-openclaw/deployment.yaml apps/prod/anton-openclaw/
cp <source>/infra/k8s/anton-openclaw/service.yaml apps/prod/anton-openclaw/
cp <source>/infra/k8s/anton-openclaw/pvc.yaml apps/prod/anton-openclaw/
cp <source>/infra/k8s/anton-openclaw/serviceaccount.yaml apps/prod/anton-openclaw/
cp <source>/infra/k8s/anton-openclaw/kustomization.yaml apps/prod/anton-openclaw/
cp <source>/infra/k8s/anton-openclaw/argocd-app.yaml apps/prod/anton-openclaw.yaml

# Billy
mkdir -p apps/prod/billy-openclaw
cp <source>/infra/k8s/billy-openclaw/deployment.yaml apps/prod/billy-openclaw/
cp <source>/infra/k8s/billy-openclaw/service.yaml apps/prod/billy-openclaw/
cp <source>/infra/k8s/billy-openclaw/pvc.yaml apps/prod/billy-openclaw/
cp <source>/infra/k8s/billy-openclaw/serviceaccount.yaml apps/prod/billy-openclaw/
cp <source>/infra/k8s/billy-openclaw/kustomization.yaml apps/prod/billy-openclaw/
cp <source>/infra/k8s/billy-openclaw/argocd-app.yaml apps/prod/billy-openclaw.yaml
```

### 3.3 Validation before PR

```bash
cd apps/prod/anton-openclaw && kubectl kustomize . > /dev/null && echo "Anton OK"
cd ../billy-openclaw && kubectl kustomize . > /dev/null && echo "Billy OK"
```

---

## Step 4: Prepare OpenClaw Config for GKE

The `openclaw.json` needs adaptations for running in a container vs locally:

### 4.1 Key changes from local config

| Setting | Local (current) | GKE (needed) |
|---------|----------------|--------------|
| `gateway.bind` | `loopback` | `lan` (K8s service routing) |
| `gateway.mode` | `local` | `local` (unchanged) |
| `agents.defaults.workspace` | `${OPENCLAW_HOME:-$HOME}/.openclaw/workspace` | `/home/node/.openclaw/workspace` |
| All script paths | `${OPENCLAW_HOME:-$HOME}/.openclaw/...` | `/home/node/.openclaw/...` |
| `channels.whatsapp` | enabled | **disable** (no WhatsApp in GKE initially) |
| `channels.slack.botToken` | hardcoded | via env var `SLACK_BOT_TOKEN` |
| `channels.slack.appToken` | hardcoded | via env var `SLACK_APP_TOKEN` |

### 4.2 Scripts path migration

**20+ scripts have hardcoded `${OPENCLAW_HOME:-$HOME}/.openclaw/`**. Before deploying, refactor all scripts to use:

```bash
OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node/.openclaw}"
```

Scripts to update:
- `dispatcher.sh`
- `task-manager.sh`
- `kill-agent-tree.sh`
- `guardrails.sh`
- `review-hook.sh`
- (all scripts now use `${OPENCLAW_HOME}` — migration complete)

### 4.3 Launchd → In-Container Cron

Local Anton uses `launchd` for infra-maintenance (15min). In GKE, this needs to run as:
- **Option A:** OpenClaw native heartbeat (already configured, runs inside gateway)
- **Option B:** Sidecar container running cron
- **Option C:** CronJob K8s resources calling the pod via `kubectl exec`

**Recommendation:** Rely on OpenClaw native heartbeat. The heartbeat already runs every 5min and drives health checks, Slack reporting, timeouts, orphans, and callbacks. No supervisor script needed — HEARTBEAT.md is the brain.

---

## Step 5: State Migration

### 5.1 Export local state

```bash
# On Caio's Mac
tar -czf anton-state.tar.gz \
  -C ${OPENCLAW_HOME:-$HOME}/.openclaw \
  --exclude='*.log' \
  --exclude='node_modules' \
  --exclude='.git' \
  workspace/ \
  tasks/state.json \
  tasks/agent-logs/ \
  hooks/

gsutil cp anton-state.tar.gz gs://brandlovrs-artifacts/openclaw-migration/
```

### 5.2 Seed PVC via one-off Job

```bash
kubectl run anton-seed --rm -it --restart=Never \
  --image=google/cloud-sdk:slim \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "seed",
        "image": "google/cloud-sdk:slim",
        "command": ["sh", "-c",
          "gsutil cp gs://brandlovrs-artifacts/openclaw-migration/anton-state.tar.gz /tmp/ && tar -xzf /tmp/anton-state.tar.gz -C /state/ && chown -R 1000:1000 /state/"
        ],
        "volumeMounts": [{"name": "state", "mountPath": "/state"}]
      }],
      "volumes": [{"name": "state", "persistentVolumeClaim": {"claimName": "anton-openclaw-state"}}]
    }
  }' -n prod
```

### 5.3 Generate GKE-adapted openclaw.json

After seeding, exec into the pod and update paths:
```bash
POD=$(kubectl get pod -n prod -l app=anton-openclaw -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n prod $POD -- sh -c '
  cd /home/node/.openclaw
  # Update all path references
  sed -i "s|${OPENCLAW_HOME:-$HOME}/.openclaw|/home/node/.openclaw|g" workspace/scripts/*.sh
  sed -i "s|${OPENCLAW_HOME:-$HOME}/.openclaw|/home/node/.openclaw|g" openclaw.json
'
```

---

## Step 6: Deploy (Billy First)

### 6.1 Deploy Billy

1. Merge Billy manifests to cicd-k8s main
2. Merge Billy secrets to sm-k8s, trigger sync
3. Wait for ArgoCD to sync (check ArgoCD dashboard)
4. Verify:
   ```bash
   kubectl get pods -n prod -l app=billy-openclaw
   kubectl logs -n prod -l app=billy-openclaw --tail=50
   ```

### 6.2 Deploy Anton

Same process, but also:
1. Seed PVC with state (Step 5)
2. Verify heartbeat fires
3. Verify Slack connection
4. Run parallel with local Anton for 48h

---

## Step 7: Post-Deploy Validation

```bash
# Pod running?
kubectl get pods -n prod -l app=anton-openclaw

# Health checks passing?
kubectl exec -n prod -l app=anton-openclaw -- curl -s http://localhost:18789/healthz

# Slack connected?
kubectl logs -n prod -l app=anton-openclaw --tail=100 | grep -i slack

# Heartbeat firing?
kubectl logs -n prod -l app=anton-openclaw --tail=100 | grep -i heartbeat
```

---

## Open Questions / Blockers

### RESOLVED: Docker Image
Custom Dockerfile at repo root. Installs `openclaw@2026.3.8` + system tools. Sub-agents spawn via `openclaw agent --agent <role>` natively.

### RESOLVED: Slack Tokens
OpenClaw reads Slack tokens from env vars (`SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`). K8s Secret `anton-openclaw` provides them.

---

## Appendix A: Custom Dockerfile (if needed)

See `Dockerfile` at repo root for the actual image definition.

USER node
WORKDIR /home/node

EXPOSE 18789

ENTRYPOINT ["openclaw"]
CMD ["gateway", "--port", "18789", "--bind", "lan"]
```

Build & push:
```bash
docker build -t gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw:latest .
docker push gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw:latest
```

If using custom image, update deployment.yaml + kustomization.yaml to reference `gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw` instead of `ghcr.io/openclaw/openclaw`, and update ArgoCD image updater annotations to use `newest-build` strategy (matching existing Go services).

## Appendix B: SA Key Fallback (if no Workload Identity)

If Workload Identity is not enabled on `bl-cluster-prod`:

1. Create SA key:
```bash
gcloud iam service-accounts keys create anton-sa-key.json \
  --iam-account=anton-openclaw@brandlovers-prod.iam.gserviceaccount.com
```

2. Base64 encode and add to sm-k8s:
```bash
# In anton-openclaw.properties
GOOGLE_ACCOUNT_CREDENTIALS="<base64-encoded-json>"
```

3. Mount in container (add to deployment.yaml env):
```yaml
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: "/tmp/gcp-sa.json"
```

And an init script to decode `GOOGLE_ACCOUNT_CREDENTIALS` to `/tmp/gcp-sa.json` at startup.

This matches the pattern used by `chat-agents` (`GOOGLE_ACCOUNT_CREDENTIALS` env var).

## Appendix C: Execution Order Summary

```
Phase 0 — Prep
  [0.1] Verify OpenClaw Docker image exists (BLOCKER)
  [0.2] Create GCP SAs + IAM roles
  [0.3] Create Workload Identity bindings (or generate SA keys)
  [0.4] Export local state from Mac

Phase 1 — Billy (low risk)
  [1.1] Create billy-openclaw.properties in sm-k8s
  [1.2] Create Billy manifests in cicd-k8s
  [1.3] Deploy, seed PVC, validate

Phase 2 — Anton (higher risk)
  [2.1] Refactor scripts to use $OPENCLAW_HOME
  [2.2] Create anton-openclaw.properties in sm-k8s
  [2.3] Create Anton manifests in cicd-k8s
  [2.4] Deploy, seed PVC with full state
  [2.5] Validate: health, Slack, heartbeat, sub-agents
  [2.6] Run parallel 48h, then cut over

Phase 3 — Harden
  [3.1] PVC backup schedule (VolumeSnapshot)
  [3.2] Datadog monitors
  [3.3] NetworkPolicy
  [3.4] Config deployment CI/CD
  [3.5] Decommission local instances
```
