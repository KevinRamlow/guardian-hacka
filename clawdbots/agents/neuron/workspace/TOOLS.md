# TOOLS.md - Neuron Agent Data Sources

## MySQL (Production — db-maestro-prod)

**Connection:** Cloud SQL Auth Proxy sidecar on localhost:3306
**Instance:** brandlovers-prod:us-east1:brandlovers-prod
**Database:** db-maestro-prod
**Access:** READ ONLY — SELECT queries only

### Key Tables & Schemas

#### `proofread_medias` — Content moderation results
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| action_id | BIGINT | FK → actions.id |
| status | VARCHAR | approved, refused, pending |
| metadata | JSON | Contains model outputs, audio_output for agentic |
| created_at | DATETIME | When moderation happened |
| updated_at | DATETIME | Last update |

#### `actions` — Creator content submissions
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| campaign_id | BIGINT | FK → campaigns.id |
| creator_id | BIGINT | FK → creators.id |
| status | VARCHAR | Action status |
| created_at | DATETIME | Submission time |

#### `media_content` — Actual media files
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| action_id | BIGINT | FK → actions.id |
| type | VARCHAR | video, image, text |
| url | TEXT | Media URL |
| created_at | DATETIME | Upload time |

#### `campaigns` — Marketing campaigns
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| name | VARCHAR | Campaign name |
| brand_id | BIGINT | FK → brands.id |
| status | VARCHAR | active, completed, draft |
| created_at | DATETIME | Creation time |

#### `proofread_guidelines` — Moderation rules per campaign
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| campaign_id | BIGINT | FK |
| guideline | TEXT | Rule text |
| type | VARCHAR | Guideline category |

#### `proofread_media_contest` — Contested moderation decisions
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| proofread_media_id | BIGINT | FK → proofread_medias.id |
| status | VARCHAR | Contest status |
| reason | TEXT | Contest reason |

#### `media_content_refused_guidelines` — Which guidelines caused refusal
| Column | Type | Description |
|--------|------|-------------|
| id | BIGINT | PK |
| media_content_id | BIGINT | FK |
| proofread_guideline_id | BIGINT | FK |

### Common Join Patterns

```sql
-- Content with moderation results
SELECT pm.*, mc.type, mc.url, a.campaign_id
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN media_content mc ON mc.action_id = a.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY);

-- Agentic model results only
SELECT pm.*
FROM proofread_medias pm
WHERE JSON_EXTRACT(pm.metadata, '$.audio_output') IS NOT NULL;

-- Campaign moderation summary
SELECT c.name, c.id,
       COUNT(*) as total,
       SUM(pm.status = 'approved') as approved,
       SUM(pm.status = 'refused') as refused
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
JOIN campaigns c ON a.campaign_id = c.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY c.id, c.name
ORDER BY total DESC;
```

## BigQuery

**Project:** brandlovers-prod
**Access:** Via Workload Identity (bigquery.dataViewer role)

### Key Datasets
- `analytics` — Event tracking, user behavior
- `guardian` — Moderation traces, agent decisions, tolerance patterns

### Cost Tips
- Always use partitioned columns (usually `_PARTITIONTIME` or `created_at`) in WHERE
- Prefer `SELECT specific_columns` over `SELECT *`
- Use `LIMIT` during exploration
- Estimate with `--dry_run` for large queries

## Metabase

**Status:** Not directly accessible (behind Cloudflare Access)
**Workaround:** Use MySQL/BigQuery directly for same data

## Query Safety Rules

1. **READ ONLY** — Never run DDL or DML
2. **LIMIT everything** — Default LIMIT 100
3. **Warn on big scans** — If query touches >1M rows or >10GB, warn first
4. **No PII in responses** — Mask emails, phone numbers, full names
5. **Time-bound queries** — Always add date filters to avoid full table scans
