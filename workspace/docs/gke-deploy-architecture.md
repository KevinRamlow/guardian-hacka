# GKE Deployment Architecture — Anton & Billy OpenClaw Gateways

> **ADR-001** | Status: **Proposed** | Author: Architect Agent | 2026-03-09

## Context

Anton (orchestrator) and Billy (ops assistant) currently run as local OpenClaw gateway processes on Caio's MacBook. This creates a single point of failure, limits uptime, and blocks team-wide access. We need to deploy them as always-on pods inside the Brandlovrs GKE cluster (`bl-cluster-prod`, `us-east1`, project `brandlovers-prod`) following the same patterns used by `guardian-agents-api`, `chat-agents-api`, and `chat-agents`.

### Decision

Deploy each OpenClaw gateway as an independent Kubernetes Deployment with persistent state via GCE Persistent Disks, managed through the existing ArgoCD + Kustomize + sm-k8s pipeline. Use the official `ghcr.io/openclaw/openclaw` Docker image as the base.

---

## 1. Pod Architecture

### 1.1 High-Level Topology

```
┌─────────────────────────────────────────────────────────────────┐
│  GKE Cluster: bl-cluster-prod (us-east1)  │  Namespace: prod   │
│                                                                 │
│  ┌──────────────────────┐   ┌──────────────────────┐           │
│  │  anton-openclaw       │   │  billy-openclaw       │           │
│  │  (Deployment, 1 rep)  │   │  (Deployment, 1 rep)  │           │
│  │                       │   │                       │           │
│  │  ghcr.io/openclaw/    │   │  ghcr.io/openclaw/    │           │
│  │  openclaw:2026.x      │   │  openclaw:2026.x      │           │
│  │                       │   │                       │           │
│  │  Port 18789 (gateway) │   │  Port 18789 (gateway) │           │
│  │                       │   │                       │           │
│  │  PVC: anton-state     │   │  PVC: billy-state     │           │
│  │  → /home/node/.openclaw│   │  → /home/node/.openclaw│           │
│  └──────────┬────────────┘   └──────────┬────────────┘           │
│             │                           │                        │
│  ┌──────────┴────────────┐   ┌──────────┴────────────┐           │
│  │  Service: ClusterIP   │   │  Service: ClusterIP   │           │
│  │  anton-openclaw:18789 │   │  billy-openclaw:18789 │           │
│  └──────────┬────────────┘   └──────────┴────────────┘           │
│             │                           │                        │
│  ┌──────────┴───────────────────────────┴────────────┐           │
│  │              Ingress (nginx)                       │           │
│  │  /anton-openclaw → anton-openclaw:18789            │           │
│  │  /billy-openclaw → billy-openclaw:18789            │           │
│  └───────────────────────────────────────────────────┘           │
│                                                                 │
│  Shared infra (existing):                                       │
│  • Redis (Memorystore)  • Cloud SQL  • RabbitMQ (in-cluster)    │
│  • Datadog Agent (DaemonSet)                                    │
└─────────────────────────────────────────────────────────────────┘

External connections (outbound from pods):
  → Anthropic API (Claude models)
  → OpenAI API (optional fallback)
  → Google Vertex AI (Gemini models)
  → BigQuery (analytics queries)
  → Cloud Logging (structured logs)
  → GCS (artifact storage)
  → Slack API (channel integration)
  → Telegram API (channel integration)
  → Discord API (channel integration)
  → GitHub API (gh CLI, issues, PRs)
  → Linear API (task management)
  → Langfuse (tracing)
  → Brave Search API
```

### 1.2 Why 1 Replica per Agent

OpenClaw gateways are **stateful singletons**: each owns a WhatsApp Web session, maintains WebSocket channel connections, and writes to local session state files. Running multiple replicas of the same gateway would cause session conflicts. This matches the `chat-agents` pattern (`replicas: 1`).

### 1.3 Container Spec

