# Monitoring & Cost Attribution

## Pod Monitoring

All agents are labeled for easy filtering:

```bash
# All ClawdBots pods
kubectl get pods -l platform=clawdbots -A

# Specific agent
kubectl get pods -l app=clawdbot-neuron -n clawdbots-dev

# Logs
kubectl logs -f deployment/clawdbot-neuron -n clawdbots-dev -c agent

# Cloud SQL Proxy logs
kubectl logs -f deployment/clawdbot-neuron -n clawdbots-dev -c cloud-sql-proxy
```

## Resource Usage

```bash
# Per-agent resource consumption
kubectl top pods -l platform=clawdbots -n clawdbots-dev

# Namespace quota usage
kubectl describe resourcequota clawdbots-quota -n clawdbots-dev
```

## Cost Attribution

### GKE Labels
Every agent has:
- `platform: clawdbots`
- `agent: <name>`

Use GCP Billing → Cost Table → filter by label `platform=clawdbots` to see platform costs.

### LLM API Costs
Track via:
- Anthropic dashboard (by API key — use separate keys per agent)
- Langfuse traces (if integrated)

### BigQuery Costs
- Each agent's service account runs queries independently
- Use `INFORMATION_SCHEMA.JOBS` to track per-SA query costs:

```sql
SELECT user_email, 
  SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed,
  COUNT(*) AS query_count
FROM `brandlovers-prod.region-us-east1`.INFORMATION_SCHEMA.JOBS
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND user_email LIKE 'clawdbot-%'
GROUP BY user_email
ORDER BY tb_processed DESC;
```

## Alerting (Future)

TODO: Set up alerts for:
- Agent pod crash loops
- High memory/CPU usage
- Unusual BigQuery scan volumes
- Slack message rate anomalies
