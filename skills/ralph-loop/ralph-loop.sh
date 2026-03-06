#!/usr/bin/env bash
# Ralph Loop — Iterative agent orchestration with fresh context per story
# Based on snarktank/ralph, adapted for OpenClaw sessions_spawn
set -euo pipefail

RALPH_DIR="/root/.openclaw/tasks/ralph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Ralph Loop — Iterative Agent Orchestration

Usage: ralph-loop.sh <command> [args]

Commands:
  create <id> <desc> [branch]         Create new project PRD
  add-story <id> <title> <desc> <ac>  Add story (ac = JSON array of criteria)
  next <id>                           Get spawn task text for next story
  pass <id> <story> [learnings]       Mark story passed + append learnings
  fail <id> <story> <reason> [learn]  Mark story failed + append learnings
  status <id>                         Show project status
  status-json <id>                    Machine-readable status
  list                                List all projects
  reset <id> <story>                  Reset story to not-passed
  
Examples:
  ralph-loop.sh create guardian-sev3 "Tune severity 3 boundary" experiment/sev3
  ralph-loop.sh add-story guardian-sev3 "Analyze disagreements" "Query MySQL for sev3 disagreements" '["SQL returns results","3+ patterns found"]'
  ralph-loop.sh next guardian-sev3
  ralph-loop.sh pass guardian-sev3 S-001 "Found that color guidelines cause 40% of sev3 disagreements"
EOF
  exit 1
}

ensure_project() {
  local ID="$1"
  local DIR="$RALPH_DIR/$ID"
  if [[ ! -d "$DIR" ]]; then
    echo "ERROR: Project '$ID' not found. Use 'create' first."
    exit 1
  fi
}

# ── CREATE ──
cmd_create() {
  local ID="${1:?Project ID required}"
  local DESC="${2:?Description required}"
  local BRANCH="${3:-ralph/$ID}"
  local DIR="$RALPH_DIR/$ID"
  
  mkdir -p "$DIR"
  
  if [[ -f "$DIR/prd.json" ]]; then
    echo "Project '$ID' already exists at $DIR"
    exit 1
  fi
  
  cat > "$DIR/prd.json" <<PRDJSON
{
  "project": "$ID",
  "branchName": "$BRANCH",
  "description": "$DESC",
  "maxIterations": 10,
  "currentIteration": 0,
  "runtime": "subagent",
  "model": "anthropic/claude-sonnet-4-5",
  "cwd": "/root/.openclaw/workspace",
  "stories": [],
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
PRDJSON

  cat > "$DIR/progress.txt" <<PROGRESS
# Ralph Progress Log — $ID
# $DESC
Started: $(date -u)

## Codebase Patterns
(Patterns discovered across iterations — add reusable knowledge here)

---
PROGRESS

  echo "Created project '$ID' at $DIR"
  echo "Next: add stories with 'ralph-loop.sh add-story $ID ...'"
}

# ── ADD STORY ──
cmd_add_story() {
  local ID="${1:?Project ID required}"
  local TITLE="${2:?Title required}"
  local DESC="${3:?Description required}"
  local AC="${4:?Acceptance criteria JSON array required}"
  
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  
  # Auto-generate story ID
  local COUNT=$(jq '.stories | length' "$PFILE")
  local STORY_ID="S-$(printf '%03d' $((COUNT + 1)))"
  local PRIORITY=$((COUNT + 1))
  
  # Add story to PRD
  jq --arg sid "$STORY_ID" \
     --arg title "$TITLE" \
     --arg desc "$DESC" \
     --argjson ac "$AC" \
     --argjson pri "$PRIORITY" \
    '.stories += [{
      id: $sid,
      title: $title,
      description: $desc,
      acceptanceCriteria: $ac,
      priority: $pri,
      passes: false,
      attempts: 0,
      maxAttempts: 3,
      notes: ""
    }]' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  echo "$STORY_ID: $TITLE (priority $PRIORITY)"
}

