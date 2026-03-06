# BigQuery Skill

## When to Use
When asked about analytics data, event tracking, user behavior, or guardian traces that live in BigQuery.

## How to Query
Use `exec` to run `bq query`:

```bash
bq query --project_id=brandlovers-prod --use_legacy_sql=false --format=prettyjson \
  'SELECT ... FROM `brandlovers-prod.dataset.table` WHERE ... LIMIT 100'
```

## Key Datasets
- `brandlovers-prod.analytics` — Event tracking
- `brandlovers-prod.guardian` — Moderation traces

## Cost Rules
1. Always filter by partition column (`_PARTITIONTIME`, `created_at`)
2. Select only needed columns
3. Use `--dry_run` first for queries you suspect are large
4. Default LIMIT 100

## Example Queries

### Daily active events (last 7 days)
```sql
SELECT DATE(_PARTITIONTIME) as day, COUNT(*) as events
FROM `brandlovers-prod.analytics.events`
WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY day ORDER BY day DESC
```
