# Brand Creation Skill - Deployment Guide

**Task:** CAI-75  
**Version:** 2.0 (API-based)  
**Date:** 2026-03-06  
**Status:** Ready for deployment

## What Changed

### ❌ Before (Blocked Implementation)
- Direct MySQL INSERT into `brands` and `organizations` tables
- **Failed:** Read-only database permissions
- Technical debt: Bypassed application logic

### ✅ After (API-First Implementation)
- REST API: `POST /v1/brands` via `user-management-api`
- Proper authentication (Bearer token, platform admin)
- Validation, audit trail, error handling
- Follows existing architecture patterns

## Files Created/Updated

```
/root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/brand-creation/
├── SKILL.md                       ← Updated (10.5 KB) - Main documentation
├── DEPLOYMENT.md                  ← New (this file) - Deployment guide
├── API-SPEC.md                    ← New - API endpoint specification
├── scripts/
│   ├── create-brand-api.sh        ← New (4.4 KB) - Bash implementation
│   └── brand-creator-api.py       ← New (9.6 KB) - Python wrapper for Billy
└── BLOCKED.md                     ← Archived - Previous attempt notes
```

## Prerequisites

### 1. API Access
- [x] `user-management-api` is deployed and reachable
- [x] Endpoint `POST /v1/brands` exists
- [ ] Network access from Billy VM (89.167.64.183) to API

**Verify:**
```bash
curl -I https://user-management-api.brandlovers.ai/v1/brands
# Should return: 401 Unauthorized (not 404 Not Found)
```

### 2. Authentication Token

Billy needs a **platform admin Bearer token**.