# ── NEXT ──
cmd_next() {
  local ID="${1:?Project ID required}"
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  local PROG="$RALPH_DIR/$ID/progress.txt"
  
  # Check max iterations
  local MAX_ITER=$(jq -r '.maxIterations' "$PFILE")
  local CUR_ITER=$(jq -r '.currentIteration' "$PFILE")
  if [[ "$CUR_ITER" -ge "$MAX_ITER" ]]; then
    echo "ERROR: Max iterations ($MAX_ITER) reached. Use 'status' to check results."
    exit 1
  fi
  
  # Find highest priority story where passes=false and attempts < maxAttempts
  local STORY=$(jq -r '
    [.stories[] | select(.passes == false and .attempts < .maxAttempts)]
    | sort_by(.priority)
    | first
    | if . then .id else "NONE" end
  ' "$PFILE")
  
  if [[ "$STORY" == "NONE" || "$STORY" == "null" ]]; then
    # Check if all passed
    local ALL_PASSED=$(jq '[.stories[].passes] | all' "$PFILE")
    if [[ "$ALL_PASSED" == "true" ]]; then
      echo "COMPLETE: All stories passed!"
    else
      echo "STUCK: Remaining stories exceeded max attempts. Check 'status' for details."
    fi
    exit 0
  fi
  
  # Increment iteration counter
  jq '.currentIteration += 1' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  # Increment attempt count for this story
  jq --arg sid "$STORY" '
    .stories |= map(if .id == $sid then .attempts += 1 else . end)
  ' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  # Extract story details
  local TITLE=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .title' "$PFILE")
  local DESC=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .description' "$PFILE")
  local AC=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .acceptanceCriteria | map("- [ ] " + .) | join("\n")' "$PFILE")
  local NOTES=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .notes // ""' "$PFILE")
  local ATTEMPT=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .attempts' "$PFILE")
  local MAX_ATT=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .maxAttempts' "$PFILE")
  local BRANCH=$(jq -r '.branchName' "$PFILE")
  local CWD=$(jq -r '.cwd' "$PFILE")
  local PROJECT_DESC=$(jq -r '.description' "$PFILE")
  local ITER=$(jq -r '.currentIteration' "$PFILE")
  
  # Read progress.txt for accumulated learnings
  local PROGRESS=""
  if [[ -f "$PROG" ]]; then
    PROGRESS=$(cat "$PROG")
  fi
  
  # Generate spawn task text
  cat <<TASK
## Ralph Loop — Iteration $ITER | Story $STORY (Attempt $ATTEMPT/$MAX_ATT)

**Project:** $PROJECT_DESC
**Branch:** $BRANCH
**Working directory:** $CWD

---

### Your Task: $TITLE

$DESC

### Acceptance Criteria (ALL must pass)

$AC

### Previous Learnings

<progress_context>
$PROGRESS
</progress_context>

$(if [[ -n "$NOTES" && "$NOTES" != "" ]]; then echo "### Notes from previous attempts"; echo "$NOTES"; fi)

---

### Rules

1. **Work on THIS story only** — do not touch other stories or features
2. **Check the branch** — ensure you're on \`$BRANCH\`. Create from main if needed.
3. **Run quality checks** — tests, typecheck, lint. Do NOT commit broken code.
4. **Commit if checks pass** — message: \`feat: [$STORY] $TITLE\`
5. **Report your results clearly** — for each acceptance criterion, state PASS or FAIL with evidence
6. **Append learnings** — at the end of your response, include a section:

\`\`\`
## Learnings for future iterations
- [Pattern/gotcha/useful context for future agents working on this codebase]
\`\`\`

7. **If blocked** — explain what's blocking and what the next agent should try differently
8. **Keep changes minimal and focused** — only what's needed for this story
TASK
}

# ── PASS ──
cmd_pass() {
  local ID="${1:?Project ID required}"
  local STORY="${2:?Story ID required}"
  local LEARNINGS="${3:-}"
  
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  local PROG="$RALPH_DIR/$ID/progress.txt"
  local ILOG="$RALPH_DIR/$ID/iterations.log"
  
  # Mark story as passed
  jq --arg sid "$STORY" '
    .stories |= map(if .id == $sid then .passes = true else . end)
  ' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  local TITLE=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .title' "$PFILE")
  local ITER=$(jq -r '.currentIteration' "$PFILE")
  
  # Append to progress.txt
  cat >> "$PROG" <<LOG

## [$(date -u +%Y-%m-%dT%H:%M:%SZ)] — $STORY: $TITLE ✅ PASSED (iteration $ITER)
$(if [[ -n "$LEARNINGS" ]]; then echo "**Learnings:**"; echo "$LEARNINGS"; fi)
---
LOG

  # Append to iterations.log
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"iter\":$ITER,\"story\":\"$STORY\",\"result\":\"pass\"}" >> "$ILOG"
  
  # Check if all done
  local REMAINING=$(jq '[.stories[] | select(.passes == false)] | length' "$PFILE")
  if [[ "$REMAINING" -eq 0 ]]; then
    echo "🎉 ALL STORIES PASSED — Project $ID complete!"
  else
    echo "✅ $STORY passed. $REMAINING stories remaining."
  fi
}

# ── FAIL ──
cmd_fail() {
  local ID="${1:?Project ID required}"
  local STORY="${2:?Story ID required}"
  local REASON="${3:?Reason required}"
  local LEARNINGS="${4:-}"
  
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  local PROG="$RALPH_DIR/$ID/progress.txt"
  local ILOG="$RALPH_DIR/$ID/iterations.log"
  
  # Add failure notes to story
  local ATTEMPT=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .attempts' "$PFILE")
  local MAX_ATT=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .maxAttempts' "$PFILE")
  
  jq --arg sid "$STORY" --arg reason "Attempt $ATTEMPT: $REASON" '
    .stories |= map(if .id == $sid then .notes = ((.notes // "") + "\n" + $reason) else . end)
  ' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  local TITLE=$(jq -r --arg sid "$STORY" '.stories[] | select(.id == $sid) | .title' "$PFILE")
  local ITER=$(jq -r '.currentIteration' "$PFILE")
  
  # Append to progress.txt
  cat >> "$PROG" <<LOG

## [$(date -u +%Y-%m-%dT%H:%M:%SZ)] — $STORY: $TITLE ❌ FAILED (iteration $ITER, attempt $ATTEMPT/$MAX_ATT)
**Reason:** $REASON
$(if [[ -n "$LEARNINGS" ]]; then echo "**Learnings:**"; echo "$LEARNINGS"; fi)
---
LOG

  # Append to iterations.log
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"iter\":$ITER,\"story\":\"$STORY\",\"result\":\"fail\",\"reason\":\"$REASON\"}" >> "$ILOG"
  
  if [[ "$ATTEMPT" -ge "$MAX_ATT" ]]; then
    echo "❌ $STORY failed ($ATTEMPT/$MAX_ATT attempts exhausted). Needs manual intervention."
  else
    echo "❌ $STORY failed (attempt $ATTEMPT/$MAX_ATT). Will retry on next iteration."
  fi
}

# ── STATUS ──
cmd_status() {
  local ID="${1:?Project ID required}"
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  
  local DESC=$(jq -r '.description' "$PFILE")
  local BRANCH=$(jq -r '.branchName' "$PFILE")
  local ITER=$(jq -r '.currentIteration' "$PFILE")
  local MAX_ITER=$(jq -r '.maxIterations' "$PFILE")
  local TOTAL=$(jq '.stories | length' "$PFILE")
  local PASSED=$(jq '[.stories[] | select(.passes == true)] | length' "$PFILE")
  local FAILED=$(jq '[.stories[] | select(.passes == false and .attempts >= .maxAttempts)] | length' "$PFILE")
  local REMAINING=$((TOTAL - PASSED - FAILED))
  
  echo "═══ Ralph Loop: $ID ═══"
  echo "$DESC"
  echo "Branch: $BRANCH"
  echo "Iteration: $ITER/$MAX_ITER"
  echo ""
  echo "Stories: $PASSED/$TOTAL passed | $FAILED exhausted | $REMAINING remaining"
  echo ""
  
  jq -r '.stories[] | 
    (if .passes then "  ✅" elif .attempts >= .maxAttempts then "  💀" else "  ⬜" end) + 
    " " + .id + " [pri=" + (.priority|tostring) + " att=" + (.attempts|tostring) + "/" + (.maxAttempts|tostring) + "] " + .title
  ' "$PFILE"
  
  if [[ "$PASSED" -eq "$TOTAL" ]]; then
    echo ""
    echo "🎉 PROJECT COMPLETE"
  elif [[ "$FAILED" -gt 0 ]]; then
    echo ""
    echo "⚠️  $FAILED stories exhausted retries — needs manual intervention"
  fi
}

# ── STATUS JSON ──
cmd_status_json() {
  local ID="${1:?Project ID required}"
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  
  jq '{
    project: .project,
    iteration: .currentIteration,
    maxIterations: .maxIterations,
    total: (.stories | length),
    passed: ([.stories[] | select(.passes == true)] | length),
    failed: ([.stories[] | select(.passes == false and .attempts >= .maxAttempts)] | length),
    remaining: ([.stories[] | select(.passes == false and .attempts < .maxAttempts)] | length),
    complete: ([.stories[].passes] | all),
    stories: [.stories[] | {id, title, passes, attempts, maxAttempts}]
  }' "$PFILE"
}

# ── LIST ──
cmd_list() {
  if [[ ! -d "$RALPH_DIR" ]]; then
    echo "No ralph projects yet."
    exit 0
  fi
  
  for dir in "$RALPH_DIR"/*/; do
    [[ ! -f "$dir/prd.json" ]] && continue
    local ID=$(basename "$dir")
    local DESC=$(jq -r '.description' "$dir/prd.json")
    local PASSED=$(jq '[.stories[] | select(.passes == true)] | length' "$dir/prd.json")
    local TOTAL=$(jq '.stories | length' "$dir/prd.json")
    local ITER=$(jq -r '.currentIteration' "$dir/prd.json")
    echo "  $ID — $DESC ($PASSED/$TOTAL passed, iter $ITER)"
  done
}

# ── RESET ──
cmd_reset() {
  local ID="${1:?Project ID required}"
  local STORY="${2:?Story ID required}"
  
  ensure_project "$ID"
  local PFILE="$RALPH_DIR/$ID/prd.json"
  
  jq --arg sid "$STORY" '
    .stories |= map(if .id == $sid then .passes = false | .attempts = 0 | .notes = "" else . end)
  ' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
  
  echo "Reset $STORY — passes=false, attempts=0"
}

# ── DISPATCH ──
[[ $# -lt 1 ]] && usage

CMD="$1"
shift

case "$CMD" in
  create)     cmd_create "$@" ;;
  add-story)  cmd_add_story "$@" ;;
  next)       cmd_next "$@" ;;
  pass)       cmd_pass "$@" ;;
  fail)       cmd_fail "$@" ;;
  status)     cmd_status "$@" ;;
  status-json) cmd_status_json "$@" ;;
  list)       cmd_list ;;
  reset)      cmd_reset "$@" ;;
  *)          echo "Unknown command: $CMD" && usage ;;
esac
