#!/usr/bin/env python3
"""
ClawdBot CLI — Create and manage OpenClaw-based AI agents on GKE.

Usage:
    clawdbot create <name> <description> [--tools=<list>] [--namespace=<ns>] [--model=<model>]
    clawdbot list
    clawdbot deploy <name> [--env=<env>]
    clawdbot destroy <name> [--env=<env>]
    clawdbot status <name> [--env=<env>]
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path
from datetime import datetime

# Paths
CLAWDBOTS_ROOT = Path(__file__).resolve().parent.parent
AGENTS_DIR = CLAWDBOTS_ROOT / "agents"
TEMPLATES_DIR = CLAWDBOTS_ROOT / "templates"

# Defaults
DEFAULT_MODEL = "anthropic/claude-sonnet-4-5"
DEFAULT_NAMESPACE_DEV = "clawdbots-dev"
DEFAULT_NAMESPACE_PROD = "clawdbots-prod"
GCP_PROJECT = "brandlovers-prod"
GKE_CLUSTER = "bl-cluster-prod"
GKE_REGION = "us-east1"


def create_agent(args):
    """Scaffold a new agent with all required files."""
    name = args.name.lower().strip()
    description = args.description
    tools = [t.strip() for t in args.tools.split(",")] if args.tools else []
    model = args.model or DEFAULT_MODEL
    namespace = args.namespace or DEFAULT_NAMESPACE_DEV

    agent_dir = AGENTS_DIR / name
    if agent_dir.exists():
        print(f"❌ Agent '{name}' already exists at {agent_dir}")
        sys.exit(1)

    print(f"🤖 Creating agent: {name}")
    print(f"   Description: {description}")
    print(f"   Tools: {', '.join(tools) if tools else 'none'}")
    print(f"   Model: {model}")
    print(f"   Namespace: {namespace}")
    print()

    # Create directory structure
    dirs = [
        agent_dir,
        agent_dir / "workspace" / "skills",
        agent_dir / "workspace" / "memory",
        agent_dir / "k8s",
    ]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)

    # --- openclaw.json ---
    openclaw_config = {
        "$schema": "https://openclaw.dev/schema/config.json",
        "version": "1.0",
        "agent": {
            "name": name,
            "description": description,
            "model": model,
        },
        "channels": {
            "slack": {
                "enabled": True,
                "allowedChannels": [],
                "allowedUsers": [],
            }
        },
        "tools": tools,
        "workspace": "./workspace",
    }
    (agent_dir / "openclaw.json").write_text(json.dumps(openclaw_config, indent=2) + "\n")

    # --- Dockerfile ---
    dockerfile = textwrap.dedent(f"""\
        FROM ghcr.io/openclaw/openclaw:latest

        # Agent: {name}
        # {description}

        WORKDIR /agent

        # Copy agent configuration
        COPY openclaw.json ./
        COPY workspace/ ./workspace/

        # Install additional dependencies if needed
        COPY requirements.txt ./
        RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || true

        ENV AGENT_NAME={name}
        ENV OPENCLAW_CONFIG=/agent/openclaw.json

        CMD ["openclaw", "start", "--config", "/agent/openclaw.json"]
    """)
    (agent_dir / "Dockerfile").write_text(dockerfile)

    # --- requirements.txt (empty placeholder) ---
    (agent_dir / "requirements.txt").write_text("# Add agent-specific Python dependencies here\n")

    # --- workspace/SOUL.md ---
    soul = textwrap.dedent(f"""\
        # SOUL.md - {name.capitalize()} Agent

        You are **{name.capitalize()}**, a specialized AI agent at Brandlovrs.

        ## Mission
        {description}

        ## Communication
        - Default language: pt-BR for team interactions, English for technical work
        - Be concise and data-driven
        - Always cite sources (query results, links, traces)

        ## Boundaries
        - Never leak credentials or PII
        - Ask before destructive operations
        - Stay within your authorized scope
    """)
    (agent_dir / "workspace" / "SOUL.md").write_text(soul)

    # --- workspace/TOOLS.md ---
    tools_md = textwrap.dedent(f"""\
        # TOOLS.md - {name.capitalize()} Agent Tools

        ## Available Tools
        {chr(10).join(f'- {t}' for t in tools) if tools else '- (none configured yet)'}

        ## Connection Details
        <!-- Add database connections, API keys, etc. -->
    """)
    (agent_dir / "workspace" / "TOOLS.md").write_text(tools_md)

    # --- workspace/AGENTS.md ---
    agents_md = textwrap.dedent(f"""\
        # AGENTS.md - {name.capitalize()}

        ## Every Session
        1. Read SOUL.md
        2. Read TOOLS.md
        3. Check memory/ for recent context

        ## Your Scope
        {description}

        ## Safety
        - Don't exfiltrate data
        - Ask before destructive actions
        - Stay within authorized channels
    """)
    (agent_dir / "workspace" / "AGENTS.md").write_text(agents_md)

    # --- K8s Deployment ---
    sa_name = f"clawdbot-{name}"
    k8s_deployment = textwrap.dedent(f"""\
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: clawdbot-{name}
          namespace: {namespace}
          labels:
            app: clawdbot-{name}
            platform: clawdbots
            agent: "{name}"
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: clawdbot-{name}
          template:
            metadata:
              labels:
                app: clawdbot-{name}
                platform: clawdbots
            spec:
              serviceAccountName: {sa_name}
              containers:
                - name: agent
                  image: us-east1-docker.pkg.dev/{GCP_PROJECT}/clawdbots/clawdbot-{name}:latest
                  resources:
                    requests:
                      cpu: "500m"
                      memory: "512Mi"
                    limits:
                      cpu: "1000m"
                      memory: "1Gi"
                  envFrom:
                    - secretRef:
                        name: clawdbot-{name}-secrets
                  env:
                    - name: AGENT_NAME
                      value: "{name}"
                    - name: NODE_ENV
                      value: "production"
              restartPolicy: Always
    """)
    (agent_dir / "k8s" / "deployment.yaml").write_text(k8s_deployment)

    # --- K8s Service Account ---
    k8s_sa = textwrap.dedent(f"""\
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: {sa_name}
          namespace: {namespace}
          labels:
            platform: clawdbots
            agent: "{name}"
          annotations:
            iam.gke.io/gcp-service-account: {sa_name}@{GCP_PROJECT}.iam.gserviceaccount.com
    """)
    (agent_dir / "k8s" / "serviceaccount.yaml").write_text(k8s_sa)

    # --- K8s NetworkPolicy ---
    netpol = textwrap.dedent(f"""\
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        metadata:
          name: clawdbot-{name}-netpol
          namespace: {namespace}
        spec:
          podSelector:
            matchLabels:
              app: clawdbot-{name}
          policyTypes:
            - Egress
          egress:
            # DNS
            - to: []
              ports:
                - port: 53
                  protocol: UDP
                - port: 53
                  protocol: TCP
            # HTTPS (APIs, Slack, OpenClaw)
            - to: []
              ports:
                - port: 443
                  protocol: TCP
            # Cloud SQL Proxy (if sidecar)
            - to: []
              ports:
                - port: 3306
                  protocol: TCP
    """)
    (agent_dir / "k8s" / "networkpolicy.yaml").write_text(netpol)

    # --- GCP Service Account setup script ---
    gcp_setup = textwrap.dedent(f"""\
        #!/bin/bash
        # Create GCP service account for {name} agent
        # Run this once during initial setup

        set -euo pipefail

        PROJECT="{GCP_PROJECT}"
        SA_NAME="{sa_name}"
        SA_EMAIL="${{SA_NAME}}@${{PROJECT}}.iam.gserviceaccount.com"
        NAMESPACE="{namespace}"
        KSA_NAME="{sa_name}"

        echo "🔐 Creating GCP service account: $SA_NAME"

        # Create service account
        gcloud iam service-accounts create $SA_NAME \\
          --project=$PROJECT \\
          --display-name="ClawdBot {name.capitalize()} Agent" \\
          --description="{description}" || true

        # Bind Workload Identity
        gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \\
          --project=$PROJECT \\
          --role="roles/iam.workloadIdentityUser" \\
          --member="serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA_NAME]"

        echo "✅ Service account created and bound to K8s SA"
        echo ""
        echo "📌 Next: Add specific IAM roles based on agent needs:"
        echo "   gcloud projects add-iam-policy-binding $PROJECT \\\\"
        echo "     --member=serviceAccount:$SA_EMAIL \\\\"
        echo "     --role=roles/bigquery.dataViewer"
    """)
    gcp_script_path = agent_dir / "k8s" / "setup-gcp-sa.sh"
    gcp_script_path.write_text(gcp_setup)
    gcp_script_path.chmod(0o755)

    print(f"✅ Agent '{name}' created at {agent_dir}")
    print()
    print("📁 Structure:")
    for p in sorted(agent_dir.rglob("*")):
        if p.is_file():
            rel = p.relative_to(agent_dir)
            print(f"   {rel}")
    print()
    print("📋 Next steps:")
    print(f"   1. Edit workspace/SOUL.md and workspace/TOOLS.md")
    print(f"   2. Run k8s/setup-gcp-sa.sh to create GCP service account")
    print(f"   3. Create secrets: kubectl create secret generic clawdbot-{name}-secrets \\")
    print(f"        --namespace={namespace} --from-env-file=.env")
    print(f"   4. Deploy: clawdbot deploy {name}")


def list_agents(args):
    """List all registered agents."""
    if not AGENTS_DIR.exists():
        print("No agents found.")
        return

    agents = [d for d in AGENTS_DIR.iterdir() if d.is_dir() and (d / "openclaw.json").exists()]
    if not agents:
        print("No agents found.")
        return

    print(f"🤖 ClawdBots Agents ({len(agents)}):\n")
    for agent_dir in sorted(agents):
        config = json.loads((agent_dir / "openclaw.json").read_text())
        agent = config.get("agent", {})
        name = agent.get("name", agent_dir.name)
        desc = agent.get("description", "")
        model = agent.get("model", "?")
        print(f"  {name:<15} {desc[:60]}")
        print(f"  {'':15} model: {model}")
        print()


def deploy_agent(args):
    """Deploy an agent to GKE."""
    name = args.name.lower().strip()
    env = args.env or "dev"
    namespace = DEFAULT_NAMESPACE_PROD if env == "prod" else DEFAULT_NAMESPACE_DEV
    agent_dir = AGENTS_DIR / name

    if not agent_dir.exists():
        print(f"❌ Agent '{name}' not found at {agent_dir}")
        sys.exit(1)

    image = f"us-east1-docker.pkg.dev/{GCP_PROJECT}/clawdbots/clawdbot-{name}"
    tag = datetime.now().strftime("%Y%m%d-%H%M%S")

    print(f"🚀 Deploying {name} to {namespace}")
    print(f"   Image: {image}:{tag}")
    print()

    # Build
    print("📦 Building Docker image...")
    subprocess.run(
        ["docker", "build", "-t", f"{image}:{tag}", "-t", f"{image}:latest", "."],
        cwd=agent_dir, check=True,
    )

    # Push
    print("📤 Pushing to Artifact Registry...")
    subprocess.run(["docker", "push", f"{image}:{tag}"], check=True)
    subprocess.run(["docker", "push", f"{image}:latest"], check=True)

    # Apply K8s manifests
    print("☸️  Applying K8s manifests...")
    k8s_dir = agent_dir / "k8s"
    for manifest in sorted(k8s_dir.glob("*.yaml")):
        # Patch namespace
        subprocess.run(
            ["kubectl", "apply", "-f", str(manifest), "-n", namespace],
            check=True,
        )

    # Update image
    subprocess.run([
        "kubectl", "set", "image",
        f"deployment/clawdbot-{name}",
        f"agent={image}:{tag}",
        "-n", namespace,
    ], check=True)

    print(f"\n✅ {name} deployed to {namespace}")
    print(f"   kubectl logs -f deployment/clawdbot-{name} -n {namespace}")


def agent_status(args):
    """Check agent status on GKE."""
    name = args.name.lower().strip()
    env = args.env or "dev"
    namespace = DEFAULT_NAMESPACE_PROD if env == "prod" else DEFAULT_NAMESPACE_DEV

    print(f"📊 Status for clawdbot-{name} in {namespace}:\n")
    subprocess.run([
        "kubectl", "get", "pods", "-l", f"app=clawdbot-{name}",
        "-n", namespace, "-o", "wide",
    ])


def destroy_agent(args):
    """Remove agent deployment from GKE."""
    name = args.name.lower().strip()
    env = args.env or "dev"
    namespace = DEFAULT_NAMESPACE_PROD if env == "prod" else DEFAULT_NAMESPACE_DEV

    print(f"🗑️  Destroying clawdbot-{name} from {namespace}")
    k8s_dir = AGENTS_DIR / name / "k8s"

    for manifest in sorted(k8s_dir.glob("*.yaml"), reverse=True):
        subprocess.run(
            ["kubectl", "delete", "-f", str(manifest), "-n", namespace, "--ignore-not-found"],
        )

    print(f"✅ {name} removed from {namespace}")


def main():
    parser = argparse.ArgumentParser(
        prog="clawdbot",
        description="ClawdBots — Multi-agent platform for Brandlovrs",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # create
    p_create = subparsers.add_parser("create", help="Create a new agent")
    p_create.add_argument("name", help="Agent name (lowercase, no spaces)")
    p_create.add_argument("description", help="What this agent does")
    p_create.add_argument("--tools", default="", help="Comma-separated tool list")
    p_create.add_argument("--namespace", default=None, help="K8s namespace")
    p_create.add_argument("--model", default=None, help="LLM model identifier")
    p_create.set_defaults(func=create_agent)

    # list
    p_list = subparsers.add_parser("list", help="List all agents")
    p_list.set_defaults(func=list_agents)

    # deploy
    p_deploy = subparsers.add_parser("deploy", help="Deploy agent to GKE")
    p_deploy.add_argument("name", help="Agent name")
    p_deploy.add_argument("--env", choices=["dev", "prod"], default="dev")
    p_deploy.set_defaults(func=deploy_agent)

    # status
    p_status = subparsers.add_parser("status", help="Check agent status")
    p_status.add_argument("name", help="Agent name")
    p_status.add_argument("--env", choices=["dev", "prod"], default="dev")
    p_status.set_defaults(func=agent_status)

    # destroy
    p_destroy = subparsers.add_parser("destroy", help="Remove agent from GKE")
    p_destroy.add_argument("name", help="Agent name")
    p_destroy.add_argument("--env", choices=["dev", "prod"], default="dev")
    p_destroy.set_defaults(func=destroy_agent)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
