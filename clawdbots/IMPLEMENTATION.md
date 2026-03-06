# ClawdBots Implementation Report

**Date:** 2026-03-05
**Status:** ✅ Platform scaffolded and ready for deployment

---

## What Was Built

### 1. Agent Creator CLI (`cli/clawdbot.py`)

A Python CLI that scaffolds complete agent structures:

```bash
# Create a new agent
python3 cli/clawdbot.py create <name> "<description>" --tools=<list> [--model=<model>] [--namespace=<ns>]

# List all agents
python3 cli/clawdbot.py list

# Deploy to GKE
python3 cli/clawdbot.py deploy <name> --env=dev|prod

# Check status
python3 cli/clawdbot.py status <name> --env=dev|prod

# Remove from GKE
python3 cli/clawdbot.py destroy <name> --env=dev|prod
```

**What `create` generates:**
- `openclaw.json` — Agent config (model, channels, tools, ACL)
- `Dockerfile` — Container image based on OpenClaw
- `requirements.txt` — Python dependencies
- `workspace/SOUL.md` — Agent personality & mission
- `workspace/TOOLS.md` — Available tools & schemas
- `workspace/AGENTS.md` — Session bootstrap
- `k8s/deployment.yaml` — K8s Deployment
- `k8s/serviceaccount.yaml` — K8s SA with Workload Identity annotation
- `k8s/networkpolicy.yaml` — Egress restrictions
- `k8s/setup-gcp-sa.sh` — One-time GCP SA creation script

### 2. Neuron Agent (Data Intelligence)

First production agent — fully configured at `agents/neuron/`:

**Capabilities:**
- Queries MySQL (db-maestro-prod) via Cloud SQL Proxy sidecar
- Queries BigQuery (brandlovers-prod) via Workload Identity
- SQL generation with full schema reference
- Read-only access enforced at IAM, DB, and prompt level

**Workspace includes:**
- Detailed SOUL.md with personality, safety rules, and cost awareness
- TOOLS.md with complete table schemas, join patterns, and example queries
- Skills for BigQuery and MySQL with query templates
- Slack ACL: data team + leadership only

**K8s deployment features:**
- Cloud SQL Auth Proxy sidecar (v2.8.2) for MySQL connectivity
- Workload Identity (no service account keys)
- NetworkPolicy: DNS + HTTPS + MySQL egress only
- Resource limits: 500m-1000m CPU, 512Mi-1Gi memory

**GCP IAM roles (least privilege):**
- `bigquery.dataViewer` — read-only BQ access
- `bigquery.jobUser` — execute queries
- `cloudsql.client` — proxy connection
- `iam.workloadIdentityUser` — GKE binding

### 3. Infrastructure as Code

**Terraform (`infrastructure/terraform/`):**
- `main.tf` — Namespaces, resource quotas, network policies, Artifact Registry, Secret Manager
- `agents.tf` — Modular agent SA creation (add new agents by adding to the map)
- `terraform.tfvars` — Environment config
- GCS backend for state management
- Resource quotas: dev (4 CPU/8Gi, 20 pods), prod (8 CPU/16Gi, 50 pods)

**GitHub Actions (`infrastructure/github-actions/`):**
- `deploy-agent.yml` — Auto-detects changed agents on push, builds/deploys to GKE
  - Manual trigger with agent name + environment selection
  - Matrix strategy for parallel multi-agent deploys
  - Rollout monitoring with 5-minute timeout
- `terraform.yml` — Plan on PR (with comment), apply on merge to main

### 4. Documentation (`docs/`)

- **architecture.md** — System overview, agent anatomy, security model, deployment flow
- **creating-an-agent.md** — Step-by-step guide with CLI commands and checklist
- **access-control.md** — 5-layer security model (Slack ACL → IAM → NetworkPolicy → DB users → SOUL.md)
- **monitoring.md** — Pod monitoring, resource tracking, cost attribution via labels and BQ

---

## How to Deploy Neuron

### Prerequisites
1. GCP auth configured (`gcloud auth login` or service account)
2. `kubectl` configured for bl-cluster-prod
3. Terraform state bucket exists

### Steps

