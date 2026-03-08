#!/bin/bash
# Capture agent transcript to persistent log
# Usage: capture-agent-transcript.sh <label>
# Reads the agent's session transcript and saves to agent-logs/
set -euo pipefail

LABEL="${1:-}"
[ -z "$LABEL" ] && exit 0

LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
SESSIONS_DIR="/Users/fonsecabc/.openclaw/agents/claude/sessions"
mkdir -p "$LOGS_DIR"

# Find session by label in sessions.json
python3 << PYEOF
import json, os, glob

label = "$LABEL"
logs_dir = "$LOGS_DIR"
sessions_dir = "$SESSIONS_DIR"

# Find session key for this label
store = json.load(open(f"{sessions_dir}/sessions.json"))
session_id = None
for key, s in store.items():
    if s.get("label") == label:
        session_id = s.get("sessionId")
        break

if not session_id:
    print(f"No session found for label: {label}")
    exit(0)

# Find transcript file
transcript = f"{sessions_dir}/{session_id}.jsonl"
if not os.path.exists(transcript):
    print(f"No transcript at: {transcript}")
    exit(0)

# Extract assistant messages (the actual work)
output_file = f"{logs_dir}/{label}-transcript.md"
with open(output_file, "w") as out:
    out.write(f"# Agent Transcript: {label}\n")
    out.write(f"# Session: {session_id}\n\n")
    
    with open(transcript) as f:
        for line in f:
            try:
                msg = json.loads(line)
                role = msg.get("role", "")
                content = msg.get("content", "")
                if isinstance(content, list):
                    content = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
                if role == "assistant" and content:
                    out.write(f"## Assistant\n{content[:2000]}\n\n")
                elif role == "user" and content and len(content) < 500:
                    out.write(f"## User\n{content[:500]}\n\n")
            except:
                pass

size = os.path.getsize(output_file)
print(f"Saved: {output_file} ({size} bytes)")
PYEOF
