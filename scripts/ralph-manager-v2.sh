#!/bin/bash
# Ralph Manager v2 — Uses spawn-agent.sh + agent-registry.sh
# Replaces direct sessions_spawn with registry-tracked spawning
set -euo pipefail

RALPH="/root/.openclaw/workspace/skills/ralph-loop/ralph-loop.sh"
REGISTRY="/root/.openclaw/workspace/scripts/agent-registry.sh"
SPAWNER="/root/.openclaw/workspace/scripts/spawn-agent.sh"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LINEAR_LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
RALPH_DIR="/root/.openclaw/tasks/ralph"

# ── CLEANUP: Kill orphans via watchdog (don't duplicate logic) ──
cmd_cleanup() {
  echo "[$(date -u +%H:%M)] Running watchdog cleanup..."
  bash /root/.openclaw/workspace/scripts/agent-watchdog-v2.sh
}

# ── STATUS: Registry-based status ──
cmd_status() {
  echo "=== Ralph Manager v2 Status ==="
  echo ""

  # Registry status
  bash "$REGISTRY" list
  echo ""

  # Ralph projects
  echo "Projects:"
  if [ -d "$RALPH_DIR" ]; then
    bash "$RALPH" list 2>/dev/null || echo "  (none)"
  else
    echo "  (none)"
  fi
}

# ── START: Create spawn text + spawn via spawn-agent.sh ──
cmd_start() {
  local PROJECT_ID="${1:?Project ID required}"
  local LINEAR_TASK="${2:-}"

  if [ ! -f "$RALPH_DIR/$PROJECT_ID/prd.json" ]; then
    echo "ERROR: Project $PROJECT_ID not found. Create it first:"
    echo "  ralph-loop.sh create $PROJECT_ID \"description\" \"branch\""
    exit 1
  fi

  # Get PRD config
  local RUNTIME=$(jq -r '.runtime // "subagent"' "$RALPH_DIR/$PROJECT_ID/prd.json")
  local MODEL=$(jq -r '.model // ""' "$RALPH_DIR/$PROJECT_ID/prd.json")
  local CWD=$(jq -r '.cwd // "/root/.openclaw/workspace"' "$RALPH_DIR/$PROJECT_ID/prd.json")
  local TIMEOUT=$(jq -r '.timeoutMin // 25' "$RALPH_DIR/$PROJECT_ID/prd.json" 2>/dev/null || echo 25)

  # Get next task text
  local TASK_TEXT=$(bash "$RALPH" next "$PROJECT_ID")

  if echo "$TASK_TEXT" | grep -q "^COMPLETE\|^STUCK\|^ERROR"; then
    echo "$TASK_TEXT"
    exit 0
  fi

  # Extract story ID
  local STORY_ID=$(echo "$TASK_TEXT" | grep -o 'Story S-[0-9]*' | head -1 | awk '{print $2}')
  local LABEL="ralph-${PROJECT_ID}-${STORY_ID}"

  # Use Linear task ID if provided, otherwise use label as task ID
  local TASK_ID="${LINEAR_TASK:-$LABEL}"

  # Write task file
  local TASK_FILE="/tmp/ralph-spawn-${PROJECT_ID}.md"
  echo "$TASK_TEXT" > "$TASK_FILE"

  # Spawn via unified spawner
  echo "Spawning: $LABEL for task $TASK_ID"

  local SPAWN_ARGS="--task $TASK_ID --label $LABEL --timeout $TIMEOUT --source ralph-loop --runtime $RUNTIME --cwd $CWD --file $TASK_FILE"
  if [ -n "$MODEL" ] && [ "$MODEL" != "null" ] && [ "$MODEL" != "" ]; then
    SPAWN_ARGS="$SPAWN_ARGS --model $MODEL"
  fi

  bash "$SPAWNER" $SPAWN_ARGS

  local EXIT=$?
  if [ $EXIT -eq 0 ]; then
    echo "OK: $LABEL spawned"
    [ -n "$LINEAR_TASK" ] && bash "$LINEAR_LOG" "$LINEAR_TASK" "🚀 Ralph spawn: $LABEL ($STORY_ID)" progress 2>/dev/null || true
  else
    echo "FAILED: spawn returned $EXIT"
    [ -n "$LINEAR_TASK" ] && bash "$LINEAR_LOG" "$LINEAR_TASK" "❌ Ralph spawn failed: $LABEL" blocked 2>/dev/null || true
  fi
}

# ── EVALUATE: Check output + pass/fail story ──
cmd_evaluate() {
  local PROJECT_ID="${1:?Project ID required}"
  local STORY_ID="${2:?Story ID required}"
  local RESULT="${3:?Result: pass or fail}"
  local LEARNINGS="${4:-}"
  local LINEAR_TASK="${5:-}"

  if [ "$RESULT" = "pass" ]; then
    bash "$RALPH" pass "$PROJECT_ID" "$STORY_ID" "$LEARNINGS"
    [ -n "$LINEAR_TASK" ] && bash "$LINEAR_LOG" "$LINEAR_TASK" "✅ Ralph $STORY_ID passed: $LEARNINGS" progress 2>/dev/null || true
  else
    local REASON="${LEARNINGS:-unknown failure}"
    bash "$RALPH" fail "$PROJECT_ID" "$STORY_ID" "$REASON"
    [ -n "$LINEAR_TASK" ] && bash "$LINEAR_LOG" "$LINEAR_TASK" "❌ Ralph $STORY_ID failed: $REASON" 2>/dev/null || true
  fi

  echo ""
  bash "$RALPH" status "$PROJECT_ID"
}

# ── DISPATCH ──
case "${1:-help}" in
  cleanup)   cmd_cleanup ;;
  status)    cmd_status ;;
  start)     shift; cmd_start "$@" ;;
  evaluate)  shift; cmd_evaluate "$@" ;;
  help|*)
    cat <<EOF
Ralph Manager v2 — Registry-based Agent Lifecycle

Commands:
  cleanup              Run watchdog cleanup
  status               Show registry + projects
  start <proj> [task]  Spawn next story via spawn-agent.sh
  evaluate <proj> <story> <pass|fail> [learnings] [task]

Lifecycle:
  1. cleanup                        → kill zombies
  2. ralph-loop.sh create ...       → create project + stories
  3. ralph-manager-v2.sh start ...  → spawn via registry
  4. <agent completes>              → watchdog detects + logs
  5. evaluate ... pass/fail         → record result
  6. goto 3
EOF
    ;;
esac