| Property | Value |
|----------|-------|
| **Base image** | `ghcr.io/openclaw/openclaw:2026.x` (pin to release tag) |
| **Runtime** | Node.js 22 (Bookworm) |
| **Gateway port** | 18789 |
| **User** | `node` (uid 1000) |
| **Bind mode** | `lan` (required for K8s service routing) |
| **Health: liveness** | `GET /healthz` port 18789 |
| **Health: readiness** | `GET /readyz` port 18789 |
| **State dir** | `/home/node/.openclaw` (PVC mount) |
| **Workspace dir** | `/home/node/.openclaw/workspace` (inside PVC) |

### 1.4 Resource Requests & Limits

OpenClaw is CPU-light (mostly I/O-bound LLM API calls) but needs memory for session state and potential sub-agent spawns:

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 250m | 1000m |
| Memory | 512Mi | 2Gi |
| Ephemeral storage | 1Gi | 5Gi |

### 1.5 Persistent Storage

Each agent needs a PVC for `~/.openclaw/` which stores:
- `openclaw.json` (config)
- `agents/` (session state, transcripts)
- `workspace/` (agent workspace files, skills, memory)
- `tasks/state.json` (task state)
- `cron/` (cron job state and run history)
- `logs/` (rolling file logs)

| PVC | Size | StorageClass | Access Mode |
|-----|------|--------------|-------------|
| `anton-openclaw-state` | 10Gi | `standard-rwo` (GCE PD) | ReadWriteOnce |
| `billy-openclaw-state` | 10Gi | `standard-rwo` (GCE PD) | ReadWriteOnce |

> **Why PVC over ConfigMap/emptyDir:** Session state, memory files, and cron history must survive pod restarts. ConfigMaps are size-limited (1MB). EmptyDir is ephemeral. GCE PD provides durable block storage with the `standard-rwo` class already available in GKE.

### 1.6 Networking

- **Ingress**: NGINX (`ingressClassName: nginx`), same pattern as `guardian-agents-api`
- **Hosts**: `api-creatorads.brandlovers.ai` and `api-crtrads.brandlovrs.com`
- **Paths**: `/anton-openclaw` and `/billy-openclaw` (Prefix match)
- **Internal only option**: If external HTTP access is not needed (agents connect via Slack/Telegram/Discord channels, not HTTP API), skip the Ingress and use ClusterIP-only Services. The channels connect outbound — no inbound HTTP is required unless using the OpenAI-compatible API or webhooks.

**Recommendation**: Start without Ingress. Add it later only if webhook receivers or the HTTP API are needed.

---

## 2. Kubernetes Manifests Plan

Following the exact conventions from `cicd-k8s/apps/prod/`:

### 2.1 File Structure (in `cicd-k8s`)

```
apps/prod/
├── anton-openclaw.yaml              # ArgoCD Application CRD
├── anton-openclaw/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   └── ingress.yaml                 # (optional, see §1.6)
├── billy-openclaw.yaml              # ArgoCD Application CRD
├── billy-openclaw/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   └── ingress.yaml                 # (optional)
```

### 2.2 ArgoCD Application CRD — `anton-openclaw.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: anton-openclaw
  namespace: argocd
  annotations:
    # Image updater watches for new tags on this image
    argocd-image-updater.argoproj.io/image-list: >-
      anton-openclaw=ghcr.io/openclaw/openclaw
    argocd-image-updater.argoproj.io/update-strategy: semver
    argocd-image-updater.argoproj.io/anton-openclaw.update-strategy: semver
    argocd-image-updater.argoproj.io/anton-openclaw.allow-tags: "regexp:^2026\\."
spec:
  project: default
  source:
    repoURL: git@github.com:brandlovers-team/cicd-k8s.git
    targetRevision: main
    path: apps/prod/anton-openclaw
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

> **Note**: Unlike the Go services which use `gcr.io/brandlovers-prod/` and `newest-build` strategy, OpenClaw uses `ghcr.io/openclaw/openclaw` (upstream public image) with `semver` strategy filtered to `2026.*` tags. No custom Docker build needed initially.

### 2.3 Deployment — `anton-openclaw/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anton-openclaw
  labels:
    app: anton-openclaw
