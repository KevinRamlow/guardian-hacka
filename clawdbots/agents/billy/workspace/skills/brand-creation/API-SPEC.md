# User Management API - Brand Creation Endpoint

**Service:** user-management-api  
**Version:** v1  
**Endpoint:** `POST /v1/brands`  
**Authentication:** Bearer token (platform admin role required)

## Endpoint Details

### Base URL

**Production:** `https://user-management-api.brandlovers.ai`  
**Staging:** `https://user-management-api-staging.brandlovers.ai` (if exists)  
**Local Dev:** `http://localhost:8080` (typical Go service port)

### Authentication

**Type:** Bearer token  
**Header:** `Authorization: Bearer <token>`  
**Required Role:** Platform Admin

**Middleware Chain:**
1. `AuthMiddleware` - Validates JWT token
2. `PlatformAdminMiddleware` - Checks user has admin role

**Source:** `user-management-api/internal/main/app/routes_v1.go:66`

```go
platformAdminBrands := api.Group("/brands")
platformAdminBrands.Use(am.Middleware(), pam.Middleware())
platformAdminBrands.POST("", brandController.Create)
```

## Request

### Method
`POST`

### Path
`/v1/brands`

### Headers
```http
Authorization: Bearer <token>
Content-Type: application/json
```

### Body Schema

```json
{
  "name": "string",                  // Required, min:1, max:100
  "brand_slug": "string",            // Required, min:1, max:150, alphanumeric only
  "description": "string",           // Optional, max:2048
  "defaultFeePercentage": 5,         // Required, int, 0-100
  "autoApproveGroups": false         // Required, boolean
}
```

### Field Validation

| Field | Type | Required | Validation | Notes |
|-------|------|----------|------------|-------|
| `name` | string | ✅ Yes | 1-100 chars | Brand display name |
| `brand_slug` | string | ✅ Yes | 1-150 chars, alphanumeric only | URL-safe identifier, must be unique |
| `description` | string | ❌ No | max 2048 chars | Brand description |
| `defaultFeePercentage` | integer | ✅ Yes | 0-100 | Platform fee percentage |
| `autoApproveGroups` | boolean | ✅ Yes | true/false | Auto-approve creator groups |

**Validation Rules (from DTO):**
```go
type CreateBrandRequest struct {
    Description          *string `json:"description" binding:"omitempty,max=2048"`
    Name                 string  `json:"name" binding:"required,min=1,max=100"`
    BrandSlug            string  `json:"brand_slug" binding:"required,min=1,max=150,alphanum"`
    DefaultFeePercentage int     `json:"defaultFeePercentage" binding:"required,min=0,max=100"`
    AutoApproveGroups    bool    `json:"autoApproveGroups"`
}
```

**Source:** `user-management-api/internal/domain/dto/brand/brand_dto.go:6-12`

### Example Request

```bash
curl -X POST https://user-management-api.brandlovers.ai/v1/brands \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nike",
    "brand_slug": "nike",
    "description": "Sportswear and athletic apparel brand",
    "defaultFeePercentage": 5,
    "autoApproveGroups": false
  }'
```

## Response

### Success (200 OK)

```json
{
  "id": 904,
  "name": "Nike",
  "brandSlug": "nike",
  "description": "Sportswear and athletic apparel brand",
  "logoUrl": "",
  "logoThumbUrl": null,
  "banner": null,
  "bannerThumbUrl": null,
  "cnpj": null,
  "companyName": null,
  "alwaysApplyTakeRate": null,
  "since": null,
  "createdAt": "2026-03-06T02:00:00Z",
  "balance": 0.0,
  "defaultFeePercentage": 5,
  "autoApproveGroups": false
}
```

