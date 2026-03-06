# Access Control Patterns

## Layer 1: Slack ACL (Who Can Talk)

Defined in `openclaw.json` per agent.

```json
{
  "channels": {
    "slack": {
      "allowedChannels": ["data-team"],
      "allowedUsers": ["U04PHF0L65P", "U07B83ANSPM"]
    }
  }
}
```

**Patterns:**
- **Team-restricted**: Only specific channel + users (e.g., Neuron → data team)
- **Leadership-only**: Channel ACL + leadership user IDs
- **Open**: Empty arrays = accessible to all (use sparingly)

## Layer 2: GCP IAM (What It Can Access)

Each agent gets a dedicated GCP service account via Workload Identity.

**Principle:** Grant minimum required roles.

| Agent   | Roles | Justification |
|---------|-------|---------------|
| Neuron  | bigquery.dataViewer, bigquery.jobUser, cloudsql.client | Read-only data access |
| Billy   | bigquery.dataViewer | Analytics only |
| Guardian| (runs separately) | Existing infrastructure |

**Never grant:**
- `roles/owner` or `roles/editor`
- `roles/bigquery.admin`
- `roles/cloudsql.admin`
- Any `*.admin` role

## Layer 3: K8s NetworkPolicy (Where It Can Connect)

Each agent has a NetworkPolicy restricting egress:

```yaml
egress:
  - ports: [53/UDP, 53/TCP]        # DNS
  - ports: [443/TCP]               # HTTPS APIs
  - ports: [3306/TCP]              # MySQL (if needed)
```

**Patterns:**
- **Data agent**: DNS + HTTPS + MySQL
- **API-only agent**: DNS + HTTPS only
- **Isolated agent**: DNS + specific IP ranges only

## Layer 4: Database Users (What Data It Sees)

Create per-agent MySQL users with minimal grants:

```sql
-- Neuron: read-only on specific tables
CREATE USER 'neuron_readonly'@'%' IDENTIFIED BY '...';
GRANT SELECT ON `db-maestro-prod`.proofread_medias TO 'neuron_readonly'@'%';
GRANT SELECT ON `db-maestro-prod`.actions TO 'neuron_readonly'@'%';
GRANT SELECT ON `db-maestro-prod`.campaigns TO 'neuron_readonly'@'%';
GRANT SELECT ON `db-maestro-prod`.media_content TO 'neuron_readonly'@'%';
FLUSH PRIVILEGES;
```

## Layer 5: Agent-Level Safety (SOUL.md)

Each agent's SOUL.md encodes safety rules:
- "SELECT only" for data agents
- "Never share PII" for all agents
- "Ask before expensive operations"
- "Stay within authorized channels"

This is the soft layer — relies on LLM compliance — but combined with IAM/Network layers, provides defense in depth.

## Security Audit Checklist

For each agent, verify:
- [ ] GCP SA has only required roles (no wildcards)
- [ ] Workload Identity is properly bound
- [ ] NetworkPolicy restricts egress appropriately
- [ ] MySQL user is read-only with table-level grants
- [ ] Slack ACL limits to intended channels/users
- [ ] SOUL.md has clear safety rules
- [ ] No credentials in workspace files (use K8s secrets)
- [ ] Resource quotas prevent runaway usage