spec:
  replicas: 1
  revisionHistoryLimit: 1
  strategy:
    type: Recreate  # Required: PVC RWO can't attach to two pods
  selector:
    matchLabels:
      app: anton-openclaw
  template:
    metadata:
      labels:
        app: anton-openclaw
        tags.datadoghq.com/env: "prod"
        tags.datadoghq.com/service: "anton-openclaw"
        tags.datadoghq.com/version: "latest"
    spec:
      terminationGracePeriodSeconds: 30
      securityContext:
        fsGroup: 1000  # node user group — ensures PVC writes work
      containers:
        - name: anton-openclaw
          image: ghcr.io/openclaw/openclaw:2026.3.1
          args:
            - "gateway"
            - "--port"
            - "18789"
            - "--bind"
            - "lan"
            - "--allow-unconfigured"
          ports:
            - name: gateway
              containerPort: 18789
              protocol: TCP
          env:
            - name: NODE_ENV
              value: "production"
            - name: DD_ENV
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['tags.datadoghq.com/env']
            - name: DD_SERVICE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['tags.datadoghq.com/service']
            - name: DD_VERSION
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['tags.datadoghq.com/version']
          envFrom:
            - secretRef:
                name: anton-openclaw
          volumeMounts:
            - name: openclaw-state
              mountPath: /home/node/.openclaw
          readinessProbe:
            httpGet:
              path: /readyz
              port: 18789
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: 18789
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 3
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 2Gi
      volumes:
        - name: openclaw-state
          persistentVolumeClaim:
            claimName: anton-openclaw-state
```

> **`strategy: Recreate`** is critical. With `RollingUpdate` (default), the new pod would try to mount the PVC while the old pod still holds it, causing a deadlock. `Recreate` terminates old → starts new.

### 2.4 PVC — `anton-openclaw/pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: anton-openclaw-state
  labels:
    app: anton-openclaw
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-rwo
  resources:
    requests:
      storage: 10Gi
```

### 2.5 Service — `anton-openclaw/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: anton-openclaw
  labels:
    app: anton-openclaw
spec:
  type: ClusterIP
  selector:
    app: anton-openclaw
  ports:
    - port: 18789
      targetPort: 18789
      protocol: TCP
```

### 2.6 Kustomization — `anton-openclaw/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - pvc.yaml
  # - ingress.yaml  # uncomment when HTTP API/webhooks needed
images:
  - name: ghcr.io/openclaw/openclaw
```

### 2.7 Billy

Billy manifests are identical in structure. Replace every occurrence of `anton` with `billy`. Both agents share the same container image but have independent config, secrets, and state.

---

## 3. Secrets Plan

### 3.1 Secrets Architecture

Following the `sm-k8s` pattern: `.properties` files in `secrets-prod/`, synced to K8s Secrets via the `sync-secrets.yaml` GitHub Actions workflow.

**Files to create in `sm-k8s`:**

```
secrets-prod/
├── anton-openclaw.properties
├── billy-openclaw.properties
```

### 3.2 Secret Variables — `anton-openclaw.properties`

```properties
# ── OpenClaw Core ──
OPENCLAW_GATEWAY_TOKEN="<generated-token>"
OPENCLAW_GATEWAY_PASSWORD="<generated-password>"

# ── LLM Providers ──
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
OPENAI_API_KEY="$OPENAI_API_KEY"

# ── GCP (Vertex AI / BigQuery / GCS / Cloud SQL) ──
GOOGLE_CLOUD_PROJECT="brandlovers-prod"
GOOGLE_CLOUD_LOCATION="us-east1"
GOOGLE_GENAI_USE_VERTEXAI="1"
# Workload Identity preferred (see §4); fallback:
# GOOGLE_APPLICATION_CREDENTIALS="/home/node/.openclaw/gcp-sa-key.json"

# ── Channel Tokens ──
SLACK_BOT_TOKEN="$ANTON_SLACK_BOT_TOKEN"
TELEGRAM_BOT_TOKEN="$ANTON_TELEGRAM_BOT_TOKEN"
DISCORD_BOT_TOKEN="$ANTON_DISCORD_BOT_TOKEN"

# ── Integrations ──
GITHUB_TOKEN="$GITHUB_TOKEN"
LINEAR_API_KEY="$LINEAR_API_KEY"
BRAVE_API_KEY="$BRAVE_API_KEY"

