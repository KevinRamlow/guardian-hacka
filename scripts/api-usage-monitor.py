#!/usr/bin/env python3
"""API Usage Monitor — Tracks real Claude API spend from session files.

Scans all Claude Code session JSONL files, extracts token usage per LLM call,
calculates cost using model pricing, and alerts when approaching budget limits.

Runs via cron every 15 minutes. Sends Slack DM alert at 80% of monthly budget.

Usage:
  api-usage-monitor.py                # Full scan + alert check
  api-usage-monitor.py --dashboard    # Print dashboard to stdout
  api-usage-monitor.py --reset        # Reset monthly counters
"""

import json
import os
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime, timedelta, timezone
from collections import defaultdict

# --- Config ---
STATE_FILE = Path("/root/.openclaw/tasks/api-usage-state.json")
BUDGET_FILE = Path("/root/.openclaw/workspace/self-improvement/loop/budget-status.json")
MASTER_LOG = Path("/root/.openclaw/tasks/agent-logs/master.log")
SECRETS_FILE = Path("/root/.openclaw/workspace/.env.secrets")
SETTINGS_FILE = Path("/root/.claude/settings.json")

SESSION_DIRS = [
    Path("/root/.openclaw/agents/main/sessions"),
    Path("/root/.claude/projects/-root"),
    Path("/root/.claude/projects/-root--openclaw-workspace"),
    Path("/root/.claude/projects/-root--openclaw-workspace-guardian-agents-api"),
]

# Monthly budget in USD (configurable via budget-status.json)
DEFAULT_MONTHLY_BUDGET = 500.0
ALERT_THRESHOLD = 0.80  # Alert at 80%
CRITICAL_THRESHOLD = 0.95  # Critical at 95%

CAIO_SLACK_ID = "U04PHF0L65P"

# Model pricing per million tokens (USD)
MODEL_PRICING = {
    "claude-opus-4-6": {"input": 15.0, "output": 75.0, "cache_read": 1.50, "cache_write": 18.75},
    "claude-sonnet-4-6": {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    "claude-sonnet-4-5": {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75},
    "claude-haiku-4-5-20251001": {"input": 0.80, "output": 4.0, "cache_read": 0.08, "cache_write": 1.0},
}

# Fallback pricing for unknown models (use sonnet pricing)
DEFAULT_PRICING = {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cache_write": 3.75}


def load_env():
    """Load environment variables from secrets files."""
    for path in [SECRETS_FILE]:
        if path.exists():
            for line in path.read_text().splitlines():
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())
    # Also load from Claude settings
    if SETTINGS_FILE.exists():
        try:
            settings = json.loads(SETTINGS_FILE.read_text())
            for k, v in settings.get("env", {}).items():
                os.environ.setdefault(k, v)
        except Exception:
            pass


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {
            "session_offsets": {},
            "daily_costs": {},
            "monthly_total": 0.0,
            "last_alert_sent": None,
            "last_scan": None,
            "task_costs": {},
        }


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2, default=str))


def get_monthly_budget():
    try:
        budget = json.loads(BUDGET_FILE.read_text())
        return budget.get("monthly_limit", DEFAULT_MONTHLY_BUDGET)
    except Exception:
        return DEFAULT_MONTHLY_BUDGET


def get_pricing(model):
    """Get pricing for a model, with fallback."""
    for key, pricing in MODEL_PRICING.items():
        if key in (model or ""):
            return pricing
    return DEFAULT_PRICING


def calculate_cost(usage, model):
    """Calculate cost from usage dict and model name."""
    # If the session already has cost.total, use it
    cost = usage.get("cost", {})
    if isinstance(cost, dict) and cost.get("total"):
        return cost["total"]

    # Otherwise calculate from token counts
    pricing = get_pricing(model)
    input_tokens = usage.get("input", 0) or 0
    output_tokens = usage.get("output", 0) or 0
    cache_read = usage.get("cacheRead", 0) or 0
    cache_write = usage.get("cacheWrite", 0) or 0

    cost_usd = (
        input_tokens * pricing["input"] / 1_000_000
        + output_tokens * pricing["output"] / 1_000_000
        + cache_read * pricing["cache_read"] / 1_000_000
        + cache_write * pricing["cache_write"] / 1_000_000
    )
    return cost_usd


def extract_task_id(text):
    """Extract CAI-XXX task ID from text."""
    import re
    m = re.search(r"\b(CAI-\d+)\b", str(text))
    return m.group(1) if m else None


