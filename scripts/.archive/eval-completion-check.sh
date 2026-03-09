#!/bin/bash
# Check for completed Guardian evals and auto-report + trigger Anton's loop
# Run via cron every 2min
set -e

WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
EVAL_DIR="$WORKSPACE/guardian-agents-api-real/evals/.runs/content_moderation"
BASELINE=0.79

source "$WORKSPACE/.env.secrets" 2>/dev/null || true
source "$WORKSPACE/.env.linear" 2>/dev/null || true

CAIO_DM="D0AK1B981QR"

# Use Python for all JSON parsing (jq not available in launchd env)
python3 << 'PYEOF'
import json, os, sys, subprocess, time
from pathlib import Path

WORKSPACE = "/Users/fonsecabc/.openclaw/workspace"
EVAL_DIR = f"{WORKSPACE}/guardian-agents-api-real/evals/.runs/content_moderation"
BASELINE = 0.79
CAIO_DM = "D0AK1B981QR"
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
LINEAR_SCRIPT = f"{WORKSPACE}/skills/linear/scripts/linear.sh"

import glob
runs = sorted(glob.glob(f"{EVAL_DIR}/run_*"), reverse=True)
if not runs:
    sys.exit(0)

latest = runs[0]
run_name = os.path.basename(latest)
reported_flag = os.path.join(latest, ".reported")
meta_path = os.path.join(latest, "progress_meta.json")
metrics_path = os.path.join(latest, "metrics.json")

# Already reported?
if os.path.exists(reported_flag):
    sys.exit(0)

# Not initialized?
if not os.path.exists(meta_path):
    sys.exit(0)

# Check status — completed when total > 0 and completed == total, OR status == "completed"
meta = json.load(open(meta_path))
completed_count = meta.get("completed", 0)
total_count = meta.get("total", 0)
is_done = (meta.get("status") == "completed") or (total_count > 0 and completed_count >= total_count)
if not is_done:
    sys.exit(0)

# No metrics yet?
if not os.path.exists(metrics_path):
    sys.exit(0)

# Extract accuracy
metrics = json.load(open(metrics_path))
accuracy = metrics.get("summary_statistics", {}).get("mean_aggregate_score")
if accuracy is None:
    accuracy = metrics.get("metrics", {}).get("overall", {}).get("answer", {}).get("exact")
if accuracy is None:
    sys.exit(0)

completed = meta.get("completed", 0)
total = meta.get("total", 0)
accuracy_pct = f"{accuracy * 100:.2f}"
delta = accuracy - BASELINE
delta_pp = f"{delta * 100:+.1f}"

# Count errors
error_count = 0
progress_path = os.path.join(latest, "progress.jsonl")
if os.path.exists(progress_path):
    for line in open(progress_path):
        try:
            if '"error"' in line and json.loads(line).get("error"):
                error_count += 1
        except:
            pass

# Build report
report = f"""✅ *Guardian Eval Completed: {run_name}*

*Overall:* {accuracy_pct}% ({completed}/{total} cases)
*Baseline:* {BASELINE*100:.0f}%
*Delta:* *{delta_pp}pp*
*Errors:* {error_count}"""

# Run breakdown analysis
try:
    result = subprocess.run(
        ["python3", f"{WORKSPACE}/scripts/eval-analyze-breakdown.py", latest, str(BASELINE)],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode == 0:
        analysis = json.loads(result.stdout)
        by_type = analysis.get("analysis", {}).get("by_type", {})
        if by_type:
            report += "\n\n*Breakdown:*"
            for t, v in by_type.items():
                acc = v.get("accuracy", 0) * 100
                correct = v.get("correct", 0)
                total_t = v.get("total", 0)
                d = v.get("delta_vs_baseline", 0) * 100
                report += f"\n• *{t.upper()}*: {acc:.0f}% ({correct}/{total_t}) | Δ{d:+.0f}pp"
except:
    pass

# Post to Slack (Caio's DM)
if SLACK_BOT_TOKEN:
    try:
        import urllib.request
        payload = json.dumps({"channel": CAIO_DM, "text": report, "mrkdwn": True}).encode()
        req = urllib.request.Request(
            "https://slack.com/api/chat.postMessage",
            data=payload,
            headers={
                "Authorization": f"Bearer {SLACK_BOT_TOKEN}",
                "Content-Type": "application/json",
            }
        )
        urllib.request.urlopen(req, timeout=10)
    except:
        pass

# Log
with open("/tmp/guardian-eval-reports.log", "a") as f:
    f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')}: {report}\n\n")

# --- TRIGGER: Write eval completion event for Anton's heartbeat ---
trigger_file = f"{WORKSPACE}/.eval-completed-trigger"
trigger = {
    "event": "eval_completed",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "run_name": run_name,
    "accuracy": accuracy,
    "accuracy_pct": accuracy_pct,
    "delta_pp": delta_pp,
    "cases": f"{completed}/{total}",
    "errors": error_count,
    "run_dir": latest,
    "action_required": "Analyze breakdown, identify top improvements, spawn agents for next iteration. Target: 87%."
}
with open(trigger_file, "w") as f:
    json.dump(trigger, f, indent=2)

print(f"✓ Trigger file written: {trigger_file}")

# Mark as reported
Path(reported_flag).touch()
print(f"✓ Report generated for {run_name}: {accuracy_pct}% ({delta_pp}pp)")
PYEOF