# ── Observability ──
LANGFUSE_SECRET_KEY="$ANTON_LANGFUSE_SECRET_KEY"
LANGFUSE_PUBLIC_KEY="$ANTON_LANGFUSE_PUBLIC_KEY"
LANGFUSE_BASE_URL="https://us.cloud.langfuse.com"

# ── Database (if needed for MCP/tools) ──
DB_MAESTRO_HOST="$DB_MAESTRO_HOST"
DB_MAESTRO_NAME="$DB_MAESTRO_NAME"
DB_MAESTRO_PASSWORD="$DB_MAESTRO_PASSWORD"
DB_MAESTRO_PORT="$DB_MAESTRO_PORT"
DB_MAESTRO_USER="$DB_MAESTRO_USER"

# ── Redis (if needed for shared state) ──
REDIS_HOST="$REDIS_HOST"
REDIS_PORT="$REDIS_PORT"
REDIS_PASSWORD="$REDIS_PASSWORD"
REDIS_USE_TLS="$REDIS_USE_TLS"
REDIS_USER="$REDIS_USER"
REDIS_CA_CERT="$REDIS_CA_CERT"
```

> Variables referencing `$VAR_NAME` are resolved from GitHub environment secrets at sync time by the `apply-secrets.sh` script, matching the existing sm-k8s convention.

### 3.3 Billy Differences

Billy's `.properties` file uses the same structure but with Billy-specific channel tokens and Langfuse keys. Both agents can share the same LLM API keys and database credentials.

### 3.4 Secret Rotation

- LLM API keys: rotate via sm-k8s commit → GitHub Actions auto-syncs → pod picks up on next restart
- Gateway tokens: stored in PVC config; rotate via `openclaw config set gateway.auth.token <new>` inside the pod

---

## 4. GCP Service Accounts & IAM

### 4.1 Workload Identity (Recommended)

GKE Workload Identity binds a Kubernetes ServiceAccount to a GCP IAM service account without key files. This is the preferred approach over mounting JSON key files.

**GCP Service Accounts to create:**

| GCP SA | Email | Purpose |
|--------|-------|---------|
| `anton-openclaw` | `anton-openclaw@brandlovers-prod.iam.gserviceaccount.com` | Anton's GCP identity |
| `billy-openclaw` | `billy-openclaw@brandlovers-prod.iam.gserviceaccount.com` | Billy's GCP identity |

### 4.2 IAM Roles

| Role | Scope | Reason |
|------|-------|--------|
| `roles/bigquery.dataViewer` | Project | Read BigQuery tables for analytics queries |
| `roles/bigquery.jobUser` | Project | Run BigQuery jobs (queries) |
| `roles/aiplatform.user` | Project | Invoke Vertex AI Gemini models |
| `roles/logging.logWriter` | Project | Write structured logs to Cloud Logging |
| `roles/storage.objectViewer` | Bucket(s) | Read artifacts from GCS |
| `roles/storage.objectCreator` | Bucket(s) | Write artifacts to GCS |
| `roles/cloudsql.client` | Project | Connect to Cloud SQL via proxy (if needed) |

### 4.3 Workload Identity Binding

```bash
# 1. Create GCP service account
gcloud iam service-accounts create anton-openclaw \
  --display-name="Anton OpenClaw Gateway" \
  --project=brandlovers-prod

# 2. Grant IAM roles
gcloud projects add-iam-policy-binding brandlovers-prod \
  --member="serviceAccount:anton-openclaw@brandlovers-prod.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"
# ... repeat for each role above

# 3. Bind K8s SA → GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  anton-openclaw@brandlovers-prod.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:brandlovers-prod.svc.id.goog[prod/anton-openclaw]"
```

### 4.4 Kubernetes ServiceAccount

Add to the manifests:

```yaml
# anton-openclaw/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: anton-openclaw
  namespace: prod
  annotations:
    iam.gke.io/gcp-service-account: anton-openclaw@brandlovers-prod.iam.gserviceaccount.com
```

Reference in Deployment spec:

```yaml
spec:
  template:
    spec:
      serviceAccountName: anton-openclaw