def build_session_task_map():
    """Build mapping from session files to task IDs using master log."""
    mapping = {}
    if not MASTER_LOG.exists():
        return mapping

    import re
    # Parse spawn entries from master log to map PID → task
    # Also check agent-registry for session mappings
    try:
        for line in MASTER_LOG.read_text().splitlines():
            task_id = extract_task_id(line)
            if task_id:
                # Try to find session ID in the line
                m = re.search(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", line)
                if m:
                    mapping[m.group(0)] = task_id
    except Exception:
        pass

    return mapping


def scan_sessions(state):
    """Scan all session JSONL files for new LLM usage data."""
    offsets = state.get("session_offsets", {})
    new_costs = []
    session_task_map = build_session_task_map()

    for session_dir in SESSION_DIRS:
        if not session_dir.exists():
            continue

        for jsonl_path in session_dir.glob("*.jsonl"):
            session_id = jsonl_path.stem
            offset = offsets.get(session_id, 0)
            file_size = jsonl_path.stat().st_size

            if file_size <= offset:
                continue

            task_id = session_task_map.get(session_id, "unknown")

            try:
                with open(jsonl_path) as f:
                    f.seek(offset)
                    while True:
                        line = f.readline()
                        if not line:
                            break
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        msg = entry.get("message", {})
                        if msg.get("role") != "assistant":
                            # Check for task ID in user messages
                            if msg.get("role") == "user":
                                content = msg.get("content", "")
                                if isinstance(content, list):
                                    content = " ".join(
                                        p.get("text", "") for p in content if isinstance(p, dict)
                                    )
                                tid = extract_task_id(str(content))
                                if tid:
                                    task_id = tid
                            continue

                        usage = msg.get("usage")
                        if not usage:
                            continue

                        model = msg.get("model", "unknown")
                        cost = calculate_cost(usage, model)
                        timestamp = entry.get("timestamp", "")

                        # Parse date from timestamp
                        try:
                            if isinstance(timestamp, str) and timestamp:
                                dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
                            elif isinstance(timestamp, (int, float)):
                                dt = datetime.fromtimestamp(timestamp / 1000, tz=timezone.utc)
                            else:
                                dt = datetime.now(timezone.utc)
                        except Exception:
                            dt = datetime.now(timezone.utc)

                        date_key = dt.strftime("%Y-%m-%d")

                        new_costs.append({
                            "date": date_key,
                            "model": model,
                            "cost": cost,
                            "input_tokens": usage.get("input", 0) or 0,
                            "output_tokens": usage.get("output", 0) or 0,
                            "cache_read": usage.get("cacheRead", 0) or 0,
                            "task_id": task_id,
                            "session_id": session_id,
                        })

                    offsets[session_id] = f.tell()
            except Exception as e:
                print(f"Error reading {jsonl_path}: {e}", file=sys.stderr)

    state["session_offsets"] = offsets
    return new_costs


def aggregate_costs(state, new_costs):
    """Aggregate new costs into state."""
    daily = state.get("daily_costs", {})
    task_costs = state.get("task_costs", {})
    model_costs = state.get("model_costs", {})

    now = datetime.now(timezone.utc)
    current_month = now.strftime("%Y-%m")

    for c in new_costs:
        date = c["date"]
        cost = c["cost"]
        model = c["model"]
        task = c["task_id"]

        # Daily aggregation
        if date not in daily:
            daily[date] = {"total": 0.0, "calls": 0, "input_tokens": 0, "output_tokens": 0}
        daily[date]["total"] += cost
        daily[date]["calls"] += 1
        daily[date]["input_tokens"] += c["input_tokens"]
        daily[date]["output_tokens"] += c["output_tokens"]

        # Task aggregation (current month only)
        if date.startswith(current_month):
            if task not in task_costs:
                task_costs[task] = {"total": 0.0, "calls": 0}
            task_costs[task]["total"] += cost
            task_costs[task]["calls"] += 1

        # Model aggregation
        if model not in model_costs:
            model_costs[model] = {"total": 0.0, "calls": 0}
        model_costs[model]["total"] += cost
        model_costs[model]["calls"] += 1

    # Calculate monthly total
    monthly_total = sum(
        v["total"] for k, v in daily.items() if k.startswith(current_month)
    )

    # Calculate weekly total (last 7 days)
    week_ago = (now - timedelta(days=7)).strftime("%Y-%m-%d")
    weekly_total = sum(
        v["total"] for k, v in daily.items() if k >= week_ago
    )

    # Today's total
    today = now.strftime("%Y-%m-%d")
    daily_total = daily.get(today, {}).get("total", 0.0)

    state["daily_costs"] = daily
    state["task_costs"] = task_costs
    state["model_costs"] = model_costs
    state["monthly_total"] = monthly_total
    state["weekly_total"] = weekly_total
    state["daily_total"] = daily_total
    state["last_scan"] = now.isoformat()

    # Clean old daily data (keep 90 days)
    cutoff = (now - timedelta(days=90)).strftime("%Y-%m-%d")
    state["daily_costs"] = {k: v for k, v in daily.items() if k >= cutoff}

    return monthly_total


def update_budget_file(state):
    """Sync spend data to existing budget-controller system."""
    try:
        budget = json.loads(BUDGET_FILE.read_text())
        budget["daily_spend"] = round(state.get("daily_total", 0), 4)
        budget["weekly_spend"] = round(state.get("weekly_total", 0), 4)
        budget["monthly_spend"] = round(state.get("monthly_total", 0), 4)
        budget["last_reset_daily"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT00:00:00Z")
        budget["last_reset_weekly"] = (
            datetime.now(timezone.utc) - timedelta(days=datetime.now(timezone.utc).weekday())
        ).strftime("%Y-%m-%dT00:00:00Z")
        budget["last_reset_monthly"] = datetime.now(timezone.utc).strftime("%Y-%m-01T00:00:00Z")

        monthly_budget = budget.get("monthly_limit", DEFAULT_MONTHLY_BUDGET)
        ratio = state["monthly_total"] / monthly_budget if monthly_budget > 0 else 0

        if ratio >= 1.0:
            budget["status"] = "over_monthly_limit"
        elif ratio >= CRITICAL_THRESHOLD:
            budget["status"] = "critical"
        elif ratio >= ALERT_THRESHOLD:
            budget["status"] = "warning"
        else:
            budget["status"] = "ok"

        BUDGET_FILE.write_text(json.dumps(budget, indent=2))
    except Exception as e:
        print(f"Warning: Could not update budget file: {e}", file=sys.stderr)


def send_slack_alert(monthly_total, budget, level):
    """Send Slack DM alert to Caio."""
    token = os.environ.get("SLACK_BOT_TOKEN", "")
    if not token:
        print("ALERT: No SLACK_BOT_TOKEN — cannot send budget alert")
        return False

    pct = (monthly_total / budget * 100) if budget > 0 else 0
    emoji = ":rotating_light:" if level == "critical" else ":warning:"
    now = datetime.now(timezone.utc)
    days_left = (datetime(now.year, now.month + 1 if now.month < 12 else 1,
                          1, tzinfo=timezone.utc) - now).days

    msg = (
        f"{emoji} *API Budget Alert ({level.upper()})*\n"
        f"*Monthly spend:* ${monthly_total:.2f} / ${budget:.2f} ({pct:.1f}%)\n"
        f"*Days remaining:* {days_left}\n"
        f"*Projected month-end:* ${(monthly_total / max(now.day, 1)) * 30:.2f}\n"
        f"*Action:* Review agent spawning frequency and model usage."
    )

    try:
        # Open DM
        r = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://slack.com/api/conversations.open",
             "-H", f"Authorization: Bearer {token}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"users": CAIO_SLACK_ID})],
            capture_output=True, text=True, timeout=10
        )
        dm_data = json.loads(r.stdout)
        channel = dm_data.get("channel", {}).get("id")
        if not channel:
            print(f"Could not open DM: {r.stdout[:200]}")
            return False

        # Send
        r2 = subprocess.run(
            ["curl", "-s", "-X", "POST", "https://slack.com/api/chat.postMessage",
             "-H", f"Authorization: Bearer {token}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"channel": channel, "text": msg, "mrkdwn": True})],
            capture_output=True, text=True, timeout=10
        )
        resp = json.loads(r2.stdout)
        if resp.get("ok"):
            print(f"ALERT SENT: {level} budget alert (${monthly_total:.2f}/${budget:.2f})")
            return True
        else:
            print(f"ALERT FAILED: {r2.stdout[:200]}")
    except Exception as e:
        print(f"ALERT ERROR: {e}")

    return False


def check_alerts(state, monthly_total):
    """Check if budget alerts should be sent."""
    budget = get_monthly_budget()
    ratio = monthly_total / budget if budget > 0 else 0

    last_alert = state.get("last_alert_sent")
    now = datetime.now(timezone.utc)

    # Don't alert more than once every 6 hours
    if last_alert:
        try:
            last_dt = datetime.fromisoformat(last_alert)
            if (now - last_dt).total_seconds() < 6 * 3600:
                return
        except Exception:
            pass

    if ratio >= CRITICAL_THRESHOLD:
        if send_slack_alert(monthly_total, budget, "critical"):
            state["last_alert_sent"] = now.isoformat()
    elif ratio >= ALERT_THRESHOLD:
        if send_slack_alert(monthly_total, budget, "warning"):
            state["last_alert_sent"] = now.isoformat()


def days_until_limit(state):
    """Estimate days until hitting monthly limit at current spend rate."""
    budget = get_monthly_budget()
    monthly = state.get("monthly_total", 0)
    if monthly <= 0:
        return 999

    now = datetime.now(timezone.utc)
    day_of_month = now.day
    if day_of_month < 1:
        return 999

    daily_avg = monthly / day_of_month
    if daily_avg <= 0:
        return 999

    remaining = budget - monthly
    if remaining <= 0:
        return 0

    return int(remaining / daily_avg)


def print_dashboard(state):
    """Print a text dashboard of API usage."""
    now = datetime.now(timezone.utc)
    budget = get_monthly_budget()
    monthly = state.get("monthly_total", 0)
    weekly = state.get("weekly_total", 0)
    daily = state.get("daily_total", 0)
    pct = (monthly / budget * 100) if budget > 0 else 0
    est_days = days_until_limit(state)

    print("=" * 60)
    print("           API USAGE MONITOR — BUDGET DASHBOARD")
    print("=" * 60)
    print()

    # Budget overview
    bar_len = 40
    filled = int(bar_len * min(pct / 100, 1.0))
    bar = "#" * filled + "-" * (bar_len - filled)
    status = "OK" if pct < 80 else ("WARNING" if pct < 95 else "CRITICAL")

    print(f"  Status: {status}")
    print(f"  Monthly: ${monthly:.2f} / ${budget:.2f} ({pct:.1f}%)")
    print(f"  [{bar}]")
    print(f"  Weekly:  ${weekly:.2f}")
    print(f"  Today:   ${daily:.2f}")
    print(f"  Est. days to limit: {est_days}")
    print()

    # Daily breakdown (last 7 days)
    print("  DAILY SPEND (Last 7 days)")
    print("  " + "-" * 45)
    daily_costs = state.get("daily_costs", {})
    for i in range(6, -1, -1):
        d = (now - timedelta(days=i)).strftime("%Y-%m-%d")
        info = daily_costs.get(d, {"total": 0, "calls": 0})
        bar_w = int(min(info["total"] / max(budget / 30, 0.01), 1.0) * 20)
        print(f"  {d}: ${info['total']:7.2f} ({info['calls']:4d} calls) {'#' * bar_w}")
    print()

    # Cost by model
    print("  COST BY MODEL (This month)")
    print("  " + "-" * 45)
    model_costs = state.get("model_costs", {})
    for model, info in sorted(model_costs.items(), key=lambda x: x[1]["total"], reverse=True):
        if info["total"] > 0.001:
            print(f"  {model:35s} ${info['total']:7.2f} ({info['calls']} calls)")
    print()

    # Top tasks by cost
    print("  TOP TASKS BY COST (This month)")
    print("  " + "-" * 45)
    task_costs = state.get("task_costs", {})
    sorted_tasks = sorted(task_costs.items(), key=lambda x: x[1]["total"], reverse=True)[:15]
    for task, info in sorted_tasks:
        if info["total"] > 0.001:
            avg = info["total"] / max(info["calls"], 1)
            print(f"  {task:15s} ${info['total']:7.2f} ({info['calls']:3d} calls, avg ${avg:.3f})")
    print()

    print(f"  Last scan: {state.get('last_scan', 'never')}")
    print(f"  Sessions tracked: {len(state.get('session_offsets', {}))}")
    print("=" * 60)


def main():
    load_env()
    state = load_state()

    if "--dashboard" in sys.argv:
        print_dashboard(state)
        return

    if "--reset" in sys.argv:
        now = datetime.now(timezone.utc)
        current_month = now.strftime("%Y-%m")
        state["daily_costs"] = {
            k: v for k, v in state.get("daily_costs", {}).items()
            if not k.startswith(current_month)
        }
        state["monthly_total"] = 0.0
        state["task_costs"] = {}
        state["model_costs"] = {}
        state["last_alert_sent"] = None
        save_state(state)
        print("Monthly counters reset.")
        return

    # Scan sessions and aggregate
    print(f"[api-monitor] Scanning sessions...")
    new_costs = scan_sessions(state)
    print(f"[api-monitor] Found {len(new_costs)} new LLM calls")

    monthly_total = aggregate_costs(state, new_costs)
    print(f"[api-monitor] Monthly total: ${monthly_total:.2f}")

    # Update budget-controller integration
    update_budget_file(state)

    # Check alerts
    check_alerts(state, monthly_total)

    # Log projected overage warning
    est = days_until_limit(state)
    if est <= 3 and monthly_total > 0:
        print(f"[api-monitor] WARNING: Estimated {est} days until budget limit!")

    save_state(state)

    # Also print dashboard in cron mode
    if "--quiet" not in sys.argv:
        print_dashboard(state)


if __name__ == "__main__":
    main()
