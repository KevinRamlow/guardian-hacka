#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
GUARDIAN_EVAL=false
FAILED=()

[[ "${1:-}" == "--guardian-eval" ]] && GUARDIAN_EVAL=true

fail() { FAILED+=("$1|$2"); }

# --- Default checks (always run) ---

# 1. Claude CLI available
if ! which claude &>/dev/null; then
  fail "Claude CLI not found" "npm install -g @anthropic-ai/claude-code"
fi

# 2. Secrets loaded
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  if [[ -f "$WORKSPACE/.env.secrets" ]]; then
    source "$WORKSPACE/.env.secrets" 2>/dev/null
  fi
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    fail "ANTHROPIC_API_KEY not set" "source $WORKSPACE/.env.secrets"
  fi
fi

# 3. Linear API working
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  -H "Authorization: ${LINEAR_API_KEY:-none}" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { id } }"}' \
  https://api.linear.app/graphql 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "200" ]]; then
  fail "Linear API unreachable (HTTP $HTTP_CODE)" "Check LINEAR_API_KEY in $WORKSPACE/.env.secrets"
fi

# --- Guardian eval checks (only with --guardian-eval) ---
if $GUARDIAN_EVAL; then
  # 4. Cloud SQL Proxy running
  if ! mysql -e 'SELECT 1' &>/dev/null; then
    fail "Cloud SQL Proxy not running" \
      'cloud-sql-proxy "brandlovers-prod:us-east1:brandlovers-prod" --port 3306 &'
  fi

  # 5. GCP auth valid
  if ! gcloud auth print-access-token &>/dev/null; then
    fail "GCP auth expired" "gcloud auth login"
  fi

  # 6. .env.guardian-eval exists with correct project
  ENV_FILE="$WORKSPACE/.env.guardian-eval"
  if [[ ! -f "$ENV_FILE" ]] || ! grep -q "GOOGLE_CLOUD_PROJECT=brandlovers-prod" "$ENV_FILE" 2>/dev/null; then
    fail ".env.guardian-eval missing or wrong GOOGLE_CLOUD_PROJECT" \
      "echo 'GOOGLE_CLOUD_PROJECT=brandlovers-prod' >> $ENV_FILE"
  fi

  # 7. guardian-agents-api-real dir with evals/
  API_DIR="$WORKSPACE/guardian-agents-api-real"
  if [[ ! -d "$API_DIR/evals" ]]; then
    fail "guardian-agents-api-real/evals/ not found" \
      "Ensure $API_DIR exists with evals/ subdirectory"
  fi

  # 8. Python venv with required packages
  VENV="$API_DIR/.venv"
  if [[ ! -f "$VENV/bin/python" ]]; then
    fail "Python venv not found" "cd $API_DIR && python3 -m venv .venv && pip install -r requirements.txt"
  fi
fi

# --- Results ---
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "PREFLIGHT OK: All checks passed."
  exit 0
fi

echo "PREFLIGHT FAILED:"
for entry in "${FAILED[@]}"; do
  IFS='|' read -r msg fix <<< "$entry"
  echo "  ✗ $msg"
  echo "    FIX: $fix"
done
exit 1
