#!/usr/bin/env bash
set -euo pipefail

TASK_ID="${1:?Usage: diagnose-failure.sh CAI-XXX}"
LOG_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}/tasks/agent-logs"

STDERR_FILE="${LOG_DIR}/${TASK_ID}-stderr.log"
OUTPUT_FILE="${LOG_DIR}/${TASK_ID}-output.log"
ACTIVITY_FILE="${LOG_DIR}/${TASK_ID}-activity.jsonl"

# Collect all log content into a single variable for classification
ALL_LOGS=""
for f in "$STDERR_FILE" "$OUTPUT_FILE" "$ACTIVITY_FILE"; do
  [ -f "$f" ] && ALL_LOGS+="$(cat "$f")"$'\n'
done

# Snippets for JSON output (first 300 chars)
stderr_snippet=""
[ -f "$STDERR_FILE" ] && stderr_snippet="$(head -c 300 "$STDERR_FILE" | tr '\n' ' ' | tr '"' "'" | tr '\\' '/')"
output_snippet=""
[ -f "$OUTPUT_FILE" ] && output_snippet="$(head -c 300 "$OUTPUT_FILE" | tr '\n' ' ' | tr '"' "'" | tr '\\' '/')"

# Classify error
error_class="unknown"
fix="ESCALATE: Manual investigation needed"

if echo "$ALL_LOGS" | grep -qiE "invalid_grant|PERMISSION_DENIED|403|token expired|reauthentication"; then
  error_class="auth_expired"
  fix="FIX: Run gcloud auth login or check service account"
elif echo "$ALL_LOGS" | grep -qiE "rate limit|quota exceeded|429|overloaded|billing"; then
  error_class="rate_limit"
  fix="FIX: Retry with model=claude-sonnet-4-6 or wait 5min"
elif echo "$ALL_LOGS" | grep -qiE "max_tokens|MAX_TOKENS|context length"; then
  error_class="max_tokens"
  fix="FIX: Break task into smaller chunks"
elif echo "$ALL_LOGS" | grep -qiE "ENOTFOUND|not found|No such file|ModuleNotFoundError"; then
  error_class="config_error"
  fix="FIX: Check .env.guardian-eval and .env"
elif echo "$ALL_LOGS" | grep -qiE "idle"; then
  error_class="idle_killed"
  fix="FIX: Increase timeout or check if task has long setup"
fi

# Output JSON
printf '{"task_id": "%s", "error_class": "%s", "fix": "%s", "stderr_snippet": "%s", "output_snippet": "%s"}\n' \
  "$TASK_ID" "$error_class" "$fix" "$stderr_snippet" "$output_snippet"
