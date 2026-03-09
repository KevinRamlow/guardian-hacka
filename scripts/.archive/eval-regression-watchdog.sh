#!/bin/bash
# eval-regression-watchdog.sh
# Monitors latest Guardian eval run for regression.json.
# Alerts Slack on warnings (>0.5pp subset drop) or critical (>1pp overall drop).
# On critical: also triggers git stash rollback in guardian-agents-api-real.
#
# Usage:
#   bash scripts/eval-regression-watchdog.sh [run_dir]
#   If run_dir is not provided, finds the latest completed run automatically.

set -euo pipefail

GUARDIAN_DIR="/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real"
RUNS_DIR="$GUARDIAN_DIR/evals/.runs/content_moderation"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"

# Load Slack token
source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null || true

# ─── Find run dir ────────────────────────────────────────────────────────────
if [ -n "${1:-}" ]; then
  RUN_DIR="$1"
else
  # Find the latest run directory that has a regression.json
  RUN_DIR=$(find "$RUNS_DIR" -name "regression.json" -maxdepth 2 2>/dev/null \
    | xargs -I{} dirname {} \
    | sort | tail -1)
fi

if [ -z "$RUN_DIR" ] || [ ! -f "$RUN_DIR/regression.json" ]; then
  echo "No regression.json found in $RUNS_DIR — skipping"
  exit 0
fi

# Check if this regression.json was already processed
PROCESSED_MARKER="$RUN_DIR/.regression-processed"
if [ -f "$PROCESSED_MARKER" ]; then
  echo "Already processed: $RUN_DIR — skipping"
  exit 0
fi

echo "=== Eval Regression Watchdog ==="
echo "Run dir: $RUN_DIR"
echo ""

# ─── Parse regression.json ───────────────────────────────────────────────────
python3 << PYEOF
import json, sys, os, subprocess
from datetime import datetime, timezone

run_dir = "$RUN_DIR"
regression_file = f"{run_dir}/regression.json"
slack_token = os.environ.get("SLACK_BOT_TOKEN", "")
guardian_dir = "$GUARDIAN_DIR"
linear_log = "$LINEAR_LOG"
processed_marker = "$PROCESSED_MARKER"

with open(regression_file) as f:
    r = json.load(f)

baseline = r["baseline_accuracy_pct"]
current = r["new_accuracy_pct"]
delta = r["overall_delta_pp"]
warnings = r["warnings"]
critical = r["critical"]
subset_deltas = r.get("subset_deltas", {})

print(f"Baseline:  {baseline:.2f}%")
print(f"Current:   {current:.2f}%")
print(f"Delta:     {delta:+.2f}pp")
print(f"Critical:  {critical}")
print(f"Warnings:  {len(warnings)}")
print()

def send_slack(channel, text):
    if not slack_token:
        print(f"[SLACK SKIPPED — no token] {text}")
        return
    try:
        import urllib.request
        payload = json.dumps({"channel": channel, "text": text}).encode()
        req = urllib.request.Request(
            "https://slack.com/api/chat.postMessage",
            data=payload,
            headers={"Authorization": f"Bearer {slack_token}", "Content-Type": "application/json"},
        )
        resp = urllib.request.urlopen(req, timeout=10)
        result = json.loads(resp.read())
        if not result.get("ok"):
            print(f"Slack error: {result}")
    except Exception as e:
        print(f"Slack failed: {e}")

# ─── Build message ────────────────────────────────────────────────────────────
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

if critical:
    status_icon = "🚨"
    severity = "CRITICAL REGRESSION"
elif warnings:
    status_icon = "⚠️"
    severity = "SUBSET REGRESSION"
else:
    # No regression — nothing to do
    print("✅ No regressions — nothing to report")
    open(processed_marker, "w").close()
    sys.exit(0)

# Format subset breakdown
subset_lines = []
for cls, d in sorted(subset_deltas.items()):
    if d is None:
        continue
    marker = " ⚠️" if d < -0.5 else ""
    subset_lines.append(f"  • {cls}: {d:+.2f}pp{marker}")
subset_text = "\n".join(subset_lines) if subset_lines else "  (no subset data)"

message = (
    f"{status_icon} *Guardian Eval {severity}* — {timestamp}\n"
    f"Baseline: *{baseline:.2f}%* → Current: *{current:.2f}%* ({delta:+.2f}pp)\n"
    f"\n*Subset breakdown:*\n{subset_text}"
)

if warnings:
    message += f"\n\n*Warnings:*\n" + "\n".join(f"  • {w}" for w in warnings)

if critical:
    message += f"\n\n🔴 *Overall drop >{1.0:.1f}pp — rollback triggered*"
    # Attempt git stash in guardian-agents-api-real
    try:
        result = subprocess.run(
            ["git", "stash", "--include-untracked", "-m", "auto-rollback: regression detected"],
            cwd=guardian_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and "No local changes" not in result.stdout:
            message += f"\n✅ `git stash` succeeded: {result.stdout.strip()}"
            print(f"Rollback (git stash) succeeded: {result.stdout.strip()}")
        else:
            message += f"\nℹ️ No uncommitted changes to stash (already committed or clean)"
            print(f"git stash: {result.stdout.strip() or result.stderr.strip()}")
    except Exception as e:
        message += f"\n⚠️ Rollback failed: {e}"
        print(f"Rollback failed: {e}")

# Send to #guardian-alerts or #guardian-dev channel
send_slack("C0926NW0319", message)  # #alerts-guardian
print()
print(message)

# Mark as processed
open(processed_marker, "w").close()
print(f"\nProcessed marker written: {processed_marker}")
PYEOF
