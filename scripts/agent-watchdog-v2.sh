#!/bin/bash
# Agent Watchdog v2 — Monitors registry, detects completions/timeouts, kills orphans
# Runs every 60s via cron. Single source: agent-registry.json
# v2.1: Re-queues failed agents, validates output content, logs stderr
set -euo pipefail

REGISTRY="/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
REGISTRY_FILE="/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
LOCKFILE="/tmp/agent-watchdog-v2.lock"

mkdir -p /Users/fonsecabc/.openclaw/tasks/agent-logs

exec 200>"$LOCKFILE"
flock -n 200 || { echo "Skipped: locked"; exit 0; }

bash "$REGISTRY" list > /dev/null 2>&1

# Source Linear API key for re-queue and Slack token for alerts
source /Users/fonsecabc/.openclaw/workspace/.env.linear 2>/dev/null || true
source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time, subprocess, re

REGISTRY_FILE = "/Users/fonsecabc/.openclaw/tasks/agent-registry.json"
LOGGER = "/Users/fonsecabc/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG = "/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
REGISTRY = "/Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh"
LOGS_DIR = "/Users/fonsecabc/.openclaw/tasks/agent-logs"
DETECT_IDLE = "/Users/fonsecabc/.openclaw/workspace/scripts/detect-agent-idle.sh"
KILL_TREE = "/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
CONSECUTIVE_FAILURES_FILE = "/Users/fonsecabc/.openclaw/tasks/consecutive-failures.json"
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
CAIO_SLACK_ID = "U04PHF0L65P"
CONSECUTIVE_FAILURE_THRESHOLD = 3

# Minimum output size to count as real work (not just an error message)
MIN_OUTPUT_BYTES = 100

# Patterns that indicate a failed agent even with output
FAILURE_PATTERNS = [
    r"permission.*denied",
    r"not allowed",
    r"blocked",
    r"I need.*approval",
    r"I'm unable to",
    r"I cannot",
    r"access denied",
    r"authentication.*failed",
    r"EACCES",
    r"API Error",
    r"usage limits",
    r"rate limit",
    r"quota exceeded",
    r"billing",
    r"invalid_request_error",
]

def load_consecutive_failures():
    """Load the consecutive failure state."""
    try:
        with open(CONSECUTIVE_FAILURES_FILE) as f:
            return json.load(f)
    except Exception:
        return {"count": 0, "task_ids": []}


def save_consecutive_failures(state):
    """Persist the consecutive failure state."""
    with open(CONSECUTIVE_FAILURES_FILE, "w") as f:
        json.dump(state, f)


def send_failure_alert(state):
    """Send Slack DM to Caio when consecutive failures exceed threshold."""
    token = SLACK_BOT_TOKEN
    if not token:
        print("ALERT: No SLACK_BOT_TOKEN — cannot send consecutive failure alert")
        return

    count = state["count"]
    task_ids = state["task_ids"]
    task_list = ", ".join(task_ids[-10:])  # last 10 at most

    # Try to detect common error pattern from recent failure logs
    error_snippets = []
    for tid in task_ids[-4:]:
        for suffix in ["-stderr.log", "-output.log"]:
            log_path = f"{LOGS_DIR}/{tid}{suffix}"
            if os.path.exists(log_path):
                try:
                    with open(log_path) as f:
                        snippet = f.read(300).strip()
                    if snippet:
                        error_snippets.append(snippet)
                        break
                except Exception:
                    pass

    common_pattern = ""
    if error_snippets:
        # Simple heuristic: find the most common line across snippets
        lines = []
        for s in error_snippets:
            lines.extend([l.strip() for l in s.split("\n") if l.strip()])
        from collections import Counter
        common = Counter(lines).most_common(1)
        if common and common[0][1] > 1:
            common_pattern = f"\n*Common pattern:* `{common[0][0][:150]}`"

    msg = (
        f":rotating_light: *{count} consecutive agent failures detected*\n"
        f"*Failed tasks:* {task_list}\n"
        f"This may indicate a systemic issue (infra, permissions, resource exhaustion)."
        f"{common_pattern}\n"
        f"Check logs: `/Users/fonsecabc/.openclaw/tasks/agent-logs/`"
    )

    # Open DM channel with Caio and send alert
    try:
        # Open conversation
        r = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://slack.com/api/conversations.open",
             "-H", f"Authorization: Bearer {token}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"users": CAIO_SLACK_ID})],
            capture_output=True, text=True, timeout=10
        )
        dm_data = json.loads(r.stdout)
        dm_channel = dm_data.get("channel", {}).get("id")
        if not dm_channel:
            print(f"ALERT: Could not open DM channel: {r.stdout[:200]}")
            return

        # Send message
        r2 = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
             "-H", f"Authorization: Bearer {token}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"channel": dm_channel, "text": msg, "mrkdwn": True})],
            capture_output=True, text=True, timeout=10
        )
        resp = json.loads(r2.stdout)
        if resp.get("ok"):
            print(f"ALERT SENT: {count} consecutive failures → Slack DM to Caio")
        else:
            print(f"ALERT FAILED: {r2.stdout[:200]}")
    except Exception as e:
        print(f"ALERT ERROR: {e}")


