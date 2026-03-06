# ClawdBots Architecture Guide

## Overview

ClawdBots is a multi-agent platform for deploying specialized OpenClaw-based AI agents on GKE. Each agent is an isolated container with its own identity, tools, access controls, and workspace.

```
┌─────────────────────────────────────────────────────────┐
│                    Slack / Channels                       │
│   #data-team   #tech-gua-ma   #leadership   DMs          │
└──────┬──────────────┬──────────────┬────────────────────┘
       │              │              │
       ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Neuron  │  │  Billy   │  │ Guardian │   ← OpenClaw agents
│  (Data)  │  │  (CS)    │  │ (Mod)    │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │              │              │
     ▼              ▼              ▼
┌─────────────────────────────────────────┐
│          GKE — clawdbots-dev/prod        │
│                                          │
│  Each agent pod:                         │
│  ┌─────────────┬──────────────────────┐  │
│  │ OpenClaw    │ Cloud SQL Proxy      │  │
│  │ Container   │ Sidecar (if needed)  │  │
│  └──────┬──────┴───────┬──────────────┘  │
│         │              │                 │
└─────────┼──────────────┼─────────────────┘
          │              │
          ▼              ▼
    ┌──────────┐  ┌──────────────┐
    │ BigQuery │  │ Cloud SQL    │
    │          │  │ (MySQL)      │
    └──────────┘  └──────────────┘
```

## Agent Anatomy

Every agent has:

```
agents/<name>/
├── openclaw.json          # Agent config (model, channels, tools)
├── Dockerfile             # Container image
├── requirements.txt       # Python deps
├── workspace/
│   ├── SOUL.md            # Agent personality & mission
│   ├── TOOLS.md           # Available tools, schemas, connection details
│   ├── AGENTS.md          # Session bootstrap instructions
│   ├── skills/            # Specialized skill files
│   └── memory/            # Persistent memory across sessions
└── k8s/
    ├── deployment.yaml    # K8s Deployment (with sidecars)
    ├── serviceaccount.yaml # K8s SA with Workload Identity
    ├── networkpolicy.yaml # Egress rules
    └── setup-gcp-sa.sh   # One-time GCP SA creation
```

## Security Model

### Access Control Layers

1. **Slack ACL** — `openclaw.json` defines allowed channels and users
2. **K8s NetworkPolicy** — Restricts egress to only needed services
3. **GCP IAM** — Least-privilege roles per agent via Workload Identity
4. **MySQL Users** — Read-only DB users per agent
5. **Secret Manager** — All secrets in Google Secret Manager, injected via K8s secrets

### Workload Identity Flow

```
K8s Service Account (clawdbot-neuron)
  ↓ annotated with
GCP Service Account (clawdbot-neuron@project.iam.gserviceaccount.com)
  ↓ has roles
BigQuery DataViewer + JobUser, CloudSQL Client
```

No service account keys are stored — Workload Identity handles auth automatically.

## Deployment Flow

1. Code change pushed to `agents/<name>/`
2. GitHub Actions detects the change
3. Docker image built and pushed to Artifact Registry
4. K8s manifests applied to target namespace
5. Deployment image updated, rollout monitored

## Cost Attribution

Each agent has labels:
- `platform: clawdbots`
- `agent: <name>`

Use these for GKE cost attribution in billing reports.

## Namespace Strategy

- `clawdbots-dev` — Testing, experimentation, initial rollout
- `clawdbots-prod` — Production-ready agents

Resource quotas enforce limits per namespace to prevent runaway costs.