**Option A: Temporary Testing (Use Caio's Token)**
1. Login to admin panel: https://backoffice.brandlovers.ai
2. Open browser DevTools → Network tab
3. Find any API request → Copy `Authorization` header
4. Extract token: `Bearer <token>`

**Option B: Production (Service Account)**
1. Create user `billy@brandlovers.ai` in user-management-api
2. Assign platform admin role
3. Generate long-lived API token
4. Store securely in Billy's `.env`

### 3. Dependencies

**Python:**
```bash
# Verify Python 3 is installed
python3 --version  # Should be >= 3.7

# Install requests library
pip3 install requests

# Or on Debian/Ubuntu
apt-get install python3-requests
```

**Tools:**
```bash
# Verify jq is installed (for JSON parsing)
jq --version

# Install if missing
apt-get install jq
```

## Deployment Steps

### Step 1: Configure Environment Variables

On Billy VM (89.167.64.183):

```bash
# SSH to Billy
ssh root@89.167.64.183

# Navigate to Billy's workspace
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/

# Edit .env file
nano .env

# Add these lines:
USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"
USER_MGMT_API_TOKEN="paste-your-bearer-token-here"

# Save and exit (Ctrl+X, Y, Enter)

# Verify .env is NOT tracked by git
cat .gitignore | grep .env || echo ".env" >> .gitignore
```

### Step 2: Verify Scripts Are Executable

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/brand-creation/

chmod +x scripts/create-brand-api.sh
chmod +x scripts/brand-creator-api.py

# Verify permissions
ls -la scripts/
# Should show: -rwxr-xr-x (executable)
```

### Step 3: Test Connection

```bash
# Source environment variables
source /root/.openclaw/workspace/clawdbots/agents/billy/workspace/.env

# Test API connectivity
curl -H "Authorization: Bearer $USER_MGMT_API_TOKEN" \
     https://user-management-api.brandlovers.ai/v1/brands?perPage=1

# Expected: JSON response with brands list (HTTP 200)
# If 401: Token is invalid
# If 403: Token lacks platform admin role
# If 404: Wrong URL or endpoint doesn't exist
```

### Step 4: Test Brand Creation (Dry Run)

```bash
# Create a test brand
python3 scripts/brand-creator-api.py "TestBrandBilly" "Test brand for Billy skill deployment" 5 false

# Expected output:
# {
#   "success": true,
#   "brand": {
#     "id": 905,
#     "name": "TestBrandBilly",
#     ...
#   }
# }
```

### Step 5: Test Duplicate Detection

```bash
# Try creating the same brand again
python3 scripts/brand-creator-api.py "TestBrandBilly" "Another description" 5 false

# Expected output:
# {
#   "success": false,
#   "error": "DUPLICATE",
#   "existing_brand": {
#     "id": 905,
#     ...
#   }
# }
```

### Step 6: Clean Up Test Data

```bash
# Option 1: Use API to delete (if DELETE endpoint exists)
curl -X DELETE \
     -H "Authorization: Bearer $USER_MGMT_API_TOKEN" \
     https://user-management-api.brandlovers.ai/v1/brands/905

# Option 2: Ask Caio/tech team to remove test brand from database
```

### Step 7: Update Billy's Context

Billy needs to know about this skill. Update Billy's `AGENTS.md` or `TOOLS.md`:

```markdown
## Brand Creation

Billy can create brands automatically via user-management-api.

**Command:** "create brand [name] with description [desc]"

**Script:** `skills/brand-creation/scripts/brand-creator-api.py`

**Usage:**
python3 skills/brand-creation/scripts/brand-creator-api.py "Brand Name" "Description" 5 false
```

### Step 8: Notify Team

Post to #tech-gua-ma-internal Slack:

> 🚀 **Billy can now create brands automatically!**
> 
> Instead of manually creating brands via Slack requests, Billy will handle it through the user-management-api.
> 
> **How to use:** Just ask Billy to create a brand!
> 
> Example: "@Billy create brand 'Tesla' with description 'Electric vehicles'"
> 
> **Technical details:**
> - Uses REST API: POST /v1/brands
> - Automatic duplicate detection
> - Validates inputs before creation
> - Logs all operations to Linear (CAI-75)
> 
> **Blocked requests:** 73 brand creation requests in 2 months → Now fully automated ✅

## Verification Checklist

After deployment, verify:

- [ ] **Environment variables set** - `echo $USER_MGMT_API_URL` returns URL
- [ ] **Token is valid** - API returns 200 (not 401/403)
- [ ] **Scripts are executable** - `ls -la scripts/` shows `rwx` permissions
- [ ] **Python dependencies installed** - `python3 -c "import requests"` succeeds
- [ ] **Brand creation works** - Test brand created successfully
- [ ] **Duplicate detection works** - Second attempt caught duplicate
- [ ] **Billy knows about skill** - AGENTS.md/TOOLS.md updated
- [ ] **Team notified** - Slack message posted

## Rollback Plan

If something goes wrong:

1. **Remove .env variables:**
   ```bash
   cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/
   sed -i '/USER_MGMT_API/d' .env
   ```

2. **Restore old workflow:**
   - Billy creates Linear ticket for brand creation
   - Tech team handles manually

3. **Debug logs:**
   ```bash
   # Check Billy's logs
   tail -f /root/.openclaw/workspace/logs/billy.log
   
   # Check API errors
   cat /tmp/brand-response.json
   ```

## Monitoring

### Daily Health Check

Run this every morning:

```bash
# Test API connectivity
python3 -c "
import os, requests
url = os.getenv('USER_MGMT_API_URL')
token = os.getenv('USER_MGMT_API_TOKEN')
r = requests.get(f'{url}/v1/brands?perPage=1', headers={'Authorization': f'Bearer {token}'})
print(f'API Health: {r.status_code} - {'OK' if r.status_code == 200 else 'ERROR'}')
"
```

### Metrics to Track

1. **Brands created per day** - Track in Linear comments
2. **Duplicate detection rate** - How many duplicates caught
3. **API errors** - 401/403/500 responses
4. **Token expiry** - When does token need renewal?

### Alerts

Set up alerts for:
- API returns 401 (token expired)
- API returns 500 (server error)
- Brand creation fails >3 times in a row
- Billy reports "API unavailable"

## Troubleshooting

### Issue: "401 Unauthorized"

**Cause:** Invalid or expired token

**Fix:**
1. Get new token (see Prerequisites → Authentication Token)
2. Update `.env` with new token
3. Restart Billy gateway: `openclaw gateway restart`

### Issue: "403 Forbidden"

**Cause:** Token lacks platform admin permissions

**Fix:**
1. Contact Caio/tech team
2. Grant platform admin role to Billy's service account
3. Verify with: `curl -H "Authorization: Bearer $TOKEN" $URL/v1/brands`

### Issue: "DUPLICATE" error but brand doesn't exist

**Cause:** Brand was soft-deleted (deleted_at IS NOT NULL)

**Fix:**
1. Check database: `mysql -e "SELECT * FROM brands WHERE name = 'BrandName' AND deleted_at IS NOT NULL"`
2. Either hard-delete the old brand OR use a different name

### Issue: "Connection Error"

**Cause:** Network issue or API is down

**Fix:**
1. Verify API is reachable: `curl -I $USER_MGMT_API_URL/v1/brands`
2. Check firewall rules on Billy VM
3. Verify DNS resolves: `nslookup user-management-api.brandlovers.ai`

### Issue: Slug generation creates invalid slugs

**Cause:** Brand name has no alphanumeric characters (e.g., "🔥💎🔥")

**Fix:**
- Update `generate_slug()` function to handle edge cases
- Require at least 1 alphanumeric character in brand name

## Next Steps (Post-Deployment)

1. **Monitor for 1 week** - Track success rate, errors
2. **Gather feedback** - Ask team if they need improvements
3. **Phase 2: Logo upload** - Add logo support to skill
4. **Phase 3: Organization management** - Handle org creation too
5. **Phase 4: Bulk import** - Import brands from CSV

## Support Contacts

- **Caio Fonseca** (@caio.fonseca) - API owner, tech lead
- **Anton** - Orchestrator, skill maintainer
- **Linear Task:** CAI-75 (caio-tests workspace)

## Success Criteria

Deployment is successful when:

✅ Billy can create brands via Slack command  
✅ Duplicate detection prevents re-creating existing brands  
✅ API errors are handled gracefully  
✅ Team uses Billy instead of manual Slack requests  
✅ 0 manual brand creation requests in 30 days post-deployment