```

### 4.5 Fallback: Key File

If Workload Identity is not enabled on the cluster, mount a JSON key file via the sm-k8s secret as a base64-encoded `GOOGLE_APPLICATION_CREDENTIALS` env var (matching the `chat-agents` pattern with `GOOGLE_ACCOUNT_CREDENTIALS`). Less secure but compatible.

---

## 5. CI/CD Pipeline

### 5.1 Current Pattern (Go Services)

The existing pipeline uses `reusable-workflows-ci` → `build-ci.yml`:
1. PR opened → conventional commit check → Go tests → build Docker image → push to `gcr.io/brandlovrs-homolog/`
2. Merge to main → build Docker image → push to `gcr.io/brandlovers-prod/`
3. ArgoCD Image Updater detects new tag → updates kustomization → auto-sync

### 5.2 OpenClaw Pipeline (Different)

OpenClaw **does not need a custom Docker build** — it uses the upstream `ghcr.io/openclaw/openclaw` image. What changes between deploys is the **configuration** (openclaw.json, workspace files, skills), not the application binary.

**Two-track deployment:**

```
Track A — Image Updates (rare, upstream-driven):
  ghcr.io/openclaw/openclaw:2026.x.y
  → ArgoCD Image Updater (semver strategy, filtered to 2026.*)
  → Auto-sync updates Deployment image tag
  → Pod restart picks up new OpenClaw version

Track B — Config/Workspace Updates (frequent, team-driven):
  replicants-anton repo (this repo)
  → PR with config/workspace/skill changes
  → GitHub Actions: validate JSON, lint SOUL.md, etc.
  → Merge → package config as ConfigMap or sync to PVC
  → Pod restart or hot-reload via gateway API
```

### 5.3 Config Deployment Workflow

For Track B, create a GitHub Actions workflow in this repo (`replicants-anton`):

```yaml
# .github/workflows/deploy-config.yml
name: Deploy Agent Config

on:
  push:
    branches: [main]
    paths:
      - 'config/**'
      - 'workspace/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - uses: actions/checkout@v4

      - name: Validate openclaw.json
        run: node -e "JSON.parse(require('fs').readFileSync('config/openclaw.json'))"

      - name: Auth to GKE
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY_PROD }}

      - name: Get GKE credentials
        run: |
          gcloud container clusters get-credentials bl-cluster-prod \
            --zone us-east1 --project brandlovers-prod

      - name: Sync config to pod
        run: |
          POD=$(kubectl get pod -n prod -l app=anton-openclaw -o jsonpath='{.items[0].metadata.name}')
          kubectl cp config/openclaw.json prod/$POD:/home/node/.openclaw/openclaw.json
          # Trigger config reload (gateway watches file changes)
```

### 5.4 Alternative: Config as Init Container

A cleaner pattern for config seeding:

```yaml
initContainers:
  - name: config-seed
    image: gcr.io/brandlovers-prod/brandlovers-team/anton-openclaw-config:latest
    command: ["sh", "-c", "cp -rn /config/* /state/ || true"]
    volumeMounts:
      - name: openclaw-state
        mountPath: /state
```

This requires a separate small image containing just the config/workspace files. Build via a simple Dockerfile in this repo:

```dockerfile
FROM busybox:stable
COPY config/ /config/.openclaw/
COPY workspace/ /config/.openclaw/workspace/
```

> **Recommendation**: Start with manual `kubectl cp` for day-1. Graduate to init-container pattern once config changes become frequent.

---

## 6. Migration Plan

### 6.1 Phases

```
Phase 0: Prep (1-2 days)
  ├─ Create GCP service accounts + IAM bindings
  ├─ Create sm-k8s secret files
  ├─ Export current openclaw.json from local machines
  └─ Export workspace/memory/skills from local machines

Phase 1: Deploy Billy — Low Risk (1-2 days)
  ├─ Create K8s manifests in cicd-k8s (Billy only)
  ├─ Deploy to GKE (ArgoCD auto-sync)
  ├─ Seed PVC with config + workspace
  ├─ Configure channels (Slack bot token)
  ├─ Validate: health checks, channel connectivity, tool execution
  └─ Run parallel: local Billy + GKE Billy on separate channels

