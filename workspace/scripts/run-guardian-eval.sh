#!/bin/bash
# Guardian eval runner — launches eval as background process.
# Usage: bash scripts/run-guardian-eval.sh --dataset <path> [--config <path>] [--workers N] [--max-agents N]
#
# --dataset is the path passed directly to run_eval.py (relative to repo root or absolute).
# Examples:
#   --dataset general/human_evals_general_dataset.jsonl
#   --dataset evals/content_moderation/all/human_evals_combined_dataset.jsonl
#
# GUARDRAIL: This script launches nohup python (an eval process). It is only legitimate
# when called INSIDE a sub-agent that was spawned via dispatcher.sh.

set -e

# Block direct invocation from main Anton session
if [ -n "$OPENCLAW_SESSION_TYPE" ] && [ "$OPENCLAW_SESSION_TYPE" = "main" ]; then
  echo "ERROR: run-guardian-eval.sh cannot be called from main thread." >&2
  echo "  Spawn a sub-agent via dispatcher.sh and let the sub-agent run evals." >&2
  exit 1
fi

# Defaults
DATASET=""
WORKERS=15
MAX_AGENTS=5
CONFIG_PATH=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config|-c)       CONFIG_PATH="$2"; shift 2;;
    --dataset|-d)      DATASET="$2"; shift 2;;
    --workers|-w)      WORKERS="$2"; shift 2;;
    --max-agents|-m)   MAX_AGENTS="$2"; shift 2;;
    --*)               echo "Unknown option: $1"; exit 1;;
    *)
      # Legacy positional: first = dataset, second = workers, third = max_agents
      if [ -z "$DATASET" ]; then DATASET="$1"
      elif [ -z "$_pos2" ]; then _pos2=1; WORKERS="$1"
      elif [ -z "$_pos3" ]; then _pos3=1; MAX_AGENTS="$1"
      fi
      shift;;
  esac
done

if [ -z "$DATASET" ]; then
  echo "ERROR: --dataset is required." >&2
  echo "Usage: bash scripts/run-guardian-eval.sh --dataset <path> [--workers N]" >&2
  exit 1
fi

echo "=== Guardian Eval Runner ==="
echo "Dataset: $DATASET"
echo "Workers: $WORKERS"
echo "Max Parallel Agents: $MAX_AGENTS"
echo ""

# Validate auth (supports both SA and ADC)
echo "→ Checking auth..."
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-/home/node/.openclaw/gcp-credentials.json}"
export PATH="/home/node/google-cloud-sdk/bin:/home/node/.local/bin:$PATH"

ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token 2>/dev/null || echo "")
if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ ERROR: No valid auth token. Activate SA: gcloud auth activate-service-account --key-file=..." >&2
  exit 1
fi

TOKEN_REMAINING=$(curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$ACCESS_TOKEN" 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in', 0))" 2>/dev/null || echo "3600")

if [ "$TOKEN_REMAINING" -lt 1800 ] 2>/dev/null; then
  echo "⚠️  Token expires in ${TOKEN_REMAINING}s, re-activating SA..."
  gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null
  TOKEN_REMAINING=3600
fi

echo "✓ Auth valid (~$((TOKEN_REMAINING/60))min remaining)"

# Kill existing evals to avoid conflicts
echo "→ Checking for existing evals..."
EXISTING=$(grep -rl "run_eval.py.*content_moderation" /proc/*/cmdline 2>/dev/null | cut -d/ -f3 || true)
if [ -n "$EXISTING" ]; then
  echo "⚠️  Found existing eval (PID: $EXISTING), killing..."
  kill $EXISTING 2>/dev/null || true
  sleep 2
fi

# Run eval
echo "→ Starting eval..."
cd ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api-real

export MAX_PARALLEL_AGENTS=$MAX_AGENTS

# Source eval env if it exists
ENV_FILE="${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/.env.guardian-eval"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

RUN_ID=$(date +%Y%m%d_%H%M%S)
LOG=/tmp/guardian-eval-${RUN_ID}.log

EVAL_CONFIG="${CONFIG_PATH:-evals/content_moderation/eval.yaml}"
nohup .venv/bin/python3 evals/run_eval.py \
  --config "$EVAL_CONFIG" \
  --dataset "$DATASET" \
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
