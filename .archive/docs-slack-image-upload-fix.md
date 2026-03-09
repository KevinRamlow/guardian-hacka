# Slack DM Image Upload - Debugging Report

## Problem
Couldn't send images to Slack DM. Two attempts failed:
1. **message tool with media parameter** - Failed (requires target channel)
2. **Slack files.upload API** - Failed with `method_deprecated` error

## Root Causes

### Issue 1: Wrong API Method
- `files.upload` is **deprecated** as of 2024
- Must use `files.uploadV2` (3-step process)

### Issue 2: Channel ID Required
- Cannot use user ID (U04PHF0L65P) directly in upload
- Must use DM channel ID that starts with D, C, G, or Z
- Caio's DM channel ID: **D04NQ9ZQTMM** (found via `conversations.list` API)

### Issue 3: Token Scopes
Token has:
- ✅ `files:write` - Can upload files
- ✅ `im:read` - Can list DM channels
- ❌ `im:write` - Cannot create NEW DM channels (but not needed if channel exists)

## Solution: files.uploadV2 API (3-Step Process)

### Step 1: Get Upload URL
```bash
curl -X POST https://slack.com/api/files.getUploadURLExternal \
  -H "Authorization: Bearer $TOKEN" \
  -d "filename=image.png" \
  -d "length=557087"
```
Returns: `upload_url` and `file_id`

### Step 2: Upload to URL
```bash
curl -X POST "$UPLOAD_URL" \
  -F file=@/path/to/image.png
```

### Step 3: Complete Upload
```bash
curl -X POST https://slack.com/api/files.completeUploadExternal \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "files": [{"id": "$FILE_ID", "title": "My Image"}],
    "channel_id": "D04NQ9ZQTMM"
  }'
```

## Working Code

### Python (Recommended)
```python
from scripts.slack_upload_image import upload_to_slack

result = upload_to_slack(
    '/path/to/image.png',
    'Image Title',
    channel_id='D04NQ9ZQTMM'  # Optional, defaults to Caio's DM
)
```

### Bash
```bash
/tmp/slack_upload_working.sh /path/to/image.png "Image Title"
```

### CLI
```bash
python /root/.openclaw/workspace/scripts/slack_upload_image.py \
    /path/to/image.png "Image Title"
```

## Verified Working
✅ All 4 Anton profile images successfully uploaded to Caio's DM:
- anton-1-minimalist.png (557 KB) → F0AKLE1RVMW
- anton-2-robot.png (840 KB) → F0AJVPT9CCU
- anton-3-circuit.png (1.0 MB) → F0AJNP2C86R
- anton-4-pixel.png (647 KB) → F0AKLE2T0N4

## Key Learnings
1. Always use `files.uploadV2` for new integrations
2. Channel ID format matters: Must be D/C/G/Z prefix
3. User IDs (U prefix) cannot be used as channels in file uploads
4. Get DM channel ID via: `conversations.list?types=im`
5. Token needs `files:write` but NOT `im:write` if channel already exists

## References
- Python script: `/root/.openclaw/workspace/scripts/slack_upload_image.py`
- Bash script: `/tmp/slack_upload_working.sh`
- Slack API: https://api.slack.com/methods/files.uploadV2