```bash
cd /root/.openclaw/workspace/clawdbots

# 1. Apply infrastructure (creates namespaces, Artifact Registry, SA)
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# 2. Create GCP service account (if not using Terraform)
bash agents/neuron/k8s/setup-gcp-sa.sh

# 3. Create MySQL read-only user
mysql -e "
CREATE USER 'neuron_readonly'@'%' IDENTIFIED BY '<password>';
GRANT SELECT ON \`db-maestro-prod\`.proofread_medias TO 'neuron_readonly'@'%';
GRANT SELECT ON \`db-maestro-prod\`.actions TO 'neuron_readonly'@'%';
GRANT SELECT ON \`db-maestro-prod\`.campaigns TO 'neuron_readonly'@'%';
GRANT SELECT ON \`db-maestro-prod\`.media_content TO 'neuron_readonly'@'%';
GRANT SELECT ON \`db-maestro-prod\`.proofread_guidelines TO 'neuron_readonly'@'%';
FLUSH PRIVILEGES;
"

# 4. Create K8s secrets
kubectl create secret generic clawdbot-neuron-secrets \
  --namespace=clawdbots-dev \
  --from-literal=ANTHROPIC_API_KEY=sk-... \
  --from-literal=SLACK_TOKEN=xoxb-... \
  --from-literal=MYSQL_USER=neuron_readonly \
  --from-literal=MYSQL_PASSWORD=...

# 5. Deploy
python3 cli/clawdbot.py deploy neuron --env=dev

# 6. Verify
python3 cli/clawdbot.py status neuron --env=dev
kubectl logs -f deployment/clawdbot-neuron -n clawdbots-dev -c agent
```

---

## Next Steps

### Immediate (before deploying to prod)
1. **Configure GCP auth** on the build machine — needed for `gcloud`, `terraform`, `kubectl`
2. **Create the Artifact Registry** — `terraform apply` or manual
3. **Create clawdbots-dev namespace** — `terraform apply` or `kubectl create ns clawdbots-dev`
4. **Create a Slack bot token** for Neuron (separate from CaioBot's user token)
5. **Set up MySQL read-only user** for Neuron
6. **Test Neuron end-to-end** in dev namespace

### Billy Agent (Customer Success)
```bash
python3 cli/clawdbot.py create billy \
  "Customer success agent — answers questions about creator performance, campaign metrics, and account health" \
  --tools=mysql,bigquery,web_search
```
Then customize SOUL.md for CS tone, TOOLS.md with relevant schemas, and add to `agents.tf`.

### Other Planned Agents
- **Guardian** (already exists separately — could migrate into platform for unified management)
- **Ops** — Infrastructure monitoring, incident response
- **Analytics** — Automated report generation, anomaly detection

### Platform Improvements
- [ ] Centralized logging (Cloud Logging + structured format)
- [ ] Alerting on pod crashes and resource spikes
- [ ] Agent health dashboard (Grafana or similar)
- [ ] Automated secret rotation
- [ ] Inter-agent communication (message bus)
- [ ] Cost dashboard per agent (BigQuery + LLM API)

---

## Security Considerations

1. **No credentials in code** — All secrets via K8s secrets / Secret Manager
2. **Workload Identity** — No service account key files, ever
3. **Least privilege IAM** — Each agent gets only the roles it needs
4. **Network isolation** — Egress-only policies per agent
5. **Read-only DB access** — Table-level MySQL grants
6. **Slack ACL** — Channel + user allowlists in openclaw.json
7. **SOUL.md safety rules** — Defense in depth at the prompt level
8. **Resource quotas** — Prevent runaway pod creation
9. **Separate API keys** — Each agent should have its own Anthropic key for cost tracking
10. **Audit trail** — K8s events + GCP audit logs + Langfuse traces

---

## Directory Structure

```
clawdbots/
├── IMPLEMENTATION.md          ← This file
├── cli/
│   ├── __init__.py
│   ├── clawdbot.py            ← Agent Creator CLI
│   └── setup.py
├── agents/
│   └── neuron/                ← First production agent
│       ├── openclaw.json
│       ├── Dockerfile
│       ├── requirements.txt
│       ├── workspace/
│       │   ├── SOUL.md
│       │   ├── TOOLS.md
│       │   ├── AGENTS.md
│       │   └── skills/
│       │       ├── bigquery/SKILL.md
│       │       └── mysql/SKILL.md
│       └── k8s/
│           ├── deployment.yaml
│           ├── serviceaccount.yaml
│           ├── networkpolicy.yaml
│           └── setup-gcp-sa.sh
├── infrastructure/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── agents.tf
│   │   └── terraform.tfvars
│   └── github-actions/
│       ├── deploy-agent.yml
│       └── terraform.yml
└── docs/
    ├── architecture.md
    ├── creating-an-agent.md
    ├── access-control.md
    └── monitoring.md
```
