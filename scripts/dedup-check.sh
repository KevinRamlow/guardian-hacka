#!/bin/bash
# Dedup Check — Prevents spawning duplicate/similar agents
# Checks task text hash + keyword-based semantic similarity against recent history
#
# Usage: dedup-check.sh <task-id> <task-text>
# Exit codes: 0 = OK to spawn (no duplicate), 1 = duplicate found
# Stdout: "ok" or "duplicate:<matching-task-id>:<reason>"
set -euo pipefail

TASK_ID="${1:?Task ID required}"
TASK_TEXT="${2:?Task text required}"

DEDUP_DIR="/Users/fonsecabc/.openclaw/tasks/dedup"
HISTORY_FILE="$DEDUP_DIR/task-history.jsonl"
EVENTS_FILE="$DEDUP_DIR/dedup-events.jsonl"
SIMILARITY_THRESHOLD=0.55  # 55% keyword overlap = duplicate (catches paraphrased tasks)
LOOKBACK_HOURS=24

mkdir -p "$DEDUP_DIR"
touch "$HISTORY_FILE"

# Run the dedup check in Python
_TASK_ID="$TASK_ID" _TASK_TEXT="$TASK_TEXT" _HISTORY_FILE="$HISTORY_FILE" \
_EVENTS_FILE="$EVENTS_FILE" _THRESHOLD="$SIMILARITY_THRESHOLD" \
_LOOKBACK_HOURS="$LOOKBACK_HOURS" \
python3 << 'PYEOF'
import hashlib, json, time, sys, re, os
from collections import Counter

task_id = os.environ.get("_TASK_ID", "")
task_text = os.environ.get("_TASK_TEXT", "")
history_file = os.environ.get("_HISTORY_FILE", "")
events_file = os.environ.get("_EVENTS_FILE", "")
threshold = float(os.environ.get("_THRESHOLD", "0.7"))
lookback_hours = int(os.environ.get("_LOOKBACK_HOURS", "24"))

now = int(time.time())
cutoff = now - (lookback_hours * 3600)

# Hash the task text (normalized: lowercase, strip whitespace, remove markdown headers)
def normalize(text):
    """Normalize task text for comparison."""
    text = text.lower()
    # Remove markdown formatting
    text = re.sub(r'[#*_`\-\[\]()>]', ' ', text)
    # Remove common template boilerplate
    for pattern in ['linear task:', 'timeout:', 'task context', 'logging', 'log to:', 'linear-log.sh']:
        text = re.sub(re.escape(pattern), '', text)
    # Collapse whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def extract_keywords(text):
    """Extract meaningful keywords from task text."""
    normalized = normalize(text)
    # Remove common stopwords
    stopwords = {'the','a','an','is','are','was','were','be','been','being','have','has','had',
                 'do','does','did','will','would','could','should','may','might','shall','can',
                 'for','and','but','or','not','no','so','if','then','than','that','this','it',
                 'to','of','in','on','at','by','with','from','as','into','about','after','before',
                 'use','using','when','what','how','all','each','every','any','few','more','most',
                 'other','some','such','only','same','cai','minutes','task','minute','agent'}
    words = re.findall(r'[a-z][a-z0-9_]{2,}', normalized)
    return [w for w in words if w not in stopwords]

def keyword_similarity(kw1, kw2):
    """Jaccard-like similarity between keyword lists."""
    if not kw1 or not kw2:
        return 0.0
    set1 = set(kw1)
    set2 = set(kw2)
    intersection = set1 & set2
    union = set1 | set2
    if not union:
        return 0.0
    return len(intersection) / len(union)

task_hash = hashlib.sha256(normalize(task_text).encode()).hexdigest()[:16]
task_keywords = extract_keywords(task_text)

# Load recent history
recent_tasks = []
if os.path.exists(history_file):
    with open(history_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('ts', 0) >= cutoff:
                    recent_tasks.append(entry)
            except json.JSONDecodeError:
                continue

# Check 1: Exact hash match (identical task text)
for entry in recent_tasks:
    if entry.get('hash') == task_hash and entry.get('task_id') != task_id:
        reason = f"exact_hash_match"
        print(f"duplicate:{entry['task_id']}:{reason}")
        # Log the dedup event
        event = {"ts": now, "blocked_task": task_id, "matched_task": entry['task_id'],
                 "reason": reason, "hash": task_hash}
        with open(events_file, 'a') as f:
            f.write(json.dumps(event) + '\n')
        sys.exit(1)

# Check 2: Same task ID already completed recently
for entry in recent_tasks:
    if entry.get('task_id') == task_id:
        reason = f"same_task_id_ran_recently"
        print(f"duplicate:{entry['task_id']}:{reason}")
        event = {"ts": now, "blocked_task": task_id, "matched_task": entry['task_id'],
                 "reason": reason, "hash": task_hash}
        with open(events_file, 'a') as f:
            f.write(json.dumps(event) + '\n')
        sys.exit(1)

# Check 3: Semantic similarity via keyword overlap
for entry in recent_tasks:
    entry_keywords = entry.get('keywords', [])
    sim = keyword_similarity(task_keywords, entry_keywords)
    if sim >= threshold:
        reason = f"semantic_similarity={sim:.2f}"
        print(f"duplicate:{entry['task_id']}:{reason}")
        event = {"ts": now, "blocked_task": task_id, "matched_task": entry['task_id'],
                 "reason": reason, "similarity": sim, "hash": task_hash,
                 "shared_keywords": list(set(task_keywords) & set(entry_keywords))}
        with open(events_file, 'a') as f:
            f.write(json.dumps(event) + '\n')
        sys.exit(1)

# No duplicate found — record this task in history
entry = {
    "task_id": task_id,
    "hash": task_hash,
    "keywords": task_keywords,
    "ts": now,
    "text_preview": normalize(task_text)[:200]
}
with open(history_file, 'a') as f:
    f.write(json.dumps(entry) + '\n')

# Prune old entries (keep only last 24h)
if os.path.exists(history_file):
    with open(history_file, 'r') as f:
        lines = f.readlines()
    kept = []
    for line in lines:
        try:
            e = json.loads(line.strip())
            if e.get('ts', 0) >= cutoff:
                kept.append(line)
        except:
            continue
    with open(history_file, 'w') as f:
        f.writelines(kept)

print("ok")
sys.exit(0)
PYEOF