**Response Schema:**
```go
type BrandResponse struct {
    Description          *string    `json:"description,omitempty"`
    LogoThumbURL         *string    `json:"logoThumbUrl,omitempty"`
    BannerURL            *string    `json:"banner,omitempty"`
    BannerThumbURL       *string    `json:"bannerThumbUrl,omitempty"`
    CNPJ                 *string    `json:"cnpj,omitempty"`
    CompanyName          *string    `json:"companyName,omitempty"`
    AlwaysApplyTakeRate  *bool      `json:"alwaysApplyTakeRate,omitempty"`
    Since                *time.Time `json:"since,omitempty"`
    CreatedAt            *time.Time `json:"createdAt,omitempty"`
    Name                 string     `json:"name"`
    BrandSlug            string     `json:"brandSlug,omitempty"`
    LogoURL              string     `json:"logoUrl,omitempty"`
    ID                   uint64     `json:"id"`
    Balance              float64    `json:"balance"`
    DefaultFeePercentage int        `json:"defaultFeePercentage"`
    AutoApproveGroups    bool       `json:"autoApproveGroups"`
}
```

**Source:** `user-management-api/internal/domain/dto/brand/brand_dto.go:44-62`

### Error Responses

#### 400 Bad Request - Invalid Input

```json
{
  "error": "invalid request",
  "message": "name is required"
}
```

**Common validation errors:**
- Missing required field (name, brand_slug, defaultFeePercentage)
- Field too long (name >100, description >2048, slug >150)
- Invalid characters in slug (non-alphanumeric)
- Fee percentage out of range (<0 or >100)

#### 401 Unauthorized - Missing/Invalid Token

```json
{
  "error": "unauthorized",
  "message": "invalid or missing token"
}
```

**Causes:**
- Authorization header missing
- Token format invalid (not `Bearer <token>`)
- Token expired
- Token signature invalid

#### 403 Forbidden - Insufficient Permissions

```json
{
  "error": "forbidden",
  "message": "insufficient permissions"
}
```

**Cause:**
- User authenticated but not platform admin
- Platform admin role check failed

#### 409 Conflict - Duplicate Slug

```json
{
  "error": "duplicate",
  "message": "brand with slug 'nike' already exists"
}
```

**Note:** The API enforces unique `brand_slug` constraint. Check for duplicates before creating.

#### 500 Internal Server Error

```json
{
  "error": "internal server error",
  "message": "failed to create brand"
}
```

**Causes:**
- Database connection failed
- Unexpected error in business logic
- Organization creation failed (brands require organizations)

## Related Endpoints

### List Brands
```http
GET /v1/brands?search=nike&perPage=10&page=1
Authorization: Bearer <token>
```

**Response:**
```json
{
  "data": [
    {
      "id": 904,
      "name": "Nike",
      "brandSlug": "nike",
      ...
    }
  ],
  "total": 1,
  "page": 1,
  "perPage": 10
}
```

### Get Brand by ID
```http
GET /v1/brands/:id
Authorization: Bearer <token>
```

**Response:** Same as BrandResponse

### Get Brand by Slug (Public)
```http
GET /v1/brands/slug/:slug
```

**Note:** No authentication required (public endpoint)

### Update Brand
```http
PUT /v1/brands/:id
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Nike Updated",
  "description": "New description",
  "logoUrl": "https://example.com/logo.png",
  "defaultFeePercentage": 10,
  "autoApproveGroups": true
}
```

### Delete Brand
```http
DELETE /v1/brands/:id
Authorization: Bearer <token>
```

**Response:** 204 No Content (soft delete, sets `deleted_at`)

### Upload Logo
```http
POST /v1/brands/:id/logo
Authorization: Bearer <token>
Content-Type: multipart/form-data

file=@logo.png
```

**Response:**
```json
{
  "id": 904,
  "name": "Nike",
  "logoUrl": "https://storage.googleapis.com/.../logo.png",
  "logoThumbUrl": "https://storage.googleapis.com/.../logo_thumb.png"
}
```

## Business Logic

### Brand Creation Flow

