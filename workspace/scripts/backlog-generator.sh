#!/bin/bash
# Backlog Generator — Creates new tasks when Linear Todo is empty
# Called by heartbeat when no tasks remain, or standalone
# Generates tasks from: agent output review, Guardian improvements, infra gaps, proactive analysis
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

WORKSPACE="${OPENCLAW_HOME:-$HOME}/.openclaw/workspace"
AGENT_LOGS="${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/agent-logs"
LOG_PREFIX="[$(date -u +%H:%M)]"

OC_HOME="${OPENCLAW_HOME:-$HOME}/.openclaw"; source "$OC_HOME/.env" 2>/dev/null || true

MIN_BACKLOG=3  # Generate tasks if fewer than this many Todos exist

log() { echo "[$(date -u +%H:%M)] $*"; }

# --- Count current Todo tasks ---
TODO_COUNT=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{issues(filter:{team:{key:{eq:\"AUTO\"}},state:{name:{eq:\"Todo\"}}},first:50){nodes{identifier}}}"}' 2>/dev/null | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('issues',{}).get('nodes',[])))" 2>/dev/null || echo "0")

log "Todo count: $TODO_COUNT (min: $MIN_BACKLOG)"

if [ "$TODO_COUNT" -ge "$MIN_BACKLOG" ]; then
  log "Backlog sufficient, skipping generation"
  exit 0
fi

NEEDED=$((MIN_BACKLOG - TODO_COUNT))
log "Need to generate $NEEDED tasks"

# --- Get AUT team ID ---
TEAM_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query{teams(filter:{key:{eq:\"AUTO\"}}){nodes{id}}}"}' 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data']['teams']['nodes'][0]['id'])" 2>/dev/null)

if [ -z "$TEAM_ID" ]; then
  log "ERROR: Could not fetch AUT team ID from Linear"
  exit 1
fi
log "Team ID: $TEAM_ID"

# --- Get Todo state ID ---
TODO_STATE_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"query{workflowStates(filter:{team:{key:{eq:\\\"AUTO\\\"}},name:{eq:\\\"Todo\\\"}}){nodes{id}}}\"}" 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data']['workflowStates']['nodes'][0]['id'])" 2>/dev/null)

if [ -z "$TODO_STATE_ID" ]; then
  log "ERROR: Could not fetch Todo state ID from Linear"
  exit 1
fi
log "Todo state ID: $TODO_STATE_ID"

# --- Get agent-required label ID (create if missing) ---
LABEL_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"query{issueLabels(filter:{team:{key:{eq:\\\"AUTO\\\"}},name:{eq:\\\"agent-required\\\"}}){nodes{id}}}\"}" 2>/dev/null | \
  python3 -c "import json,sys; nodes=json.load(sys.stdin)['data']['issueLabels']['nodes']; print(nodes[0]['id'] if nodes else '')" 2>/dev/null || echo "")

if [ -z "$LABEL_ID" ]; then
  log "WARN: agent-required label not found, tasks will be created without label"
fi

# --- Gather context for Claude ---
# Recent completed agent logs (last 5 task logs, excluding infra logs)
RECENT_LOGS=""
for logfile in $(ls -t "$AGENT_LOGS"/*.log 2>/dev/null | grep -v 'auto-queue\|watchdog\|master\|gateway\|linear-sync\|langfuse\|fallback' | head -5); do
  RECENT_LOGS="$RECENT_LOGS
--- $(basename "$logfile") ---
$(tail -30 "$logfile" 2>/dev/null)
"
done

# Self-improvement analysis (most recent)
SELF_IMPROVEMENT=""
LATEST_SI=$(ls -t "$WORKSPACE"/memory/self-improvement-*.md 2>/dev/null | head -1)
if [ -n "$LATEST_SI" ]; then
  SELF_IMPROVEMENT=$(cat "$LATEST_SI" 2>/dev/null | head -100)
fi

# --- Generate task ideas via Claude ---
log "Generating $NEEDED task ideas via Claude Haiku..."

PROMPT=$(cat <<'PROMPT_EOF'
You are the backlog generator for Anton, an autonomous AI agent that improves the Guardian content moderation system.

Current state:
- Guardian eval baseline accuracy: 76.86%
- Known improvement areas: severity scoring, archetype detection, edge cases in CAPTIONS/TIME_CONSTRAINTS guidelines
- Infrastructure: auto-queue, watchdog, eval pipeline, Linear integration

Recent agent task logs:
PROMPT_EOF
)

PROMPT="$PROMPT
$RECENT_LOGS

Self-improvement analysis:
$SELF_IMPROVEMENT

Generate exactly $NEEDED concrete, actionable improvement tasks. Each task should target ONE of:
1. Guardian accuracy improvements (prompt tuning, new patterns, edge case handling)
2. Eval pipeline improvements (better datasets, new metrics, regression detection)
3. Infrastructure reliability (agent lifecycle, error recovery, monitoring)

Output ONLY valid JSON array, no markdown, no explanation. Each object has \"title\" (max 80 chars, starts with a verb) and \"description\" (2-3 sentences, specific and actionable).

Example format:
[{\"title\":\"Improve severity scoring for CAPTIONS guideline edge cases\",\"description\":\"Several CAPTIONS evaluations show incorrect severity. Analyze predictions.json for false negatives in CAPTIONS category and add targeted patterns to the severity agent prompt. Target: +1pp accuracy on CAPTIONS subset.\"}]"

# Write prompt to temp file, then build JSON request body via Python
echo "$PROMPT" > /tmp/backlog-prompt.txt

python3 - <<'PYEOF'
import json
prompt = open("/tmp/backlog-prompt.txt").read()
body = {
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 2048,
    "messages": [{"role": "user", "content": prompt}]
}
with open("/tmp/backlog-request.json", "w") as f:
    json.dump(body, f)
PYEOF

TASK_JSON=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d @/tmp/backlog-request.json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['content'][0]['text'])" 2>/dev/null)

rm -f /tmp/backlog-prompt.txt /tmp/backlog-request.json

if [ -z "$TASK_JSON" ]; then
  log "ERROR: Claude returned empty response"
  exit 1
fi

# Extract JSON array — Claude might wrap it in markdown code blocks
TASK_JSON=$(echo "$TASK_JSON" | python3 -c "
import sys, json, re
raw = sys.stdin.read()
# Strip markdown code fences if present
raw = re.sub(r'^\s*\`\`\`json?\s*', '', raw)
raw = re.sub(r'\s*\`\`\`\s*$', '', raw)
# Find the JSON array
match = re.search(r'\[.*\]', raw, re.DOTALL)
if match:
    tasks = json.loads(match.group())
    print(json.dumps(tasks))
else:
    sys.exit(1)
" 2>/dev/null)

if [ -z "$TASK_JSON" ] || [ "$TASK_JSON" = "null" ]; then
  log "ERROR: Could not parse task JSON from Claude output"
  exit 1
fi

TASK_COUNT=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
log "Parsed $TASK_COUNT tasks from Claude"

# --- Create tasks in Linear ---
CREATED=0
for i in $(seq 0 $((TASK_COUNT - 1))); do
  TITLE=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin)[$i]; print(t['title'])" 2>/dev/null)
  DESC=$(echo "$TASK_JSON" | python3 -c "import json,sys; t=json.load(sys.stdin)[$i]; print(t['description'])" 2>/dev/null)

  if [ -z "$TITLE" ]; then
    log "WARN: Skipping task $i — empty title"
    continue
  fi

  # Escape for GraphQL JSON string
  TITLE_ESC=$(echo "$TITLE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])")
  DESC_ESC=$(echo "$DESC" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])")

  # Build mutation input
  if [ -n "$LABEL_ID" ]; then
    LABEL_PART=",labelIds:[\\\"$LABEL_ID\\\"]"
  else
    LABEL_PART=""
  fi

  RESULT=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"mutation{issueCreate(input:{teamId:\\\"$TEAM_ID\\\",title:\\\"$TITLE_ESC\\\",description:\\\"$DESC_ESC\\\",stateId:\\\"$TODO_STATE_ID\\\"$LABEL_PART}){success issue{identifier}}}\"}" 2>/dev/null)

  SUCCESS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueCreate',{}).get('success',False))" 2>/dev/null || echo "False")
  IDENTIFIER=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('issueCreate',{}).get('issue',{}).get('identifier','?'))" 2>/dev/null || echo "?")

  if [ "$SUCCESS" = "True" ]; then
    log "Created $IDENTIFIER: $TITLE"
    CREATED=$((CREATED + 1))
  else
    log "ERROR: Failed to create task: $TITLE"
    log "  Response: $(echo "$RESULT" | head -c 200)"
  fi
done

log "Backlog generation complete: $CREATED/$TASK_COUNT tasks created"
