#!/usr/bin/env python3
"""
Upload images to Slack DM using files.uploadV2 API

Usage:
    python slack_upload_image.py /path/to/image.png "Title" [channel_id]
    
Or as a library:
    from slack_upload_image import upload_to_slack
    upload_to_slack('/path/to/image.png', 'Title', channel_id='D04NQ9ZQTMM')
"""

import sys
import os
import json
import requests
from pathlib import Path

# Caio's Slack DM channel ID (retrieved via conversations.list API)
DEFAULT_CHANNEL_ID = "D04NQ9ZQTMM"
TOKEN = os.environ.get("SLACK_USER_TOKEN", "")


def upload_to_slack(file_path: str, title: str, channel_id: str = DEFAULT_CHANNEL_ID, token: str = TOKEN) -> dict:
    """
    Upload a file to Slack using the files.uploadV2 API (3-step process)
    
    Args:
        file_path: Path to the file to upload
        title: Title for the file in Slack
        channel_id: Slack channel ID (must start with C, G, D, or Z)
        token: Slack user token with files:write scope
        
    Returns:
        API response dict with 'ok' field indicating success
    """
    file_path = Path(file_path)
    if not file_path.exists():
        return {"ok": False, "error": f"File not found: {file_path}"}
    
    filename = file_path.name
    file_size = file_path.stat().st_size
    
    # Step 1: Get upload URL
    response = requests.post(
        "https://slack.com/api/files.getUploadURLExternal",
        headers={"Authorization": f"Bearer {token}"},
        data={"filename": filename, "length": file_size}
    )
    step1 = response.json()
    
    if not step1.get("ok"):
        return step1
    
    upload_url = step1["upload_url"]
    file_id = step1["file_id"]
    
    # Step 2: Upload file to the URL
    with open(file_path, "rb") as f:
        upload_response = requests.post(upload_url, files={"file": f})
    
    if upload_response.status_code != 200:
        return {"ok": False, "error": f"Upload failed: {upload_response.text}"}
    
    # Step 3: Complete the upload
    complete_response = requests.post(
        "https://slack.com/api/files.completeUploadExternal",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        },
        json={
            "files": [{"id": file_id, "title": title}],
            "channel_id": channel_id
        }
    )
    
    return complete_response.json()


def main():
    if len(sys.argv) < 3:
        print("Usage: slack_upload_image.py <file_path> <title> [channel_id]")
        sys.exit(1)
    
    file_path = sys.argv[1]
    title = sys.argv[2]
    channel_id = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_CHANNEL_ID
    
    result = upload_to_slack(file_path, title, channel_id)
    
    print(json.dumps(result, indent=2))
    
    if result.get("ok"):
        print(f"\n✅ SUCCESS: Uploaded {file_path}")
        sys.exit(0)
    else:
        print(f"\n❌ ERROR: {result.get('error', 'Unknown error')}")
        sys.exit(1)


if __name__ == "__main__":
    main()
