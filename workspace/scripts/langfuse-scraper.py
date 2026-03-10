#!/usr/bin/env python3
"""Langfuse session scraper — reads Anton's main thread session files and pushes traces.
Runs every 2min via cron. Tracks what was already sent via state file.
"""
import json
import os
import re
import sys
import time
from pathlib import Path

# Config from env
PK = os.environ.get("LANGFUSE_PUBLIC_KEY", "")
SK = os.environ.get("LANGFUSE_SECRET_KEY", "")
HOST = os.environ.get("LANGFUSE_BASE_URL", "https://us.cloud.langfuse.com")

if not PK or not SK:
    # Try loading from .env.secrets
    secrets = Path("" + os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw")) + "/workspace/.env.secrets")
    if secrets.exists():
        for line in secrets.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ[k.strip()] = v.strip()
        PK = os.environ.get("LANGFUSE_PUBLIC_KEY", "")
        SK = os.environ.get("LANGFUSE_SECRET_KEY", "")

if not PK or not SK:
    sys.exit(0)

import urllib.request
import base64

AUTH = base64.b64encode(f"{PK}:{SK}".encode()).decode()
STATE_FILE = Path("" + os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw")) + "/tasks/langfuse-state.json")
SESSIONS_DIR = Path("" + os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw")) + "/agents/main/sessions")


def post_langfuse(batch):
    data = json.dumps({"batch": batch}).encode()
    req = urllib.request.Request(
        f"{HOST}/api/public/ingestion",
        data=data,
        headers={
            "Authorization": f"Basic {AUTH}",
            "Content-Type": "application/json",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass


def gen_id():
    return f"oc-{int(time.time())}-{os.urandom(4).hex()}"


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))


def extract_task_id(text):
    m = re.search(r"\b(CAI-\d+)\b", str(text))
    return m.group(1) if m else None


def find_active_session():
    """Find the most recently modified session file."""
    if not SESSIONS_DIR.exists():
        return None
    jsonls = [f for f in SESSIONS_DIR.glob("*.jsonl") if not f.name.endswith(".deleted")]
    if not jsonls:
        return None
    return max(jsonls, key=lambda f: f.stat().st_mtime)


def parse_llm_events(path, offset):
    """Parse session JSONL from offset, extract LLM generation events."""
    events = []
    new_offset = offset

    with open(path) as f:
        f.seek(offset)
        while True:
            line = f.readline()
            if not line:
                break
            new_offset = f.tell()
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg = entry.get("message", {})
            role = msg.get("role", "")

            # Only interested in assistant messages (LLM outputs)
            if role != "assistant":
                continue

            usage = msg.get("usage", {})
            model = msg.get("model", "")
            if not model and not usage:
                continue

            # Extract text output
            output = ""
            tool_calls = []
            content = msg.get("content", [])
            if isinstance(content, list):
                for p in content:
                    if isinstance(p, dict):
                        if p.get("type") == "text":
                            output += p.get("text", "")
                        elif p.get("type") == "toolCall":
                            tool_calls.append(p.get("toolName", p.get("name", "unknown")))

            events.append({
                "model": model,
                "usage": usage,
                "output": output[:1000],
                "tools": tool_calls,
                "timestamp": entry.get("timestamp", ""),
                "stop_reason": msg.get("stopReason", ""),
            })

    return events, new_offset


def main():
    session_path = find_active_session()
    if not session_path:
        return

    session_id = session_path.stem
    state = load_state()
    offset = state.get(session_id, 0)

    # Check if file has grown
    file_size = session_path.stat().st_size
    if file_size <= offset:
        return

    events, new_offset = parse_llm_events(session_path, offset)
    if not events:
        state[session_id] = new_offset
        save_state(state)
        return

    # Create/reuse trace for this session
    trace_id = state.get(f"{session_id}_trace")
    if not trace_id:
        trace_id = gen_id()
        state[f"{session_id}_trace"] = trace_id
        post_langfuse([{
            "id": gen_id(),
            "type": "trace-create",
            "timestamp": events[0].get("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
            "body": {
                "id": trace_id,
                "name": f"anton:main",
                "sessionId": session_id,
                "tags": ["anton-main", "gateway"],
            },
        }])

    # Send generation events
    batch = []
    for evt in events:
        model = evt["model"] or "claude-sonnet-4-5"
        usage = evt["usage"]
        cost = usage.get("cost", {})

        gen_event = {
            "id": gen_id(),
            "type": "generation-create",
            "timestamp": evt.get("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
            "body": {
                "id": gen_id(),
                "traceId": trace_id,
                "name": model.split("/")[-1] if "/" in model else model,
                "model": model,
                "output": evt["output"][:500] if evt["output"] else None,
                "usage": {
                    "input": usage.get("input", 0),
                    "output": usage.get("output", 0),
                    "total": usage.get("totalTokens", 0),
                    "unit": "TOKENS",
                },
                "metadata": {
                    "stop_reason": evt["stop_reason"],
                    "tool_calls": evt["tools"],
                    "cache_read": usage.get("cacheRead", 0),
                    "cost_total": cost.get("total") if isinstance(cost, dict) else None,
                },
            },
        }
        batch.append(gen_event)

        # Add tool spans
        for tool_name in evt["tools"]:
            batch.append({
                "id": gen_id(),
                "type": "span-create",
                "timestamp": evt.get("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
                "body": {
                    "id": gen_id(),
                    "traceId": trace_id,
                    "name": f"tool:{tool_name}",
                },
            })

    if batch:
        # Send in chunks of 20
        for i in range(0, len(batch), 20):
            post_langfuse(batch[i:i+20])

    state[session_id] = new_offset
    save_state(state)


if __name__ == "__main__":
    main()
