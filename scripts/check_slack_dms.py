#!/usr/bin/env python3
"""
Check Slack DMs for new messages since last check.
Requires SLACK_USER_TOKEN environment variable.
"""

import os
import sys
import json
import time
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timezone

SLACK_API_URL = "https://slack.com/api"
STATE_FILE = "/root/.openclaw/workspace/memory/slack-dm-state.json"
TIMEOUT = 10  # seconds

class SlackChecker:
    def __init__(self, token: str):
        self.token = token
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    def _request(self, endpoint: str, params: dict = None):
        """Make a Slack API request."""
        url = f"{SLACK_API_URL}/{endpoint}"
        if params:
            query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
            url = f"{url}?{query}"
        
        req = urllib.request.Request(url, headers=self.headers)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
                data = json.loads(response.read().decode('utf-8'))
                if not data.get('ok'):
                    raise Exception(f"Slack API error: {data.get('error', 'unknown')}")
                return data
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else str(e)
            raise Exception(f"HTTP {e.code}: {error_body}")
        except Exception as e:
            raise Exception(f"Request error: {e}")
    
    def get_dm_conversations(self, limit=20):
        """Get list of DM conversations."""
        data = self._request("conversations.list", {
            "types": "im",
            "exclude_archived": "true",
            "limit": limit
        })
        return data.get('channels', [])
    
    def get_conversation_history(self, channel_id: str, oldest: str = None, limit: int = 20):
        """Get messages from a conversation."""
        params = {
            "channel": channel_id,
            "limit": limit
        }
        if oldest:
            params["oldest"] = oldest
        
        data = self._request("conversations.history", params)
        return data.get('messages', [])
    
    def get_user_info(self, user_id: str):
        """Get user information."""
        try:
            data = self._request("users.info", {"user": user_id})
            return data.get('user', {})
        except Exception:
            return {"id": user_id, "name": user_id}
    
    def get_auth_test(self):
        """Get current user info."""
        return self._request("auth.test")

def load_state():
    """Load last check state."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_state(state):
    """Save check state."""
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not save state: {e}", file=sys.stderr)

def format_message(msg, user_name):
    """Format a message for display."""
    try:
        timestamp = datetime.fromtimestamp(float(msg['ts']), tz=timezone.utc)
        time_str = timestamp.strftime("%Y-%m-%d %H:%M UTC")
    except Exception:
        time_str = msg.get('ts', 'unknown')
    
    text = msg.get('text', '')
    
    # Handle different message types
    if msg.get('subtype') == 'file_share':
        files = msg.get('files', [])
        file_names = [f.get('name', 'file') for f in files]
        text = f"[File: {', '.join(file_names)}] {text}"
    
    return {
        "from": user_name,
        "time": time_str,
        "text": text,
        "ts": msg['ts']
    }

def main():
    token = os.environ.get("SLACK_USER_TOKEN")
    if not token:
        print(json.dumps({"error": "SLACK_USER_TOKEN not set"}))
        sys.exit(1)
    
    try:
        slack = SlackChecker(token)
        
        # Get current user
        auth = slack.get_auth_test()
        current_user_id = auth['user_id']
        
        # Load state
        state = load_state()
        last_checks = state.get('lastChecks', {})
        
        # Get DM conversations (limit to 20 most recent)
        conversations = slack.get_dm_conversations(limit=20)
        
        new_messages = []
        now = time.time()
        
        # Only check first 10 conversations to avoid timeout
        for conv in conversations[:10]:
            channel_id = conv['id']
            user_id = conv['user']
            
            # Get last check timestamp for this conversation
            last_check = last_checks.get(channel_id, str(now - 86400))  # Default to 24h ago
            
            try:
                # Get recent messages (limit to 10)
                messages = slack.get_conversation_history(channel_id, oldest=last_check, limit=10)
                
                # Filter for messages not from current user
                incoming = [msg for msg in messages 
                           if msg.get('user') != current_user_id 
                           and float(msg['ts']) > float(last_check)]
                
                if incoming:
                    # Get user info
                    user_info = slack.get_user_info(user_id)
                    user_name = user_info.get('real_name') or user_info.get('name', user_id)
                    
                    for msg in reversed(incoming):  # Oldest first
                        formatted = format_message(msg, user_name)
                        formatted['channel_id'] = channel_id
                        new_messages.append(formatted)
                
                # Update last check for this conversation
                if messages:
                    last_checks[channel_id] = messages[0]['ts']
                else:
                    last_checks[channel_id] = str(now)
                    
            except Exception as e:
                # Skip this conversation if there's an error
                print(f"Warning: Could not check conversation {channel_id}: {e}", file=sys.stderr)
                continue
        
        # Save updated state
        state['lastChecks'] = last_checks
        state['lastCheckTime'] = now
        save_state(state)
        
        # Output results
        result = {
            "checked_at": datetime.fromtimestamp(now, tz=timezone.utc).isoformat(),
            "conversations_checked": len(conversations[:10]),
            "new_messages": new_messages,
            "count": len(new_messages)
        }
        
        print(json.dumps(result, indent=2))
        
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
