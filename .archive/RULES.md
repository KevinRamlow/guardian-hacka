# RULES.md - Development & Operations Standards

**Last Updated:** 2026-03-06  
**Applies To:** All Billy skills, workspace tools, and automation scripts

---

## 🔒 API-First Mutations (MANDATORY)

**Rule:** All data mutations MUST go through API endpoints. Direct database writes and message queue publishes are FORBIDDEN.

### What This Means

✅ **ALLOWED:**
- Read-only SQL queries (`SELECT`)
- API calls (POST, PUT, DELETE) to application endpoints
- File operations within workspace
- External API calls (Slack, Linear, Google APIs)

❌ **FORBIDDEN:**
- Direct database `INSERT`, `UPDATE`, `DELETE` statements
- Direct RabbitMQ/message queue publishes
- Direct cache writes (Redis, Memcached)
- Bypassing application business logic

### Why?

1. **Security** — APIs enforce auth and permissions
2. **Audit trail** — All mutations logged via API
3. **Business logic** — Validation, side effects handled correctly
4. **Maintainability** — Single source of truth
5. **Safety** — Prevents data corruption and race conditions

### Examples

#### ❌ WRONG (Direct DB Write)
```bash
mysql -e "INSERT INTO proofread_medias (media_id, result) VALUES (123, 'approved')"
```

#### ✅ CORRECT (Via API)
```bash
curl -X POST https://guardian-api/v1/campaigns/1/ads/2/contents/approve \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"contentIds": [123]}'
```

---

#### ❌ WRONG (Direct Queue Publish)
```bash
# Publishing directly to RabbitMQ
rabbitmqadmin publish exchange=amq.default routing_key=guardian-queue payload='{"id": 123}'
```

#### ✅ CORRECT (Via API)
```bash
# Trigger reprocess via Guardian API
curl -X POST http://guardian-api.prod.svc/v1/backoffice/reprocess-media \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"mediaIDs": "123", "processingLevel": "auto"}'
```

---

## 📋 Skill Development Rules

### 1. All Billy Skills Must Follow API-First

When creating or updating skills for Billy (or any workspace automation):
- Identify the proper API endpoint for the action
- Document required auth (Bearer tokens, API keys, internal headers)
- Never bypass APIs with direct database/queue access
- If an API endpoint doesn't exist, request one from the team

### 2. Document Auth Requirements

Every skill that calls APIs must document:
- Required auth method (Bearer token, API key, OAuth)
- Required permissions/scopes
- Where to get credentials
- Example environment variable setup

**Example (in SKILL.md):**
```markdown
## Authentication

Required: Bearer token with GuardianTeam permission

export GUARDIAN_AUTH_TOKEN='Bearer eyJ...'
```

### 3. Handle Errors Gracefully

- Check for missing auth tokens before making API calls
- Provide clear error messages with actionable steps
- Don't expose sensitive data in error logs
- Return proper exit codes (0 = success, non-zero = failure)

### 4. Use Environment Variables for Secrets

```bash
# ✅ GOOD
GUARDIAN_AUTH_TOKEN="${GUARDIAN_AUTH_TOKEN:-}"
if [ -z "$GUARDIAN_AUTH_TOKEN" ]; then
    echo "Error: GUARDIAN_AUTH_TOKEN not set"
    exit 1
fi

# ❌ BAD (hardcoded token)
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cC..."
```

---

## 🛠️ Migration Guide

### Migrating Existing Skills

If you find a skill that violates the API-first rule:

1. **Identify the mutation:**
   - What data is being written?
   - What queue is being published to?
   - What side effects should occur?

2. **Find or request the API endpoint:**
   - Check application routes (`routes_v1.go`, FastAPI routers)
   - If endpoint doesn't exist, ask the team to create one
   - Document the endpoint spec

3. **Rewrite the skill:**
   - Replace direct DB/queue calls with API calls
   - Add auth handling
   - Update SKILL.md documentation
   - Test in staging/dev environment

4. **Update SKILL.md:**
   - Document the new API-based approach
   - Add migration notes explaining the change
   - Mark old approach as DEPRECATED

---

## 🔍 Enforcement

### Review Checklist

Before merging any new skill or tool:
- [ ] No direct `INSERT`/`UPDATE`/`DELETE` SQL statements
- [ ] No direct queue publishes (RabbitMQ, Kafka, etc.)
- [ ] All mutations go through documented API endpoints
- [ ] Auth requirements clearly documented
- [ ] Error handling for missing credentials
- [ ] SKILL.md updated with API usage

### Audit Commands

Find potential violations:

```bash
# Find direct SQL mutations
grep -r "INSERT INTO\|UPDATE.*SET\|DELETE FROM" skills/ --include="*.sh" --include="*.py"

# Find RabbitMQ publishes
grep -r "rabbitmqadmin\|amqp\|publish.*queue" skills/ --include="*.sh" --include="*.py"

# Find hardcoded tokens
grep -r "Bearer ey[A-Za-z0-9]" skills/ --include="*.sh" --include="*.py"
```

---

## 📚 Reference

### API Endpoints by Service

**Guardian API** (`guardian-api.prod.svc`):
- POST `/v1/backoffice/reprocess-media` — Reprocess media
- POST `/v1/campaigns/:id/ads/:id/contents/approve` — Approve content
- POST `/v1/campaigns/:id/ads/:id/contents/refuse` — Refuse content

**Campaign Manager API** (`campaign-manager-api.prod.svc`):
- (Add endpoints as needed)

### Auth Methods

| Service | Method | Header | Example |
|---------|--------|--------|---------|
| Guardian API (backoffice) | Bearer token | `Authorization: Bearer $TOKEN` | GuardianTeam permission |
| Guardian API (internal) | Internal API key | `X-GU-Internal-API-Key: $KEY` | Service-to-service |
| Billy internal | (none yet) | (TBD) | Billy is private/testing |

---

## 🚨 Exceptions

**Very rare cases where direct access might be needed:**
- Emergency production fixes (with explicit approval)
- One-time data migrations (scripted, reviewed, tested)
- Performance-critical read paths (SELECT only)

**Process for exceptions:**
1. Document why API approach isn't feasible
2. Get approval from tech lead (Manoel)
3. Add safeguards (dry-run, confirmations, backups)
4. Create Linear task to build proper API endpoint afterward

---

## 📝 History

- **2026-03-06** — Created RULES.md, enforced API-first for all Billy skills and workspace tools (CAI-103)

---

**Questions?** Ask Caio or Manoel.
