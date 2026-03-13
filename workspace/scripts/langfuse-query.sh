#!/bin/bash
# Query Langfuse traces for Anton + subagents via mcporter
set -euo pipefail

ACTION="${1:-recent}"

case "$ACTION" in
  recent)
    echo "Recent traces (last 24h):"
    mcporter call langfuse.get_traces page=1 limit=20 --output json \
      | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('content', []):
    if item.get('type') == 'text':
        inner = json.loads(item['text'])
        for t in inner.get('data', []):
            tokens = (t.get('usage') or {}).get('total', 0)
            print(f\"{t.get('name','')} | {t.get('timestamp','')} | tokens: {tokens}\")
        break
"
    ;;

  stats)
    echo "Session statistics:"
    mcporter call langfuse.get_traces page=1 limit=100 --output json \
      | python3 -c "
import sys, json
from collections import defaultdict
data = json.load(sys.stdin)
for item in data.get('content', []):
    if item.get('type') == 'text':
        inner = json.loads(item['text'])
        groups = defaultdict(lambda: {'count': 0, 'tokens': 0})
        for t in inner.get('data', []):
            tag = (t.get('tags') or ['unknown'])[0]
            groups[tag]['count'] += 1
            groups[tag]['tokens'] += (t.get('usage') or {}).get('total', 0)
        for tag, v in groups.items():
            print(f\"{tag}: {v['count']} traces, {v['tokens']} tokens\")
        break
"
    ;;

  task)
    TASK_ID="${2:-CAI-304}"
    echo "Traces for $TASK_ID:"
    mcporter call langfuse.get_traces page=1 limit=50 --output json \
      | python3 -c "
import sys, json
task = sys.argv[1]
data = json.load(sys.stdin)
for item in data.get('content', []):
    if item.get('type') == 'text':
        inner = json.loads(item['text'])
        for t in inner.get('data', []):
            if task in (t.get('tags') or []):
                model = (t.get('metadata') or {}).get('model', 'unknown')
                print(f\"{t.get('name','')} | {t.get('timestamp','')} | {model}\")
        break
" "$TASK_ID"
    ;;

  *)
    echo "Usage: $0 {recent|stats|task <CAI-XXX>}"
    exit 1
    ;;
esac