now = int(time.time())
ts = time.strftime("%H:%M", time.gmtime())
consec_state = load_consecutive_failures()

try:
    d = json.load(open(REGISTRY_FILE))
except Exception:
    d = {"agents": {}, "maxConcurrent": 3}

agents = dict(d.get("agents", {}))
removals = []
completions = timeouts = failures = requeued = 0

# Proactively extend timeouts for active agents near deadline (defense in depth)
try:
    subprocess.run(["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/monitor-extend-timeouts.sh"], capture_output=True, timeout=10)
except Exception:
    pass

def requeue_task(task_id):
    """Move task back to Todo in Linear for retry."""
    global requeued
    if not LINEAR_API_KEY:
        return
    try:
        # Get the issue by identifier
        query = f'{{issues(filter:{{identifier:{{eq:"{task_id}"}}}},first:1){{nodes{{id}}}}}}'
        result = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": query})],
            capture_output=True, text=True, timeout=10
        )
        data = json.loads(result.stdout)
        nodes = data.get("data", {}).get("issues", {}).get("nodes", [])
        if not nodes:
            return

        issue_id = nodes[0]["id"]

        # Get Todo state ID
        state_query = '{workflowStates(filter:{name:{eq:"Todo"},team:{key:{eq:"AUT"}}},first:1){nodes{id}}}'
        result2 = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": state_query})],
            capture_output=True, text=True, timeout=10
        )
        data2 = json.loads(result2.stdout)
        state_nodes = data2.get("data", {}).get("workflowStates", {}).get("nodes", [])
        if not state_nodes:
            return

        state_id = state_nodes[0]["id"]

        # Update issue to Todo
        mutation = f'mutation{{issueUpdate(id:"{issue_id}",input:{{stateId:"{state_id}"}}){{success}}}}'
        subprocess.run(
            ["curl", "-s", "-X", "POST", "https://api.linear.app/graphql",
             "-H", f"Authorization: {LINEAR_API_KEY}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"query": mutation})],
            capture_output=True, text=True, timeout=10
        )
        requeued += 1
        print(f"  REQUEUED {task_id} → Todo")
    except Exception as e:
        print(f"  REQUEUE FAILED {task_id}: {e}")


def check_output_quality(task_id):
    """Check if agent output represents real work or a failure."""
    output_log = f"{LOGS_DIR}/{task_id}-output.log"
    stderr_log = f"{LOGS_DIR}/{task_id}-stderr.log"

    output_size = os.path.getsize(output_log) if os.path.exists(output_log) else 0
    stderr_size = os.path.getsize(stderr_log) if os.path.exists(stderr_log) else 0

    # No output at all = definite failure
    if output_size < 2:
        stderr_msg = ""
        if stderr_size > 0:
            try:
                with open(stderr_log) as f:
                    stderr_msg = f.read(500)
            except:
                pass
        return "empty", output_size, stderr_msg

    # Small output = likely just an error message
    if output_size < MIN_OUTPUT_BYTES:
        try:
            with open(output_log) as f:
                content = f.read()
            for pattern in FAILURE_PATTERNS:
                if re.search(pattern, content, re.IGNORECASE):
                    return "blocked", output_size, f"Pattern match: {pattern}"
        except:
            pass
        return "small", output_size, ""

    # Larger output but check for failure patterns in first 500 bytes
    try:
        with open(output_log) as f:
            head = f.read(500)
        for pattern in FAILURE_PATTERNS:
            if re.search(pattern, head, re.IGNORECASE):
                return "blocked", output_size, f"Pattern match: {pattern}"
    except:
        pass

    return "success", output_size, ""


for task_id, a in agents.items():
    pid = a.get("pid", 0)
    timeout_min = a.get("timeoutMin", 25)
    age_min = (now - a.get("spawnedEpoch", now)) // 60
    label = a.get("label", task_id)
    retries = a.get("retries", 0)

    try:
        os.kill(pid, 0)
        alive = True
    except (OSError, ProcessLookupError):
        alive = False

    if not alive:
        status, output_size, detail = check_output_quality(task_id)

        REPORT = "/Users/fonsecabc/.openclaw/workspace/scripts/agent-report.sh"

        if status in ("success", "small"):
            print(f"DONE {task_id}: {age_min}min, {output_size}B output")
            # Unified report: reads logs, posts to Linear + Slack atomically
            subprocess.run(["bash", REPORT, task_id, "done"], capture_output=True, timeout=30)
            completions += 1
            consec_state = {"count": 0, "task_ids": []}

        else:
            # Empty or blocked — FAIL
            fail_reason = f"output={output_size}B"
            if detail:
                fail_reason += f" ({detail[:200]})"

            print(f"[FAIL] {task_id}: {age_min}min, {fail_reason}")
            # Unified report: reads logs, diagnoses error, posts to Linear + Slack atomically
            subprocess.run(["bash", REPORT, task_id, "failed"], capture_output=True, timeout=30)
            failures += 1

            consec_state["count"] += 1
            consec_state["task_ids"].append(task_id)

            if consec_state["count"] > CONSECUTIVE_FAILURE_THRESHOLD:
                send_failure_alert(consec_state)

            if retries < 2:
                requeue_task(task_id)

        removals.append(task_id)
        continue

    if age_min >= timeout_min:
        print(f"TIMEOUT {task_id}: {age_min}min >= {timeout_min}min — killing PID {pid} and children")
        try:
            # Use kill-agent-tree.sh to kill entire process tree
            subprocess.run([
                "bash",
                "/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh",
                str(pid)
            ], capture_output=True, timeout=10)
        except Exception as e:
            print(f"  Error killing tree for {pid}: {e}")
            # Fallback: try direct kill
            try:
                os.kill(pid, 9)
            except Exception:
                pass

        # Unified report: reads logs, posts to Linear + Slack atomically
        subprocess.run(["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/agent-report.sh", task_id, "timeout"], capture_output=True, timeout=30)
        timeouts += 1

        # Track consecutive failures (timeouts count as failures)
        consec_state["count"] += 1
        consec_state["task_ids"].append(task_id)

        if consec_state["count"] > CONSECUTIVE_FAILURE_THRESHOLD:
            send_failure_alert(consec_state)

        # Re-queue timed out tasks too
        requeue_task(task_id)

        removals.append(task_id)
        continue

    # --- Idle Detection (only for agents >10min old to avoid false positives on setup) ---
    if age_min >= 10:
        try:
            idle_result = subprocess.run(
                ["bash", DETECT_IDLE, task_id],
                capture_output=True, text=True, timeout=15
            ).stdout.strip()
        except Exception as e:
            idle_result = "active"
            print(f"  IDLE_CHECK error for {task_id}: {e}")

        if idle_result in ("idle_no_output", "idle_no_activity", "loop_same_error"):
            print(f"IDLE {task_id}: {idle_result} at {age_min}min — killing PID {pid}")
            try:
                subprocess.run(["bash", KILL_TREE, str(pid)], capture_output=True, timeout=10)
            except Exception:
                try:
                    os.kill(pid, 9)
                except Exception:
                    pass
            subprocess.run(["bash", "/Users/fonsecabc/.openclaw/workspace/scripts/agent-report.sh", task_id, "idle_killed"], capture_output=True, timeout=30)
            failures += 1
            # Track consecutive failures
            consec_state["count"] += 1
            consec_state["task_ids"].append(task_id)
            if consec_state["count"] > CONSECUTIVE_FAILURE_THRESHOLD:
                send_failure_alert(consec_state)
            requeue_task(task_id)
            removals.append(task_id)
            continue

    # --- Progress-Based Timeout Extension (max 2 extensions, +10min each) ---
    extensions = a.get("extensions", 0)
    if extensions < 2 and age_min >= timeout_min - 2:
        activity_log = f"{LOGS_DIR}/{task_id}-activity.jsonl"
        making_progress = False
        if os.path.exists(activity_log):
            activity_age = now - os.path.getmtime(activity_log)
            making_progress = activity_age < 120  # event in last 2min
        if making_progress:
            new_timeout = timeout_min + 10
            try:
                reg_data = json.load(open(REGISTRY_FILE))
                if task_id in reg_data.get("agents", {}):
                    reg_data["agents"][task_id]["timeoutMin"] = new_timeout
                    reg_data["agents"][task_id]["extensions"] = extensions + 1
                    json.dump(reg_data, open(REGISTRY_FILE, "w"), indent=2)
                    print(f"EXTENDED {task_id}: {timeout_min} → {new_timeout}min (ext #{extensions+1}, active at {age_min}min)")
                    subprocess.run([LINEAR_LOG, task_id, f"[{ts}] Timeout extended: {timeout_min} → {new_timeout}min (still active at {age_min}min, ext #{extensions+1})", "progress"], capture_output=True)
                    timeout_min = new_timeout  # update local var for the OK print below
            except Exception as e:
                print(f"  EXTEND FAILED {task_id}: {e}")

    print(f"OK {task_id}: PID={pid} {age_min}/{timeout_min}min")

for task_id in removals:
    subprocess.run(["bash", REGISTRY, "remove", task_id], capture_output=True)

# Kill orphan claude processes not in registry (but spare gateway's main thread)
registered_pids = set()
try:
    d2 = json.load(open(REGISTRY_FILE))
    registered_pids = {a["pid"] for a in d2.get("agents", {}).values()}
except Exception:
    pass

orphans = 0
try:
    result = subprocess.run(["pgrep", "-x", "claude"], capture_output=True, text=True)
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            pid = int(line.strip())
            if pid in registered_pids:
                continue
            try:
                # Check if this is the gateway's main thread (PPID is openclaw-gateway)
                ppid_r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
                ppid = int(ppid_r.stdout.strip())
                # Check if parent is openclaw-gateway
                parent_r = subprocess.run(["ps", "-o", "comm=", "-p", str(ppid)], capture_output=True, text=True)
                if "openclaw" in parent_r.stdout.strip():
                    # This is the main Anton thread — DO NOT KILL
                    continue

                age_r = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], capture_output=True, text=True)
                if int(age_r.stdout.strip()) > 300:
                    # Use kill-agent-tree.sh for orphans too (they might have spawned children)
                    try:
                        subprocess.run([
                            "bash",
                            "/Users/fonsecabc/.openclaw/workspace/scripts/kill-agent-tree.sh",
                            str(pid)
                        ], capture_output=True, timeout=10)
                        print(f"ORPHAN killed (tree): PID={pid}")
                        orphans += 1
                    except Exception:
                        # Fallback
                        try:
                            os.kill(pid, 9)
                            print(f"ORPHAN killed: PID={pid}")
                            orphans += 1
                        except Exception:
                            pass
            except Exception:
                pass
