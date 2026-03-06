# MySQL Skill

## When to Use
When asked about campaigns, content moderation (proofread), creators, media, or any data in db-maestro-prod.

## How to Query
Use `exec` to run mysql:

```bash
mysql -h 127.0.0.1 -P 3306 -D db-maestro-prod -e "SELECT ... LIMIT 100"
```

## Safety Rules
1. **SELECT ONLY** — Never run INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE
2. **Always LIMIT** — Default LIMIT 100
3. **Date filter** — Always add WHERE created_at >= ... to avoid full scans
4. **No PII** — Mask emails, names, phone numbers in output

## Schema Reference
See TOOLS.md for full table schemas and join patterns.

## Common Patterns

### Moderation stats (last 7 days)
```sql
SELECT 
  DATE(pm.created_at) as day,
  COUNT(*) as total,
  SUM(pm.status = 'approved') as approved,
  SUM(pm.status = 'refused') as refused,
  ROUND(SUM(pm.status = 'approved') / COUNT(*) * 100, 1) as approval_rate
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY day ORDER BY day DESC;
```

### Campaign breakdown
```sql
SELECT c.name, c.id,
  COUNT(*) as total_moderations,
  SUM(pm.status = 'approved') as approved,
  SUM(pm.status = 'refused') as refused
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN campaigns c ON a.campaign_id = c.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY c.id, c.name
ORDER BY total_moderations DESC
LIMIT 20;
```

### Agentic model results
```sql
SELECT pm.id, pm.status, pm.created_at,
  JSON_EXTRACT(pm.metadata, '$.audio_output') as audio_output
FROM proofread_medias pm
WHERE JSON_EXTRACT(pm.metadata, '$.audio_output') IS NOT NULL
  AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY pm.created_at DESC
LIMIT 50;
```
