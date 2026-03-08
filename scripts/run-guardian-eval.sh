#!/bin/bash
# Direct Guardian eval runner - no agent wrapper
# Usage: bash scripts/run-guardian-eval.sh [dataset] [workers] [max_parallel_agents]

set -e

DATASET="${1:-guidelines_combined_dataset.jsonl}"
WORKERS="${2:-15}"
MAX_AGENTS="${3:-5}"

echo "=== Guardian Eval Runner ==="
echo "Dataset: $DATASET"
echo "Workers: $WORKERS"
echo "Max Parallel Agents: $MAX_AGENTS"
echo ""

# Validate auth
echo "→ Checking OAuth token..."
TOKEN_REMAINING=$(gcloud auth application-default print-access-token 2>/dev/null | \
  curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$(cat -)" 2>/dev/null | \
  jq -r '.expires_in // "0"')

if [ "$TOKEN_REMAINING" = "0" ] || [ "$TOKEN_REMAINING" -lt 1800 ]; then
  echo "❌ ERROR: OAuth token invalid or expires in <30min. Run: gcloud auth application-default login"
  exit 1
fi

echo "✓ OAuth valid for ${TOKEN_REMAINING}s (~$((TOKEN_REMAINING/60))min)"

# Kill existing evals to avoid conflicts
echo "→ Checking for existing evals..."
EXISTING=$(pgrep -f "run_eval.py.*content_moderation" || true)
if [ -n "$EXISTING" ]; then
  echo "⚠️  Found existing eval (PID: $EXISTING), killing..."
  pkill -f "run_eval.py.*content_moderation" || true
  sleep 2
fi

# Run eval
echo "→ Starting eval..."
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real

export MAX_PARALLEL_AGENTS=$MAX_AGENTS
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval

RUN_ID=$(date +%Y%m%d_%H%M%S)
LOG=/tmp/guardian-eval-${RUN_ID}.log

nohup .venv/bin/python3 evals/run_eval.py \
  --config evals/content_moderation/eval.yaml \
  --dataset evals/content_moderation/${DATASET} \
  --workers $WORKERS \
  > $LOG 2>&1 &

PID=$!
echo $PID > /tmp/guardian-eval.pid
echo ""
echo "✓ Eval started:"
echo "  PID: $PID"
echo "  Log: $LOG"
echo "  OAuth expires in: ~$((TOKEN_REMAINING/60))min"
echo ""
echo "Monitor with: bash scripts/guardian-eval-status.sh"