Phase 2: Deploy Anton — Higher Risk (2-3 days)
  ├─ Create K8s manifests in cicd-k8s (Anton)
  ├─ Deploy to GKE
  ├─ Seed PVC with config + workspace + memory
  ├─ Configure channels (Slack/Telegram/Discord tokens)
  ├─ Migrate cron jobs (export → import)
  ├─ Validate: heartbeat, cron execution, sub-agent spawns
  └─ Run parallel for 48h, then cut over

Phase 3: Harden (1 week)
  ├─ Enable Workload Identity (if not Phase 0)
  ├─ Set up PVC backup (VolumeSnapshot or GCS sync)
  ├─ Configure Datadog monitors + alerts
  ├─ Add NetworkPolicy (restrict egress to known endpoints)
  ├─ Load-test sub-agent spawning in container
  └─ Document runbook for on-call
```

### 6.2 State Migration

```bash
# On local machine — export state
tar -czf anton-state.tar.gz -C ~/.openclaw .

# Upload to GCS (staging area)
gsutil cp anton-state.tar.gz gs://brandlovrs-artifacts/openclaw-migration/

# In GKE — seed PVC via one-off Job
kubectl run anton-seed --rm -it --restart=Never \
  --image=google/cloud-sdk:slim \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "seed",
        "image": "google/cloud-sdk:slim",
        "command": ["sh", "-c",
          "gsutil cp gs://brandlovrs-artifacts/openclaw-migration/anton-state.tar.gz /tmp/ && tar -xzf /tmp/anton-state.tar.gz -C /state/"
        ],
        "volumeMounts": [{"name": "state", "mountPath": "/state"}]
      }],
      "volumes": [{"name": "state", "persistentVolumeClaim": {"claimName": "anton-openclaw-state"}}]
    }
  }' -n prod
