#!/bin/bash
# Score agent output quality (0-100)
# Usage: score-agent.sh <CAI-XXX>
set -euo pipefail

TASK_ID="${1:-}"

if [ -z "$TASK_ID" ]; then
  echo "Usage: $0 <CAI-XXX>"
  exit 1
fi

TASK_LOG="/root/.openclaw/tasks/agent-logs/${TASK_ID}-output.log"

if [ ! -f "$TASK_LOG" ]; then
  echo "❌ Task log not found: $TASK_LOG"
  exit 1
fi

SCORE=0
BREAKDOWN=""

# 1. Files changed (30 points max)
FILES_CHANGED=$(git log --all --since="1 day ago" --grep="$TASK_ID" --oneline --name-only 2>/dev/null | grep -v "^[a-f0-9]" | sort -u | wc -l || echo 0)
if [ "$FILES_CHANGED" -gt 0 ]; then
  FILE_POINTS=$((FILES_CHANGED * 10))
  [ "$FILE_POINTS" -gt 30 ] && FILE_POINTS=30
  SCORE=$((SCORE + FILE_POINTS))
  BREAKDOWN="${BREAKDOWN}\n  Files changed: $FILES_CHANGED (+${FILE_POINTS}pts)"
fi

# 2. Lines changed (30 points max)
LINES_CHANGED=$(git log --all --since="1 day ago" --grep="$TASK_ID" --stat 2>/dev/null | grep "files changed" | awk '{print $4+$6}' | head -1 || echo 0)
if [ "$LINES_CHANGED" -gt 0 ]; then
  LINE_POINTS=$((LINES_CHANGED / 10))
  [ "$LINE_POINTS" -gt 30 ] && LINE_POINTS=30
  SCORE=$((SCORE + LINE_POINTS))
  BREAKDOWN="${BREAKDOWN}\n  Lines changed: $LINES_CHANGED (+${LINE_POINTS}pts)"
fi

# 3. Commits made (20 points max)
COMMITS=$(git log --all --since="1 day ago" --grep="$TASK_ID" --oneline 2>/dev/null | wc -l || echo 0)
if [ "$COMMITS" -gt 0 ]; then
  COMMIT_POINTS=$((COMMITS * 10))
  [ "$COMMIT_POINTS" -gt 20 ] && COMMIT_POINTS=20
  SCORE=$((SCORE + COMMIT_POINTS))
  BREAKDOWN="${BREAKDOWN}\n  Commits: $COMMITS (+${COMMIT_POINTS}pts)"
fi

# 4. Validation passed (20 points)
if grep -q "✅.*validated\|✅.*PASS" "$TASK_LOG" 2>/dev/null; then
  SCORE=$((SCORE + 20))
  BREAKDOWN="${BREAKDOWN}\n  Validation: PASSED (+20pts)"
elif grep -q "❌.*failed\|❌.*FAIL" "$TASK_LOG" 2>/dev/null; then
  BREAKDOWN="${BREAKDOWN}\n  Validation: FAILED (+0pts)"
fi

# 5. Output size (code vs empty) (bonus 10 points)
OUTPUT_SIZE=$(wc -c < "$TASK_LOG" 2>/dev/null || echo 0)
if [ "$OUTPUT_SIZE" -gt 1000 ]; then
  SCORE=$((SCORE + 10))
  BREAKDOWN="${BREAKDOWN}\n  Output size: ${OUTPUT_SIZE} bytes (+10pts)"
elif [ "$OUTPUT_SIZE" -lt 100 ]; then
  BREAKDOWN="${BREAKDOWN}\n  Output size: ${OUTPUT_SIZE} bytes (too small, +0pts)"
fi

# Cap at 100
[ "$SCORE" -gt 100 ] && SCORE=100

# Grade
GRADE="F"
[ "$SCORE" -ge 90 ] && GRADE="A"
[ "$SCORE" -ge 80 ] && [ "$SCORE" -lt 90 ] && GRADE="B"
[ "$SCORE" -ge 70 ] && [ "$SCORE" -lt 80 ] && GRADE="C"
[ "$SCORE" -ge 60 ] && [ "$SCORE" -lt 70 ] && GRADE="D"

# Output JSON
cat << EOF
{
  "task": "$TASK_ID",
  "score": $SCORE,
  "grade": "$GRADE",
  "breakdown": {
    "files_changed": $FILES_CHANGED,
    "lines_changed": $LINES_CHANGED,
    "commits": $COMMITS,
    "output_size": $OUTPUT_SIZE
  }
}
EOF

echo ""
echo "========================================="
echo "Score: $SCORE/100 (Grade: $GRADE)"
echo -e "Breakdown:$BREAKDOWN"
