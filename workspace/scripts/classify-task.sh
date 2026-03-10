#!/bin/bash
# classify-task.sh — Auto-classify task and return appropriate Linear label IDs
#
# Usage: classify-task.sh "Task Title" "Task Description"
# Output: Space-separated label IDs (or empty string)
#
# Classification rules:
# - Guardian-related → guardian
# - Billy-related → billy  
# - Evals, tests → testing
# - New features → feature
# - Dashboards, metrics, monitoring → monitoring
# - Timeout, idle, resilience, reliability → resilience
# - Auto-queue related → queue
# - Safety, validation, guardrails → guardrails

set -euo pipefail

TITLE="${1:-}"
DESCRIPTION="${2:-}"
COMBINED=$(echo "$TITLE $DESCRIPTION" | tr '[:upper:]' '[:lower:]')

# Label IDs (CAI team)
LABEL_GUARDIAN="88bff148-34ac-4713-9071-86ef88d6f6fb"
LABEL_BILLY="80e32667-5df8-440c-ab5a-006994179271"
LABEL_FEATURE="0c38f7c5-786f-462a-b099-50c717b61668"
LABEL_TESTING="fcf078cc-e86f-45db-9b9a-f8bf186d8fcd"
LABEL_GUARDRAILS="1a00bb61-391a-425a-8db0-2b3e707776ab"
LABEL_MONITORING="b337f54c-94f7-49f1-b4f0-5a9e3b3712f0"
LABEL_QUEUE="13874b6b-01ff-45cb-a6b8-2580b995b000"
LABEL_RESILIENCE="e61658bc-ffb0-4f64-9345-8f2d854401e3"

LABELS=()

# Guardian
if echo "$COMBINED" | grep -qE "(guardian|gua-|eval|moderation|archetype|severity|guideline)"; then
  LABELS+=("$LABEL_GUARDIAN")
fi

# Billy
if echo "$COMBINED" | grep -qE "(billy|boost|campaign|creator)"; then
  LABELS+=("$LABEL_BILLY")
fi

# Feature
if echo "$COMBINED" | grep -qE "(feature|implement|add|new|create .* skill|create .* system)"; then
  LABELS+=("$LABEL_FEATURE")
fi

# Testing
if echo "$COMBINED" | grep -qE "(test|eval|validation|verify|check)"; then
  LABELS+=("$LABEL_TESTING")
fi

# Monitoring
if echo "$COMBINED" | grep -qE "(monitor|dashboard|metrics|observability|langfuse|trace)"; then
  LABELS+=("$LABEL_MONITORING")
fi

# Resilience
if echo "$COMBINED" | grep -qE "(resilience|reliability|timeout|idle|watchdog|health|failure|retry|error|fix.*kill|fix.*spawn|fix.*agent)"; then
  LABELS+=("$LABEL_RESILIENCE")
fi

# Queue
if echo "$COMBINED" | grep -qE "(queue|auto-queue|dispatch|spawn.*agent)"; then
  LABELS+=("$LABEL_QUEUE")
fi

# Guardrails
if echo "$COMBINED" | grep -qE "(guardrail|safety|validation|preflight|diagnose|classify)"; then
  LABELS+=("$LABEL_GUARDRAILS")
fi

# Deduplicate and output
echo "${LABELS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//'
