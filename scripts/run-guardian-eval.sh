#!/bin/bash
# Guardian Eval Wrapper — Automatically configures GCP env before running eval
# Usage: run-guardian-eval.sh [eval.py arguments...]
#
# This script ensures GOOGLE_CLOUD_PROJECT=brandlovers-prod is always set,
# preventing 403 PERMISSION_DENIED errors from homolog SA trying to access prod buckets.
set -euo pipefail

WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
GUARDIAN_REPO="$WORKSPACE/guardian-agents-api-real"
ENV_FILE="$WORKSPACE/.env.guardian-eval"

# Verify guardian repo exists
if [ ! -d "$GUARDIAN_REPO" ]; then
  echo "ERROR: Guardian repo not found at $GUARDIAN_REPO" >&2
  exit 1
fi

# Source Guardian eval environment
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Guardian eval env file not found at $ENV_FILE" >&2
  exit 1
fi

source "$ENV_FILE"

# Verify configuration
if [ "$GOOGLE_CLOUD_PROJECT" != "brandlovers-prod" ]; then
  echo "ERROR: GOOGLE_CLOUD_PROJECT is $GOOGLE_CLOUD_PROJECT, expected brandlovers-prod" >&2
  exit 1
fi

# Navigate to Guardian repo
cd "$GUARDIAN_REPO"

# Activate venv if exists
if [ -d ".venv" ]; then
  source .venv/bin/activate
fi

# Run eval with all arguments passed through
echo "Running Guardian eval with GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT"
exec python3 evals/run_eval.py "$@"
