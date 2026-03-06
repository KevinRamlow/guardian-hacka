#!/bin/bash
# Ralph Manager — Clean lifecycle management for ralph loop agents
# Usage: ralph-manager.sh <command> [args]
set -euo pipefail

RALPH="/root/.openclaw/workspace/skills/ralph-loop/ralph-loop.sh"
LOGGER="/root/.openclaw/workspace/scripts/agent-logger.sh"
LOG="/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh"
RALPH_DIR="/root/.openclaw/tasks/ralph"

# ── CLEANUP: Kill ALL orphan claude processes ──
cmd_cleanup() {
  echo "[$(date -u +%H:%M)] Cleaning up orphan processes..."
  
  # Count before
  local BEFORE
  BEFORE=$(ps aux | grep "[c]laude$" | wc -l)
  
  # Kill all claude-agent-acp and claude processes
  pkill -f "claude-agent-acp" 2>/dev/null || true
  pkill -f "claude" 2>/dev/null || true
  sleep 2
  
  local AFTER
  AFTER=$(ps aux | grep "[c]laude$" | wc -l)
  echo "Cleaned: $BEFORE → $AFTER processes"
  
  # Report memory freed
  free -h | grep Mem | awk '{print "RAM: " $3 " used / " $2 " total"}'
}

# ── STATUS: Show all ralph projects + running processes ──
cmd_status() {
  echo "═══ Ralph Manager Status ═══"
  echo ""
  
  # Running processes
  local CLAUDE_COUNT=$(ps aux | grep "claude$" | grep -v grep | wc -l)
  local ACP_COUNT=$(ps aux | grep "claude-agent-acp" | grep -v grep | wc -l)
  echo "Processes: $CLAUDE_COUNT claude / $ACP_COUNT bridges"
  free -h | grep Mem | awk '{print "RAM: " $3 " used / " $2 " total"}'
  echo ""
  
  # Ralph projects
  echo "Projects:"
  if [ -d "$RALPH_DIR" ]; then
    bash "$RALPH" list 2>/dev/null || echo "  (none)"
  else
    echo "  (none)"
  fi
  echo ""
  
  # ACP sessions (last 30 min)
  python3 -c "
import json, time
now = int(time.time() * 1000)
try:
    store = json.load(open('/root/.openclaw/agents/claude/sessions/sessions.json'))
    recent = [(v.get('label','?'), int((now-v.get('updatedAt',0))/60000), v.get('totalTokens',0))
              for k,v in store.items() if 'acp' in k and (now-v.get('updatedAt',0)) < 1800000]
    if recent:
        print('Recent ACP sessions (30min):')
        for l,a,t in sorted(recent):
            print(f'  {\"🟢\" if a<15 else \"🟡\"} {l} ({a}m, {t}tok)')
    else:
        print('No recent ACP sessions')
except: print('Cannot read sessions')
" 2>/dev/null
}

# ── START: Create project + add stories + spawn first agent ──
cmd_start() {
  local PROJECT_ID="${1:?Project ID required}"
  local LINEAR_TASK="${2:-}"
  
  if [ ! -f "$RALPH_DIR/$PROJECT_ID/prd.json" ]; then
    echo "ERROR: Project $PROJECT_ID not found. Create it first:"
    echo "  ralph-loop.sh create $PROJECT_ID \"description\" \"branch\""
    echo "  ralph-loop.sh add-story $PROJECT_ID ..."
    exit 1
  fi
  
  # Check stories exist
  local STORY_COUNT=$(jq '.stories | length' "$RALPH_DIR/$PROJECT_ID/prd.json")
  if [ "$STORY_COUNT" -eq 0 ]; then
    echo "ERROR: No stories. Add stories first."
    exit 1
  fi
  
  # Get next task text
  local TASK_TEXT=$(bash "$RALPH" next "$PROJECT_ID")
  
  if echo "$TASK_TEXT" | grep -q "^COMPLETE\|^STUCK\|^ERROR"; then
    echo "$TASK_TEXT"
    exit 0
  fi
  
  # Extract story ID from task text
  local STORY_ID=$(echo "$TASK_TEXT" | grep -o 'Story S-[0-9]*' | head -1 | awk '{print $2}')
  local LABEL="ralph-${PROJECT_ID}-${STORY_ID}"
  
  echo "Spawning: $LABEL"
  echo "Task text saved to: /tmp/ralph-spawn-${PROJECT_ID}.md"
  echo "$TASK_TEXT" > "/tmp/ralph-spawn-${PROJECT_ID}.md"
  
  # Log
  [ -n "$LINEAR_TASK" ] && bash "$LOG" "$LINEAR_TASK" "🚀 Ralph spawn: $LABEL ($STORY_ID)" progress 2>/dev/null
  bash "$LOGGER" "$LABEL" spawn "Story $STORY_ID started" "project=$PROJECT_ID" 2>/dev/null
  
  echo ""
  echo "Ready to spawn. Use:"
  echo "  sessions_spawn(runtime='acp', label='$LABEL', task=<content of /tmp/ralph-spawn-${PROJECT_ID}.md>)"
}

# ── EVALUATE: Check agent output + pass/fail story ──
cmd_evaluate() {
  local PROJECT_ID="${1:?Project ID required}"
  local STORY_ID="${2:?Story ID required}"
  local RESULT="${3:?Result: pass or fail}"
  local LEARNINGS="${4:-}"
  local LINEAR_TASK="${5:-}"
  
  if [ "$RESULT" = "pass" ]; then
    bash "$RALPH" pass "$PROJECT_ID" "$STORY_ID" "$LEARNINGS"
    [ -n "$LINEAR_TASK" ] && bash "$LOG" "$LINEAR_TASK" "✅ Ralph $STORY_ID passed: $LEARNINGS" progress 2>/dev/null
    bash "$LOGGER" "ralph-${PROJECT_ID}-${STORY_ID}" complete "PASSED: $LEARNINGS" 2>/dev/null
  else
    local REASON="${LEARNINGS:-unknown failure}"
    bash "$RALPH" fail "$PROJECT_ID" "$STORY_ID" "$REASON"
    [ -n "$LINEAR_TASK" ] && bash "$LOG" "$LINEAR_TASK" "❌ Ralph $STORY_ID failed: $REASON" 2>/dev/null
    bash "$LOGGER" "ralph-${PROJECT_ID}-${STORY_ID}" error "FAILED: $REASON" 2>/dev/null
  fi
  
  # Show what's next
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
Ralph Manager — Agent Lifecycle

Commands:
  cleanup              Kill ALL orphan claude processes
  status               Show projects + running processes + RAM
  start <proj> [task]  Get next story + prepare spawn
  evaluate <proj> <story> <pass|fail> [learnings] [task]

Lifecycle:
  1. cleanup                    → kill zombies
  2. ralph-loop.sh create ...   → create project + stories
  3. ralph-manager.sh start ... → get spawn text
  4. sessions_spawn(...)        → run agent
  5. <agent completes>
  6. evaluate ... pass/fail     → record result
  7. goto 3 (auto-loop)
EOF
    ;;
esac
