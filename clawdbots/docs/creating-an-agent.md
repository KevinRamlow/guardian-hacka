# How to Create a New Agent

## Quick Start (CLI)

```bash
cd /root/.openclaw/workspace/clawdbots

# Create agent scaffold
python cli/clawdbot.py create myagent "Description of what it does" \
  --tools=mysql,bigquery,web_search \
  --model=anthropic/claude-sonnet-4-5

# Customize the workspace
vim agents/myagent/workspace/SOUL.md
vim agents/myagent/workspace/TOOLS.md

# Set up GCP service account
bash agents/myagent/k8s/setup-gcp-sa.sh

# Create K8s secrets
kubectl create secret generic clawdbot-myagent-secrets \
  --namespace=clawdbots-dev \
  --from-literal=ANTHROPIC_API_KEY=sk-... \
  --from-literal=SLACK_TOKEN=xoxb-...

# Deploy
python cli/clawdbot.py deploy myagent --env=dev
```

## Step-by-Step

### 1. Plan Your Agent

Before creating, define:
- **Name**: lowercase, no spaces (e.g., `neuron`, `billy`)
- **Mission**: What does it do? Be specific.
- **Data sources**: What databases/APIs does it need?
- **Users**: Who can talk to it? Which channels?
- **Model**: Which LLM? (sonnet for most, opus for complex reasoning)

### 2. Generate Scaffold

```bash
python cli/clawdbot.py create <name> "<description>" --tools=<list>
```

This creates the full directory structure with sensible defaults.

### 3. Customize Workspace

The workspace defines your agent's personality and capabilities:

- **SOUL.md** — Who is this agent? What's its personality? What are its rules?
- **TOOLS.md** — Database schemas, API endpoints, connection details
- **AGENTS.md** — Session startup instructions
- **skills/** — Specialized skill files for complex operations

### 4. Configure Access Control

Edit `openclaw.json`:

```json
{
  "channels": {
    "slack": {
      "allowedChannels": ["data-team", "leadership"],
      "allowedUsers": ["U04PHF0L65P"]
    }
  }
}
```

### 5. Set Up IAM

Add your agent to `infrastructure/terraform/agents.tf`:

```hcl
myagent = {
  description = "My agent description"
  roles = [
    "roles/bigquery.dataViewer",
  ]
  namespace = "clawdbots-dev"
}
```

Or run the generated setup script:
```bash
bash agents/myagent/k8s/setup-gcp-sa.sh
```

### 6. Create Secrets

```bash
kubectl create secret generic clawdbot-myagent-secrets \
  --namespace=clawdbots-dev \
  --from-literal=ANTHROPIC_API_KEY=sk-... \
  --from-literal=SLACK_TOKEN=xoxb-... \
  --from-literal=MYSQL_USER=readonly_myagent \
  --from-literal=MYSQL_PASSWORD=...
```

### 7. Deploy

```bash
# Dev first
python cli/clawdbot.py deploy myagent --env=dev

# Check it's running
python cli/clawdbot.py status myagent --env=dev

# When ready, promote to prod
python cli/clawdbot.py deploy myagent --env=prod
```

### 8. Add to Terraform (for long-term management)

Add the agent to `agents.tf` and the deployment will be managed via CI/CD.

## Checklist for New Agents

- [ ] Agent scaffold created
- [ ] SOUL.md customized with clear mission and rules
- [ ] TOOLS.md has all schemas and connection details
- [ ] openclaw.json has correct channel/user ACLs
- [ ] GCP service account created with minimal roles
- [ ] K8s secrets created in dev namespace
- [ ] NetworkPolicy reviewed for correct egress rules
- [ ] Deployed to dev and tested
- [ ] Added to Terraform agents.tf
- [ ] Documented in this repo
