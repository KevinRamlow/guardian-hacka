#!/bin/bash
# Generate Guardian eval metrics JSON for cockpit dashboard
# Outputs JSON consumed by /api/eval endpoint

python3 << 'PYEOF'
import json, os, glob, time

EVAL_DIR = "/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real/evals/.runs/content_moderation"
TARGET_FILE = "/Users/fonsecabc/.openclaw/workspace/.guardian-improvement-target"
BASELINE = 0.79

# Check current eval running
current_eval = None
pid_file = "/tmp/guardian-eval.pid"
if os.path.exists(pid_file):
    try:
        pid = int(open(pid_file).read().strip())
        os.kill(pid, 0)  # Check if alive
        # Find latest run dir
        runs = sorted(glob.glob(f"{EVAL_DIR}/run_*"), reverse=True)
        if runs:
            meta_path = os.path.join(runs[0], "progress_meta.json")
            if os.path.exists(meta_path):
                meta = json.load(open(meta_path))
                completed = meta.get("completed", 0)
                total = meta.get("total", 0)
                pct = int(completed * 100 / total) if total > 0 else 0
                # Get elapsed from process
                import subprocess
                try:
                    elapsed = subprocess.check_output(["ps", "-p", str(pid), "-o", "etime="], text=True).strip()
                except:
                    elapsed = "?"
                current_eval = {
                    "status": "running",
                    "run_name": os.path.basename(runs[0]),
                    "pid": str(pid),
                    "progress": {"completed": completed, "total": total, "percent": pct},
                    "elapsed": elapsed,
                }
    except (ProcessLookupError, OSError, ValueError):
        pass

# Recent completed runs
recent_runs = []
runs = sorted(glob.glob(f"{EVAL_DIR}/run_*"), reverse=True)[:5]
for run_dir in runs:
    metrics_path = os.path.join(run_dir, "metrics.json")
    if not os.path.exists(metrics_path):
        continue
    try:
        metrics = json.load(open(metrics_path))
        acc = metrics.get("summary_statistics", {}).get("mean_aggregate_score")
        if acc is None:
            acc = metrics.get("metrics", {}).get("overall", {}).get("answer", {}).get("exact")
        if acc is None:
            continue
        acc_pct = f"{acc * 100:.2f}"
        delta = acc - BASELINE
        delta_pp = f"{delta * 100:+.1f}"
        run_name = os.path.basename(run_dir)
        timestamp = run_name.replace("run_", "")
        recent_runs.append({
            "run_name": run_name,
            "timestamp": timestamp,
            "accuracy": acc_pct,
            "delta_pp": delta_pp,
            "status": "completed",
        })
    except:
        pass

# Target progress
target_accuracy = 0.87
current_accuracy = BASELINE
iterations = 0
if os.path.exists(TARGET_FILE):
    try:
        t = json.load(open(TARGET_FILE))
        target_accuracy = t.get("target_accuracy", 0.87)
        current_accuracy = t.get("current_accuracy", BASELINE)
        iterations = t.get("iterations", 0)
    except:
        pass

# Use best recent run as current if better than stored
for r in recent_runs:
    acc = float(r["accuracy"]) / 100
    if acc > current_accuracy:
        current_accuracy = acc

result = {
    "current_eval": current_eval,
    "recent_runs": recent_runs,
    "target": {
        "target_accuracy": target_accuracy,
        "current_accuracy": current_accuracy,
        "baseline_accuracy": BASELINE,
        "target_delta_pp": (target_accuracy - BASELINE) * 100,
        "current_delta_pp": (current_accuracy - BASELINE) * 100,
        "remaining_pp": (target_accuracy - current_accuracy) * 100,
        "iterations": iterations,
    }
}

print(json.dumps(result))
PYEOF