```

### 6.3 Channel Cutover

Channels (Slack/Telegram/Discord) are configured with bot tokens. The same token can't be used by two gateway instances simultaneously for stateful channels (WhatsApp). For stateless webhook-based channels (Slack, Telegram), both can coexist briefly.

**Cutover order:**
1. Disconnect channel from local gateway (`openclaw channels remove`)
2. Add channel token to GKE pod secrets
3. Restart GKE pod
4. Verify channel connected (`openclaw channels status --probe`)

### 6.4 Rollback

- Keep local OpenClaw configs intact for 2 weeks post-migration
- PVC snapshots before any config change
- ArgoCD makes rollback trivial: revert commit in cicd-k8s

---

## 7. Implementation Backlog

### Epic: GKE Deployment — Anton & Billy OpenClaw Gateways

| # | Task | Priority | Estimate | Dependencies | Phase |
|---|------|----------|----------|--------------|-------|
| 1 | Create GCP SAs (`anton-openclaw`, `billy-openclaw`) + IAM role bindings | P0 | 2h | GCP admin access | 0 |
| 2 | Create Workload Identity bindings (or generate SA key files as fallback) | P0 | 1h | Task 1 | 0 |
| 3 | Export local Anton + Billy state (openclaw.json, workspace, memory, cron) | P0 | 1h | Local machine access | 0 |
| 4 | Create `billy-openclaw.properties` in sm-k8s repo | P0 | 1h | Secret values collected | 0 |
| 5 | Create `anton-openclaw.properties` in sm-k8s repo | P0 | 1h | Secret values collected | 0 |
| 6 | Create Billy K8s manifests in cicd-k8s (Deployment, Service, PVC, Kustomization, ArgoCD App) | P0 | 2h | — | 1 |
| 7 | Deploy Billy to GKE, verify ArgoCD sync | P0 | 1h | Tasks 4, 6 | 1 |
| 8 | Seed Billy PVC with exported config + workspace | P0 | 1h | Tasks 3, 7 | 1 |
| 9 | Configure Billy channels (Slack) and validate | P0 | 2h | Task 8 | 1 |
| 10 | Run Billy parallel validation (48h) | P1 | — | Task 9 | 1 |
| 11 | Create Anton K8s manifests in cicd-k8s | P0 | 2h | — | 2 |
| 12 | Deploy Anton to GKE, verify ArgoCD sync | P0 | 1h | Tasks 5, 11 | 2 |
| 13 | Seed Anton PVC with exported state (config, workspace, memory, skills, cron) | P0 | 2h | Tasks 3, 12 | 2 |
| 14 | Configure Anton channels + validate tool execution | P0 | 3h | Task 13 | 2 |
| 15 | Migrate cron jobs from local to GKE Anton | P1 | 2h | Task 14 | 2 |
| 16 | Run Anton parallel validation (48h) | P1 | — | Task 15 | 2 |
| 17 | Channel cutover: local → GKE for both agents | P0 | 2h | Tasks 10, 16 | 2 |
| 18 | Set up PVC VolumeSnapshot schedule (daily) | P1 | 2h | Tasks 7, 12 | 3 |
| 19 | Create Datadog monitors (pod restarts, health check failures, error rate) | P1 | 3h | Tasks 7, 12 | 3 |
| 20 | Add NetworkPolicy restricting egress | P2 | 2h | Tasks 7, 12 | 3 |
| 21 | Create config deployment workflow in replicants-anton | P2 | 3h | Task 17 | 3 |
| 22 | Write ops runbook (restart, logs, config update, rollback, PVC recovery) | P1 | 3h | Task 17 | 3 |
| 23 | Evaluate sub-agent sandbox support (Docker-in-Docker or sidecar) | P2 | 4h | Task 17 | 3 |
| 24 | Decommission local gateway instances | P1 | 1h | All Phase 3 | 3 |

**Total estimated effort:** ~38h across 3 phases over ~2 weeks.

---

## Appendix A: Alternatives Considered

### A.1 Cloud Run Instead of GKE

**Rejected.** Cloud Run is serverless and scales to zero, but OpenClaw gateways need:
- Always-on WebSocket connections (channel bots)
- Persistent local filesystem (session state)
- Long-running processes (cron, heartbeat)

Cloud Run's request-based lifecycle and ephemeral filesystem make it unsuitable.

### A.2 GCE VM Instead of GKE

**Rejected.** A dedicated VM would work but doesn't leverage the existing ArgoCD/Kustomize/sm-k8s pipeline. It would be a one-off snowflake requiring separate CI/CD, monitoring, and secret management.

### A.3 Custom Docker Image per Agent

**Deferred.** Building a custom image (baking in config, skills, extensions) adds CI complexity. The upstream `ghcr.io/openclaw/openclaw` image + PVC config mount is simpler for day-1. Graduate to custom images if config-as-code becomes a bottleneck.

### A.4 StatefulSet Instead of Deployment

**Considered but not needed.** StatefulSets provide stable network identity and ordered deployment — useful for databases. OpenClaw pods don't need stable hostnames or ordered scaling. A Deployment with `strategy: Recreate` and named PVCs achieves the same persistence guarantee with less complexity.

---

## Appendix B: Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| PVC data loss | High | Low | Daily VolumeSnapshot, GCS backup |
| OpenClaw upstream breaking change | Medium | Low | Pin to release tags, test in homolog first |
| Channel token leak via sm-k8s | High | Low | GitHub environment protection, branch rules |
| Pod OOM from sub-agent spawns | Medium | Medium | Memory limits, disable sandbox (no DinD) |
| ArgoCD Image Updater picks bad tag | Medium | Low | Semver filter + allow-tags regex |
| Datadog agent overhead | Low | Low | Already running as DaemonSet cluster-wide |

---

## Appendix C: Sub-Agent Sandboxing in GKE

OpenClaw's agent sandboxing uses Docker-in-Docker (mounting `docker.sock`). In GKE, this requires either:

1. **Privileged container** (security risk, not recommended in prod)
2. **Sidecar DinD container** (e.g., `docker:dind` with `--privileged`)
3. **Disable sandboxing** (agents run tools in the gateway container directly)

**Recommendation for day-1:** Disable sandboxing (`agents.defaults.sandbox.mode: "off"`). Tools run directly in the gateway container. This matches the current local setup and avoids DinD complexity. Revisit if security isolation becomes a requirement.