1. **Validate request** (DTO binding)
2. **Check authorization** (platform admin only)
3. **Create organization** (if not exists)
   - Organization name = Brand name
   - owner_id = Current user ID
4. **Create brand** (insert into brands table)
   - Links to organization via organization_id
   - Sets brand_slug (must be unique)
   - Initializes balance = 0.0
5. **Return brand data**

### Organization Relationship

**Every brand belongs to an organization:**
- 1 organization : N brands
- When creating a brand, an organization is auto-created OR linked to existing
- Organization owner = User who created the brand

**Database schema:**
```sql
CREATE TABLE organizations (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  owner_id INT NOT NULL,  -- FK to users
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL
);

CREATE TABLE brands (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  organization_id INT NOT NULL,  -- FK to organizations
  brand_slug VARCHAR(150) NOT NULL UNIQUE,
  description TEXT,
  logo TEXT,
  logo_thumb TEXT,
  banner TEXT,
  banner_thumb TEXT,
  cnpj VARCHAR(15),
  company_name VARCHAR(255),
  always_apply_take_rate TINYINT(1),
  brand_status_id INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  since TIMESTAMP NULL,
  UNIQUE KEY brand_slug (brand_slug)
);
```

## Security Considerations

### Token Security
- **Never log tokens** - Redact in logs
- **Rotate regularly** - Tokens should expire
- **Store securely** - Use environment variables, not git
- **Least privilege** - Only grant platform admin to services that need it

### Rate Limiting
- Recommend: 100 requests/minute per token
- Prevents abuse and accidental DOS

### Input Sanitization
- API handles validation (DTO binding)
- Billy should still validate inputs before calling API
- Prevent XSS by escaping user input in Slack responses

### Audit Trail
- All brand creations logged via API activity log
- Include: User ID, timestamp, brand details
- Searchable for compliance

## Testing

### Manual Testing (curl)

```bash
# Set token
TOKEN="your-bearer-token"
API="https://user-management-api.brandlovers.ai"

# Create brand
curl -X POST "$API/v1/brands" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Brand",
    "brand_slug": "test-brand",
    "description": "Testing brand creation",
    "defaultFeePercentage": 5,
    "autoApproveGroups": false
  }'

# Verify it exists
curl -H "Authorization: Bearer $TOKEN" \
  "$API/v1/brands?search=Test%20Brand"

# Clean up (delete)
BRAND_ID=905  # From create response
curl -X DELETE "$API/v1/brands/$BRAND_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### Integration Testing

```python
import requests

API_URL = "https://user-management-api.brandlovers.ai"
TOKEN = "your-bearer-token"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def test_create_brand():
    payload = {
        "name": "Test Brand",
        "brand_slug": "test-brand-unique",
        "description": "Test",
        "defaultFeePercentage": 5,
        "autoApproveGroups": False
    }
    
    response = requests.post(
        f"{API_URL}/v1/brands",
        headers=HEADERS,
        json=payload
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Test Brand"
    assert data["id"] > 0
    
    # Clean up
    requests.delete(
        f"{API_URL}/v1/brands/{data['id']}",
        headers=HEADERS
    )

test_create_brand()
print("✅ Test passed!")
```

## Source Code References

**Repository:** `brandlovers-team/user-management-api`

**Key Files:**
- Routes: `internal/main/app/routes_v1.go:66-70`
- Controller: `internal/presentation/controllers/brand_controller.go:55-70`
- DTO: `internal/domain/dto/brand/brand_dto.go:6-12`
- Use Case: `internal/domain/usecases/brand/create_brand_usecase.go`

**Clone Locally:**
```bash
cd /root/.openclaw/workspace
gh repo clone brandlovers-team/user-management-api -- --depth 1
```

## Support

**Questions?**
- Caio Fonseca (@caio.fonseca) - Tech lead
- Manoel Stilpen - API architect

**Report Issues:**
- GitHub: brandlovers-team/user-management-api
- Linear: GUA team (Guardian workspace)
