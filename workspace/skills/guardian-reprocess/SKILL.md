# Guardian Reprocess Skill

Reprocess orphaned media that Guardian AI failed to analyze — **via Guardian API backoffice endpoint**.

## When to Use

- Media uploaded but never analyzed by Guardian (no `proofread_medias` record)
- Media stuck in processing pipeline
- Need to re-trigger Guardian analysis for specific media

## Quick Start

```bash
# Set auth token first (REQUIRED)
export GUARDIAN_AUTH_TOKEN='Bearer eyJhbGciOi...'

# Reprocess specific media
./skills/guardian-reprocess/scripts/reprocess.sh 61520 61487

# Check media status
./skills/guardian-reprocess/scripts/reprocess.sh --check 61520

# Find orphaned media from last 24h
./skills/guardian-reprocess/scripts/reprocess.sh --find-orphans

# Preview without sending
./skills/guardian-reprocess/scripts/reprocess.sh --dry-run 61520
```

## How It Works (API-Based)

### New Architecture (2026-03-06)
```
Script calls Guardian API
    ↓
POST /v1/backoffice/reprocess-media
    {
      "mediaIDs": "61520,61487",
      "processingLevel": "auto"  // or "guardian" or "ads_treatment"
    }
    ↓
Guardian API use case routes messages
    ↓
Publishes to RabbitMQ (guardian-medias-prod or guardian-ads-treatment-prod)
    ↓
Consumed by guardian-api or ads-treatment service
    ↓
Creates proofread_medias record
```

### Processing Levels
- **`auto`** (default) — API decides based on `compressed_media_key`
  - Has compressed key → guardian queue
  - No compressed key → ads-treatment queue
- **`guardian`** — Force send to Guardian queue (requires compressed media)
- **`ads_treatment`** — Force send to ads-treatment queue (for compression)

### Why API Instead of Direct RabbitMQ?
- ✅ Proper auth and permission checks (GuardianTeam only)
- ✅ Single source of truth for business logic
- ✅ Audit trail via API logs
- ✅ Validation and error handling
- ❌ No direct queue access from tools (security)

## Authentication

**Required:** Bearer token with `GuardianTeam` permission

```bash
# Get token from Guardian backoffice UI or auth service
export GUARDIAN_AUTH_TOKEN='Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'

# Or set in shell profile
echo 'export GUARDIAN_AUTH_TOKEN="Bearer YOUR_TOKEN_HERE"' >> ~/.bashrc
```

Ask Caio for a token if you don't have one.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GUARDIAN_AUTH_TOKEN` | (none) | **REQUIRED** Bearer token |
| `GUARDIAN_API_URL` | `http://guardian-api.prod.svc/v1` | Guardian API base URL |
| `PROCESSING_LEVEL` | `auto` | Routing strategy: `auto`, `guardian`, `ads_treatment` |

## Requirements

- **kubectl** configured with GKE prod cluster access (`/opt/google-cloud-sdk/bin`)
- **MySQL** access via cloud-sql-proxy (for status checks and orphan finding)
- **GUARDIAN_AUTH_TOKEN** environment variable set

## Database Reference

### Key Tables
- `media_content` — uploaded media (id = media_content_id used in API)
- `proofread_medias` — Guardian analysis results (media_id → media_content.id)
- `actions` — creator actions (media_content.action_id → actions.id)

### Useful Queries (Read-Only)

```sql
-- Find orphaned media (uploaded but not analyzed)
SELECT mc.id, mc.created_at, mc.compressed_media_key IS NOT NULL as compressed,
       TIMESTAMPDIFF(HOUR, mc.created_at, NOW()) as hours_old
FROM media_content mc
LEFT JOIN proofread_medias pm ON pm.media_id = mc.id
WHERE pm.id IS NULL
  AND mc.approved_at IS NULL AND mc.refused_at IS NULL AND mc.deleted_at IS NULL
  AND mc.created_at >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
ORDER BY mc.created_at DESC;

-- Check if media was processed
SELECT mc.id, mc.compressed_media_key IS NOT NULL as compressed,
       pm.id as pm_id, pm.created_at as analyzed_at
FROM media_content mc
LEFT JOIN proofread_medias pm ON pm.media_id = mc.id
WHERE mc.id = 61520;
```

**Note:** All mutations (reprocessing) must go through the API endpoint. Direct database writes and RabbitMQ publishes are forbidden.

## API Reference

### POST /v1/backoffice/reprocess-media

**Auth:** Bearer token with `GuardianTeam` permission

**Request:**
```json
{
  "campaignIDs": "123,456",      // optional, comma-separated
  "momentIDs": "789",            // optional
  "adIDs": "111",                // optional
  "mediaIDs": "222,333",         // optional
  "processingLevel": "auto"      // required: auto|guardian|ads_treatment
}
```

**Response (immediate):**
```json
{
  "message": "reprocess begun"
}
```

Processing happens in background. Check `proofread_medias` table after a few seconds to verify.

## Troubleshooting

### "GUARDIAN_AUTH_TOKEN not set"
```bash
export GUARDIAN_AUTH_TOKEN='Bearer YOUR_TOKEN_HERE'
./reprocess.sh 61520
```

### "No guardian-api pod found"
```bash
# Check pods
kubectl get pods -n prod -l app=guardian-api

# If not connected to GKE
gcloud container clusters get-credentials bl-cluster --region us-east1 --project brandlovers-prod
```

### Media still not processed after API call
1. Check response for errors
2. Wait 30-60 seconds (background processing)
3. Query `proofread_medias` table
4. Check guardian-api pod logs:
   ```bash
   kubectl logs -n prod -l app=guardian-api --tail=100 | grep -i reprocess
   ```

### API returns 401/403
- Token expired → get a new token
- Missing GuardianTeam permission → ask admin to grant it

## Migration Notes

**Old approach (DEPRECATED):**
- Direct RabbitMQ publish via `kubectl exec`
- No auth, no audit trail
- Hardcoded queue names and message formats

**New approach (CURRENT):**
- Guardian API endpoint with proper auth
- Business logic in API (DRY)
- Auditable, secure, maintainable

**Breaking changes:**
- Must set `GUARDIAN_AUTH_TOKEN` env var
- No more `--queue-status` flag (use kubectl + RabbitMQ management UI instead)
