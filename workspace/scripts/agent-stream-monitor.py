#!/usr/bin/env python3
"""Agent Stream Monitor — Real-time activity tracker with live Linear + Slack updates.

Reads claude --output-format stream-json from stdin, writes:
  - <task-id>-output.log    — final assistant text
  - <task-id>-activity.jsonl — all events (tool calls, results, errors)
  - <task-id>-stderr.log    — errors

Posts progress updates to Linear + Slack every REPORT_INTERVAL_SEC or REPORT_INTERVAL_TOOLS.

Usage: claude --print --output-format stream-json ... | python3 agent-stream-monitor.py <task-id>
"""
import json
import os
import subprocess
import sys
import time

if len(sys.argv) < 2:
    print("Usage: agent-stream-monitor.py <task-id>", file=sys.stderr)
    sys.exit(1)

TASK_ID = sys.argv[1]
LOGS_DIR = os.environ.get("LOGS_DIR", "" + os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw")) + "/tasks/agent-logs")
WORKSPACE = "" + os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw")) + "/workspace"

# Report interval: post progress every N seconds or N tool calls (whichever comes first)
REPORT_INTERVAL_SEC = 120   # every 2 minutes
REPORT_TOOL_INTERVAL = 8    # or every 8 tool calls

output_path = os.path.join(LOGS_DIR, f"{TASK_ID}-output.log")
activity_path = os.path.join(LOGS_DIR, f"{TASK_ID}-activity.jsonl")
stderr_path = os.path.join(LOGS_DIR, f"{TASK_ID}-stderr.log")

os.makedirs(LOGS_DIR, exist_ok=True)

# Load secrets for reporting
secrets = {}
for env_file in [f"{WORKSPACE}/.env.secrets", f"{WORKSPACE}/.env.linear"]:
    try:
        for line in open(env_file):
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.replace("export ", "").strip()
            secrets[k] = v.strip()
    except FileNotFoundError:
        pass

LINEAR_API_KEY = secrets.get("LINEAR_API_KEY", "")
SLACK_BOT_TOKEN = secrets.get("SLACK_BOT_TOKEN", "")
CAIO_DM = "D0AK1B981QR"
LINEAR_SCRIPT = f"{WORKSPACE}/skills/linear/scripts/linear.sh"


def post_progress(tools_so_far, errors_so_far, elapsed_min, last_tool):
    """Post a progress chunk to Linear + Slack."""
    ts = time.strftime("%H:%M:%S")
    msg = f"[{ts}] Progress: {len(tools_so_far)} tool calls, {errors_so_far} errors, {elapsed_min}min elapsed"
    if last_tool:
        msg += f"\nLast: {last_tool}"
    # Recent unique tools
    recent = list(dict.fromkeys(tools_so_far[-10:]))
    if recent:
        msg += f"\nTools: {', '.join(recent)}"

    # Linear comment (non-blocking)
    if LINEAR_API_KEY:
        try:
            subprocess.Popen(
                ["bash", LINEAR_SCRIPT, TASK_ID, msg],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                env={**os.environ, "LINEAR_API_KEY": LINEAR_API_KEY}
            )
        except Exception:
            pass

    # Slack message (non-blocking)
    if SLACK_BOT_TOKEN:
        try:
            safe = msg.replace('"', '\\"').replace("\n", "\\n")
            subprocess.Popen(
                ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
                 "-H", f"Authorization: Bearer {SLACK_BOT_TOKEN}",
                 "-H", "Content-Type: application/json",
                 "-d", json.dumps({"channel": CAIO_DM, "text": f":gear: *{TASK_ID}* {msg}", "mrkdwn": True})],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


# --- State ---
tools_used = []
error_count = 0
tool_count_since_report = 0
last_report_time = time.time()
start_time = time.time()
last_tool_name = ""

with open(activity_path, "w") as activity_f, \
     open(output_path, "w") as output_f, \
     open(stderr_path, "w") as stderr_f:

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            output_f.write(line + "\n")
            output_f.flush()
            continue

        ts = time.strftime("%H:%M:%S")
        event["_ts"] = ts
        activity_f.write(json.dumps(event) + "\n")
        activity_f.flush()

        event_type = event.get("type", "")
        msg = event.get("message", {}) if isinstance(event.get("message"), dict) else {}
        role = msg.get("role", "")
        content = msg.get("content", "")

        # --- Track tool calls ---
        if event_type == "content_block_start":
            block = event.get("content_block", {})
            if block.get("type") == "tool_use":
                tool_name = block.get("name", "unknown")
                tools_used.append(tool_name)
                last_tool_name = tool_name
                tool_count_since_report += 1
                activity_f.write(json.dumps({"_ts": ts, "_summary": f"TOOL_START: {tool_name}"}) + "\n")
                activity_f.flush()

        elif event_type == "message_start":
            model = event.get("message", {}).get("model", "")
            if model:
                activity_f.write(json.dumps({"_ts": ts, "_summary": f"MODEL: {model}"}) + "\n")
                activity_f.flush()

        elif event_type == "result":
            result_text = event.get("result", "")
            if result_text:
                output_f.write(result_text)
                output_f.flush()

            usage = event.get("usage", {})
            cost = event.get("cost", {})
            if usage or cost:
                activity_f.write(json.dumps({
                    "_ts": ts, "_summary": "DONE",
                    "usage": usage, "cost": cost,
                    "duration_ms": event.get("duration_ms"),
                    "session_id": event.get("session_id"),
                }) + "\n")
                activity_f.flush()

        elif event_type == "error":
            error_msg = event.get("error", {}).get("message", str(event.get("error", "")))
            error_count += 1
            stderr_f.write(f"[{ts}] ERROR: {error_msg}\n")
            stderr_f.flush()
            activity_f.write(json.dumps({"_ts": ts, "_summary": f"ERROR: {error_msg}"}) + "\n")
            activity_f.flush()

        # --- Track assistant text ---
        if role == "assistant" and isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    text = part.get("text", "")
                    if text:
                        pass  # output captured via "result" event

        # --- Track tool results ---
        if role == "tool" or event_type == "tool_result":
            tool_content = msg.get("content", event.get("content", ""))
            if isinstance(tool_content, str) and len(tool_content) > 0:
                short = tool_content[:200]
                activity_f.write(json.dumps({"_ts": ts, "_summary": f"TOOL_RESULT: {short}"}) + "\n")
                activity_f.flush()

        # --- Periodic progress report ---
        now = time.time()
        elapsed_min = int((now - start_time) / 60)
        time_since_report = now - last_report_time

        should_report = (
            (time_since_report >= REPORT_INTERVAL_SEC and len(tools_used) > 0) or
            (tool_count_since_report >= REPORT_TOOL_INTERVAL)
        )

        if should_report:
            post_progress(tools_used, error_count, elapsed_min, last_tool_name)
            last_report_time = now
            tool_count_since_report = 0
