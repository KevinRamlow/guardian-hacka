# Brand Creation Skill (API-First)

**Version:** 2.0 (API-based)  
**Status:** ✅ Ready for deployment (requires auth configuration)  
**Linear Task:** CAI-75  
**Last Updated:** 2026-03-06 02:18 UTC

## Overview

Billy can now create brands automatically via the **user-management-api** REST endpoint, eliminating the need for manual Slack requests.

**73 manual brand creation requests** in 2 months → Now fully automated.

## Architecture

### Previous Attempt (❌ Blocked)
- Direct MySQL INSERT/UPDATE
- **Blocked by read-only permissions**
- Violated API-first architecture

### Current Implementation (✅ Correct)
- Uses `user-management-api` REST endpoint: `POST /v1/brands`
- Proper authentication (Bearer token, platform admin)
- Validation + error handling
- Audit trail via API logs
- No direct database access

## API Endpoint

**Service:** user-management-api  
**Endpoint:** `POST /v1/brands`  
**Authentication:** Bearer token (platform admin role required)  
**Location:** `/root/.openclaw/workspace/user-management-api/`

### Request Format

```json
{
  "name": "Nike",                       // Required, 1-100 chars
  "brand_slug": "nike",                 // Required, 1-150 chars, alphanumeric
  "description": "Sportswear brand",    // Optional, max 2048 chars
  "defaultFeePercentage": 5,            // Required, 0-100
  "autoApproveGroups": false            // Required, boolean
}
```

### Response Format

```json
{
  "id": 904,
  "name": "Nike",
  "brandSlug": "nike",
  "description": "Sportswear brand",
  "defaultFeePercentage": 5,
  "autoApproveGroups": false,
  "logoUrl": "",
  "balance": 0.0,
  "createdAt": "2026-03-06T02:00:00Z"
}
```

### Error Responses

**400 Bad Request** - Invalid input:
```json
{
  "error": "invalid request",
  "message": "name is required"
}
```

**401 Unauthorized** - Missing/invalid token:
```json
{
  "error": "unauthorized",
  "message": "invalid or missing token"
}
```

**403 Forbidden** - Not platform admin:
```json
{
  "error": "forbidden",
  "message": "insufficient permissions"
}
```

**409 Conflict** - Duplicate slug:
```json
{
  "error": "duplicate",
  "message": "brand_slug already exists"
}
```

## Configuration

### Required Environment Variables

Billy's `.env` file needs:

```bash
# user-management-api configuration
USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"  # or staging URL
USER_MGMT_API_TOKEN="your-platform-admin-bearer-token-here"
```

**⚠️ SECURITY:**
- Token must have **platform admin** role
- Token grants full brand/user management access
- Store securely (do not commit to git)
- Rotate periodically

### How to Get a Token

**Option 1: Use Caio's Token (temporary testing)**
1. Login to backoffice/admin panel
2. Open browser devtools → Network tab
3. Find any API request to user-management-api
4. Copy `Authorization: Bearer <token>` header value

**Option 2: Create Billy Service Account (production)**
1. Create dedicated user `billy@brandlovers.ai` in user-management-api
2. Grant platform admin role
3. Generate long-lived token for service account
4. Store in Billy's `.env`

**Option 3: OAuth Client Credentials Flow (future)**
- Implement client credentials grant
- Billy authenticates as service app
- Token auto-refreshes

## Implementation Files

### 1. Bash Script (`create-brand-api.sh`)

**Location:** `scripts/create-brand-api.sh`  
**Size:** 4.4 KB  
**Purpose:** Direct command-line brand creation via API

**Usage:**
```bash
export USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"
export USER_MGMT_API_TOKEN="your-token"

./scripts/create-brand-api.sh "Nike" "Sportswear brand" 5 false
```

**Features:**
- Input validation (name length, fee range, etc.)
- Automatic slug generation (handles special chars)
- Pretty-printed JSON output
- HTTP status code checking
- Colored terminal output

### 2. Python Wrapper (`brand-creator-api.py`)

**Location:** `scripts/brand-creator-api.py`  
**Size:** 9.6 KB  
**Purpose:** Billy's primary interface for brand creation

**Usage:**
```bash
python3 scripts/brand-creator-api.py "Nike" "Sportswear brand" 5 false
```

**Features:**
- ✅ Duplicate detection (checks existing brands by name/slug)
- ✅ Slug validation and generation
- ✅ Comprehensive API error handling
- ✅ Structured JSON output for Billy
- ✅ Timeout handling (30s)
- ✅ Connection error recovery

**Output Format:**
```json
{
  "success": true,
  "brand": {
    "id": 904,
    "name": "Nike",
    "slug": "nike",
    "description": "Sportswear brand",
    "defaultFeePercentage": 5,
    "autoApproveGroups": false,
    "logoUrl": "",
    "createdAt": "2026-03-06T02:00:00Z"
  },
  "message": "Brand 'Nike' created with ID 904"
}
```

**Duplicate Detection Output:**
```json
{
  "success": false,
  "error": "DUPLICATE",
  "existing_brand": {
    "id": 723,
    "name": "Nike",
    "slug": "nike",
    "description": "Existing sportswear brand"
  },
  "message": "Brand 'Nike' (ID: 723) already exists with slug 'nike'"
}
```

## Workflow

### 1. User Request (Slack)

**User:** "@Billy create brand 'Tesla' with description 'Electric vehicles'"

### 2. Billy Processing