except Exception:
    pass

# Clean stale session store
try:
    sf = "/Users/fonsecabc/.openclaw/agents/claude/sessions/sessions.json"
    sessions = json.load(open(sf))
    cutoff = now * 1000 - 1800000
    cleaned = {k: v for k, v in sessions.items() if v.get("updatedAt", 0) > cutoff}
    if len(cleaned) < len(sessions):
        json.dump(cleaned, open(sf, "w"))
except Exception:
    pass

# Persist consecutive failure state
save_consecutive_failures(consec_state)

# Summary
alive = 0
try:
    alive = len(json.load(open(REGISTRY_FILE)).get("agents", {}))
except Exception:
    pass

print(f"\n=== Watchdog: running={alive} done={completions} failed={failures} timeout={timeouts} requeued={requeued} orphans={orphans} consec_fail={consec_state['count']} ===")

# ── Health Metrics ─────────────────────────────────────────────────────────────
import glob, re
from datetime import datetime, timezone, timedelta
from collections import defaultdict

METRICS_FILE = "/Users/fonsecabc/.openclaw/workspace/metrics/agent-health.json"
BUDGET_FILE  = "/Users/fonsecabc/.openclaw/workspace/self-improvement/loop/budget-status.json"
ALERT_COOLDOWN_FILE = "/Users/fonsecabc/.openclaw/workspace/metrics/alert-cooldown.json"
LOGS_DIR2    = "/Users/fonsecabc/.openclaw/tasks/agent-logs"
SUCCESS_RATE_ALERT_THRESHOLD = 70.0
ALERT_COOLDOWN_HOURS = 1  # Only alert once per hour for same issue

