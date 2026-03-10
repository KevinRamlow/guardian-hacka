#!/bin/bash
# review-hook.sh — Spawn an adversarial reviewer after agent completion
# Called by supervisor.sh when an agent transitions to done
#
# Usage: review-hook.sh <task-id>
#
# Checks if the task is eligible for review (code changes, not already reviewed)
# and spawns a reviewer agent if needed.
set -euo pipefail

TASK_ID="${1:?Task ID required}"
TASK_MGR="/Users/fonsecabc/.openclaw/workspace/scripts/task-manager.sh"
SPAWNER="/Users/fonsecabc/.openclaw/workspace/scripts/spawn-agent.sh"
LINEAR_LOG="/Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
LOGS_DIR="/Users/fonsecabc/.openclaw/tasks/agent-logs"
REVIEW_CONFIG="/Users/fonsecabc/.openclaw/workspace/config/review-config.json"

# Load config (with defaults)
ENABLED=true
MIN_OUTPUT_BYTES=500
REQUIRE_GIT_CHANGES=true
REVIEWER_TIMEOUT=15

if [ -f "$REVIEW_CONFIG" ]; then
  ENABLED=$(python3 -c "import json; c=json.load(open('$REVIEW_CONFIG')); print(str(c.get('enabled', True)).lower())" 2>/dev/null || echo "true")
  MIN_OUTPUT_BYTES=$(python3 -c "import json; c=json.load(open('$REVIEW_CONFIG')); print(c.get('min_output_bytes', 500))" 2>/dev/null || echo "500")
  REQUIRE_GIT_CHANGES=$(python3 -c "import json; c=json.load(open('$REVIEW_CONFIG')); print(str(c.get('require_git_changes', True)).lower())" 2>/dev/null || echo "true")
  REVIEWER_TIMEOUT=$(python3 -c "import json; c=json.load(open('$REVIEW_CONFIG')); print(c.get('reviewer_timeout_min', 15))" 2>/dev/null || echo "15")
fi

[ "$ENABLED" != "true" ] && exit 0

# Get task info
TASK_JSON=$(bash "$TASK_MGR" get "$TASK_ID" 2>/dev/null || echo "NOT_FOUND")
[ "$TASK_JSON" = "NOT_FOUND" ] && exit 0

# Check if task is reviewable
LABEL=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('label',''))" 2>/dev/null || echo "")
SOURCE=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('source',''))" 2>/dev/null || echo "")

# Skip review for: callbacks, reviews themselves, image generation, analysis
case "$SOURCE" in
  process-callback|review|auto-review) exit 0 ;;
esac

# Skip if task label contains "review" (prevent infinite review loops)
echo "$LABEL" | grep -qi "review" && exit 0

# Skip if task ID starts with REVIEW- (prevent infinite review loops)
[[ "$TASK_ID" == REVIEW-* ]] && exit 0

# Skip if no output log (nothing to review)
OUTPUT_LOG="$LOGS_DIR/${TASK_ID}-output.log"
[ ! -f "$OUTPUT_LOG" ] && exit 0
OUTPUT_SIZE=$(stat -f%z "$OUTPUT_LOG" 2>/dev/null || stat -c%s "$OUTPUT_LOG" 2>/dev/null || echo 0)
[ "$OUTPUT_SIZE" -lt "$MIN_OUTPUT_BYTES" ] && exit 0

# Check for git changes in the workspace (if required)
GIT_CHANGES=""
if [ "$REQUIRE_GIT_CHANGES" = "true" ]; then
  cd /Users/fonsecabc/.openclaw/workspace
  GIT_CHANGES=$(git diff --name-only HEAD~1 2>/dev/null | head -20)
  [ -z "$GIT_CHANGES" ] && exit 0
fi

# Check if review already exists in state.json (prevent re-spawn loop)
REVIEW_TASK_ID="REVIEW-${TASK_ID#AUTO-}"
if bash "$TASK_MGR" has "$REVIEW_TASK_ID" 2>/dev/null; then
  echo "[review-hook] $REVIEW_TASK_ID already exists in state.json, skipping"
  exit 0
fi

# Build review prompt
REVIEW_PROMPT=$(cat <<REVIEWEOF
# Adversarial Code Review: $TASK_ID

## Original Task
$LABEL

## Changes to Review
\`\`\`
$GIT_CHANGES
\`\`\`

## Your Mission
Perform a thorough adversarial code review following the 5-step process:

1. **Discover Changes**: Run \`git log --oneline -5\` and \`git diff HEAD~1\` to see actual changes
2. **Build Attack Plan**: Identify acceptance criteria, high-risk areas
3. **Execute Review**: Check implementation vs claims, code quality, test coverage, security
4. **Present Findings**: Minimum 3 findings, categorized as CRITICAL/HIGH/MEDIUM
5. **Verdict**: APPROVE or REQUEST_CHANGES

## Rules
- Be skeptical — assume bugs until proven otherwise
- If tests are claimed to pass, verify they actually exist and run
- Check for security issues (injection, auth bypass, credential exposure)
- Verify error handling covers realistic failure modes

## Output
Log your review to Linear:
\`\`\`bash
bash /Users/fonsecabc/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh $TASK_ID "REVIEW: [verdict]. [N] findings: [summary]" done
\`\`\`

If REQUEST_CHANGES, also create a follow-up task description in the log.
REVIEWEOF
)

# Check if we have slots
SLOTS=$(bash "$TASK_MGR" slots 2>/dev/null || echo "0")
[ "$SLOTS" -le 0 ] && {
  echo "No slots for review, skipping"
  exit 0
}

# Spawn reviewer agent
bash "$SPAWNER" \
  --task "$REVIEW_TASK_ID" \
  --label "review-${TASK_ID}" \
  --role reviewer \
  --timeout "$REVIEWER_TIMEOUT" \
  --source auto-review \
  --force \
  "$REVIEW_PROMPT" 2>/dev/null

if [ $? -eq 0 ]; then
  bash "$LINEAR_LOG" "$TASK_ID" "Auto-review spawned: $REVIEW_TASK_ID" progress 2>/dev/null || true
  echo "Review spawned: $REVIEW_TASK_ID"
else
  echo "Review spawn failed, marking done anyway"
fi