```python
import subprocess
import json

result = subprocess.run(
    [
        "python3",
        "skills/brand-creation/scripts/brand-creator-api.py",
        "Tesla",
        "Electric vehicles",
        "5",  # default fee
        "false"  # auto approve
    ],
    capture_output=True,
    text=True
)

data = json.loads(result.stdout)
```

### 3. Response to User

**Success:**
> ✅ Brand created successfully!
> 
> **Tesla** (ID: 905)  
> Slug: `tesla`  
> Description: Electric vehicles  
> Default Fee: 5%

**Duplicate:**
> ⚠️ Brand **Tesla** already exists!
> 
> ID: 842  
> Slug: `tesla`  
> Would you like to use the existing brand or create with a different name?

**Error:**
> ❌ Failed to create brand: Unauthorized
> 
> The API token may have expired. Please contact tech team.

## Validation Rules

### Name
- Required
- 1-100 characters
- Any characters allowed (emoji, special chars OK)

### Slug (auto-generated from name)
- Lowercase only
- Alphanumeric + hyphens
- Max 150 characters
- Must be unique (API enforces)

**Examples:**
- `"Nike"` → `"nike"`
- `"L'Oréal"` → `"loreal"`
- `"Coca-Cola"` → `"coca-cola"`
- `"H&M"` → `"h-m"`

### Description
- Optional
- Max 2048 characters

### Default Fee Percentage
- Required
- Integer 0-100
- Default: 5

### Auto-approve Groups
- Required
- Boolean (true/false)
- Default: false

## Testing

### 1. Test Duplicate Detection

```bash
# First call - should succeed
python3 scripts/brand-creator-api.py "TestBrand" "Test description"

# Second call - should fail with DUPLICATE
python3 scripts/brand-creator-api.py "TestBrand" "Another description"
```

### 2. Test Validation

```bash
# Empty name - should fail
python3 scripts/brand-creator-api.py "" "Description"

# Name too long - should fail
python3 scripts/brand-creator-api.py "$(printf 'A%.0s' {1..101})" "Desc"

# Invalid fee - should fail
python3 scripts/brand-creator-api.py "Test" "Desc" 150
```

### 3. Test API Connectivity

```bash
# Should return 401 if token is invalid
export USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"
export USER_MGMT_API_TOKEN="invalid-token"
python3 scripts/brand-creator-api.py "Test" "Desc"
```

## Error Handling

### API Errors

| Error | Cause | Billy Response |
|-------|-------|----------------|
| DUPLICATE | Brand name/slug exists | Show existing brand, offer alternatives |
| API_ERROR 400 | Invalid input | Show validation error, ask for correction |
| API_ERROR 401 | Invalid token | Alert tech team, log to Linear |
| API_ERROR 403 | Insufficient permissions | Alert tech team, Billy needs admin role |
| TIMEOUT | API took >30s | Retry once, then report failure |
| CONNECTION_ERROR | Network issue | Retry 3 times, then report failure |

### Retry Logic

```python
MAX_RETRIES = 3
for attempt in range(MAX_RETRIES):
    result = create_brand(name, desc)
    if result["success"] or result["error"] == "DUPLICATE":
        break
    if attempt < MAX_RETRIES - 1:
        time.sleep(2 ** attempt)  # exponential backoff
```

## Monitoring

### Metrics to Track

1. **Success Rate** - Successful creations / total attempts
2. **Duplicate Rate** - Duplicate errors / total attempts
3. **API Latency** - Time to complete creation
4. **Token Expiry Events** - 401 responses
5. **Daily Volume** - Brands created per day

### Logging

Log to Linear (CAI workspace) for every brand creation:

```
[BRAND-CREATION] Brand 'Nike' created via API
- Brand ID: 904
- Slug: nike
- Requested by: @user.name (Slack U123456)
- API latency: 342ms
- Status: SUCCESS
```

## Deployment Checklist

Before Billy can use this skill:

- [ ] **API access verified** - user-management-api is reachable
- [ ] **Token generated** - Platform admin token obtained
- [ ] **Environment configured** - `.env` updated with URL + token
- [ ] **Python dependencies installed** - `requests` library available
- [ ] **Scripts executable** - `chmod +x scripts/*.sh scripts/*.py`
- [ ] **Duplicate detection tested** - Confirms it catches existing brands
- [ ] **Billy skill documented** - SKILL.md readable by Billy
- [ ] **Team notified** - Tech team knows Billy can create brands

## Future Enhancements

### Phase 2: Logo Upload
- Add logo upload support via `POST /v1/brands/:id/logo`
- Billy accepts image URLs or attachments
- Auto-generates thumbnails

### Phase 3: Organization Management
- Also handle organization creation (brands require organizations)
- Billy asks: "Should I create a new organization for this brand?"

### Phase 4: Bulk Import
- Import multiple brands from CSV/spreadsheet
- Validation before bulk creation
- Progress reporting

### Phase 5: Brand Updates
- Edit existing brands via `PUT /v1/brands/:id`
- Update descriptions, logos, fee percentages

## References

- **API Repository:** `/root/.openclaw/workspace/user-management-api/`
- **Routes Definition:** `user-management-api/internal/main/app/routes_v1.go`
- **Controller:** `user-management-api/internal/presentation/controllers/brand_controller.go`
- **DTO:** `user-management-api/internal/domain/dto/brand/brand_dto.go`
- **Billy Workspace:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/`

## Support

**Questions?** Contact:
- Caio Fonseca (@caio.fonseca) - Tech lead, API owner
- Anton - Orchestrator, skill maintainer

**Report Issues:**
- Linear workspace: `caio-tests` (CAI team)
- Task: CAI-75