os.makedirs("/Users/fonsecabc/.openclaw/workspace/metrics", exist_ok=True)

def should_send_alert(alert_type):
    """Check if enough time has passed since last alert of this type."""
    try:
        if os.path.exists(ALERT_COOLDOWN_FILE):
            cooldowns = json.load(open(ALERT_COOLDOWN_FILE))
        else:
            cooldowns = {}
        
        last_alert_epoch = cooldowns.get(alert_type, 0)
        now_epoch = int(time.time())
        hours_since = (now_epoch - last_alert_epoch) / 3600
        
        if hours_since >= ALERT_COOLDOWN_HOURS:
            # Update cooldown file
            cooldowns[alert_type] = now_epoch
            json.dump(cooldowns, open(ALERT_COOLDOWN_FILE, "w"))
            return True
        else:
            return False
    except Exception:
        return True  # If cooldown check fails, allow the alert

def _parse_ts(s):
    """Parse log timestamp like '2026-03-07 15:30:23'."""
    try:
        return datetime.strptime(s, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except Exception:
        return None

def _task_type(label):
    """Extract rough task type from label or task_id."""
    label = label.lower()
    for kw in ["guardian","fix","feat","feature","analysis","monitor","resil","refactor","test","docs","sync","deploy"]:
        if kw in label:
            return kw
    return "other"

# Parse all per-task agent logs (CAI-NNN.log, not -output, not sub-runs)
task_logs = [
    f for f in glob.glob(f"{LOGS_DIR2}/CAI-*.log")
    if "-output" not in f and re.search(r"CAI-\d+\.log$", f)
]

# Rolling 7-day window
cutoff = datetime.now(timezone.utc) - timedelta(days=7)

tasks_by_date = defaultdict(lambda: {"completed": 0, "timeout": 0, "failed": 0, "durations": []})
tasks_by_type = defaultdict(lambda: {"completed": 0, "timeout": 0, "failed": 0, "durations": []})
all_durations = []
total_completed = total_timeout = total_failed = total_unknown = 0

# Track peak concurrent: collect (spawn_epoch, end_epoch) intervals
concurrent_windows = []

for fpath in sorted(task_logs):
    lines = open(fpath).readlines()
    status = "unknown"
    duration_min = None
    spawn_dt = None
    label = os.path.basename(fpath).replace(".log", "")
    ttype = _task_type(label)
    log_date = None

    for line in lines:
        # Extract spawn time
        if "[spawn]" in line:
            m = re.search(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
            if m:
                spawn_dt = _parse_ts(m.group(1))
                log_date = m.group(1)[:10]
            # Try to extract full label from spawn line
            m2 = re.search(r"Agent spawned: (\S+)", line)
            if m2:
                label = m2.group(1)
                ttype = _task_type(label)

        # Also check progress lines for label
        if "[progress]" in line and "Agent spawned:" in line:
            m2 = re.search(r"Agent spawned: (\S+)", line)
            if m2:
                label = m2.group(1)
                ttype = _task_type(label)

        if "[complete]" in line and "Finished in" in line:
            m = re.search(r"Finished in (\d+)min", line)
            if m:
                duration_min = int(m.group(1))
            status = "completed"

        if "[timeout]" in line and "Timed out" in line:
            status = "timeout"

        if "[error]" in line:
            status = "failed"

    # Only count within 7-day window
    if spawn_dt and spawn_dt < cutoff:
        continue
    if log_date is None and status == "unknown":
        continue

    if log_date is None:
        # Fallback: use file mtime
        log_date = datetime.fromtimestamp(os.path.getmtime(fpath), tz=timezone.utc).strftime("%Y-%m-%d")

    if status == "completed":
        total_completed += 1
        tasks_by_date[log_date]["completed"] += 1
        tasks_by_type[ttype]["completed"] += 1
        if duration_min:
            all_durations.append(duration_min)
            tasks_by_date[log_date]["durations"].append(duration_min)
            tasks_by_type[ttype]["durations"].append(duration_min)
            if spawn_dt:
                end_epoch = spawn_dt.timestamp() + duration_min * 60
                concurrent_windows.append((spawn_dt.timestamp(), end_epoch))
    elif status == "timeout":
        total_timeout += 1
        tasks_by_date[log_date]["timeout"] += 1
        tasks_by_type[ttype]["timeout"] += 1
    elif status == "failed":
        total_failed += 1
        tasks_by_date[log_date]["failed"] += 1
        tasks_by_type[ttype]["failed"] += 1
    else:
        total_unknown += 1

total = total_completed + total_timeout + total_failed + total_unknown
success_rate = round(total_completed / total * 100, 1) if total > 0 else 0.0
avg_duration = round(sum(all_durations) / len(all_durations), 1) if all_durations else 0.0

# Peak concurrent: sweep line over all intervals
peak_concurrent = alive  # at minimum the current count
if concurrent_windows:
    events = []
    for s, e in concurrent_windows:
        events.append((s, +1))
        events.append((e, -1))
    events.sort()
    cur = 0
    for _, delta in events:
        cur += delta
        if cur > peak_concurrent:
            peak_concurrent = cur

# Load cost data from budget-status.json
total_cost_usd = 0.0
try:
    bdata = json.load(open(BUDGET_FILE))
    total_cost_usd = round(bdata.get("monthly_spend", 0.0), 2)
except Exception:
    pass

# Build per-type summary
by_type_out = {}
for ttype, d in sorted(tasks_by_type.items()):
    t = d["completed"] + d["timeout"] + d["failed"]
    sr = round(d["completed"] / t * 100, 1) if t > 0 else 0.0
    by_type_out[ttype] = {
        "count": t,
        "completed": d["completed"],
        "timeout": d["timeout"],
        "failed": d["failed"],
        "success_rate_pct": sr,
        "avg_duration_min": round(sum(d["durations"]) / len(d["durations"]), 1) if d["durations"] else 0.0,
    }

# Build daily trend (last 7 days)
daily_trend = []
for date_str in sorted(tasks_by_date.keys()):
    d = tasks_by_date[date_str]
    t = d["completed"] + d["timeout"] + d["failed"]
    sr = round(d["completed"] / t * 100, 1) if t > 0 else 0.0
    avg_d = round(sum(d["durations"]) / len(d["durations"]), 1) if d["durations"] else 0.0
    daily_trend.append({
        "date": date_str,
        "completed": d["completed"],
        "timeout": d["timeout"],
        "failed": d["failed"],
        "success_rate_pct": sr,
        "avg_duration_min": avg_d,
    })

# Alerts list
alerts = []
# Only alert on low success rate if we have meaningful data:
# - At least 5 total agents in window (enough for statistical significance)
# - At least 1 completion attempt (not just all timeouts/unknowns)
# - Success rate below threshold
if total >= 5 and (total_completed + total_failed + total_timeout) >= 1 and success_rate < SUCCESS_RATE_ALERT_THRESHOLD:
    alerts.append({
        "level": "critical",
        "type": "low_success_rate",
        "message": f"Success rate {success_rate}% is below threshold {SUCCESS_RATE_ALERT_THRESHOLD}%",
        "value": success_rate,
        "threshold": SUCCESS_RATE_ALERT_THRESHOLD,
    })

metrics = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "generated_epoch": int(time.time()),
    "window_days": 7,
    "summary": {
        "total_agents": total,
        "completed": total_completed,
        "timeouts": total_timeout,
        "failed": total_failed,
        "unknown": total_unknown,
        "success_rate_pct": success_rate,
        "avg_duration_min": avg_duration,
        "peak_concurrent": peak_concurrent,
        "total_cost_usd": total_cost_usd,
    },
    "by_task_type": by_type_out,
    "daily_trend": daily_trend,
    "alerts": alerts,
}

json.dump(metrics, open(METRICS_FILE, "w"), indent=2)

# Daily summary line (always print so cron captures it)
print(f"\n--- Health Metrics (7d) ---")
print(f"  Agents: {total} total | completed={total_completed} timeout={total_timeout} failed={total_failed}")
print(f"  Success rate: {success_rate}% | avg duration: {avg_duration}min | peak concurrent: {peak_concurrent}")
print(f"  Total cost (month): ${total_cost_usd}")
if alerts:
    for a in alerts:
        print(f"  !! ALERT [{a['level'].upper()}]: {a['message']}")
else:
    print(f"  Health: OK")
print(f"  Metrics: {METRICS_FILE}")

# Slack alert if success rate below threshold (with cooldown)
if alerts and SLACK_BOT_TOKEN:
    for a in alerts:
        if a["type"] == "low_success_rate" and should_send_alert("low_success_rate"):
            try:
                r = subprocess.run(
                    ["curl", "-s", "-X", "POST", "https://slack.com/api/conversations.open",
                     "-H", f"Authorization: Bearer {SLACK_BOT_TOKEN}",
                     "-H", "Content-Type: application/json",
                     "-d", json.dumps({"users": CAIO_SLACK_ID})],
                    capture_output=True, text=True, timeout=10
                )
                dm_data = json.loads(r.stdout)
                dm_channel = dm_data.get("channel", {}).get("id")
                if dm_channel:
                    msg = (f":warning: *Agent health alert*\n"
                           f"Success rate dropped to *{success_rate}%* (threshold: {SUCCESS_RATE_ALERT_THRESHOLD}%)\n"
                           f"7d window: {total_completed} completed, {total_timeout} timeout, {total_failed} failed\n"
                           f"Check logs: `{LOGS_DIR2}/`")
                    subprocess.run(
                        ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
                         "-H", f"Authorization: Bearer {SLACK_BOT_TOKEN}",
                         "-H", "Content-Type: application/json",
                         "-d", json.dumps({"channel": dm_channel, "text": msg, "mrkdwn": True})],
                        capture_output=True, text=True, timeout=10
                    )
                    print(f"  Health alert sent to Slack")
            except Exception as e:
                print(f"  Health alert Slack error: {e}")

PYEOF
