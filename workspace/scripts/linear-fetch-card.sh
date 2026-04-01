#!/bin/bash
# linear-fetch-card.sh — Fetch a single Linear card by identifier and emit a PM task body
# Usage: linear-fetch-card.sh <CARD-ID>   (e.g. GAS-42)
# Outputs JSON to stdout. Exit codes:
#   0  — card found and eligible (Backlog or To Do)
#   1  — card not found / API error
#   2  — card found but in wrong state (already started / completed / canceled)
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME}"
OC_HOME="$OPENCLAW_HOME/.openclaw"
LINEAR_API="https://api.linear.app/graphql"
MASTER_LOG="$OC_HOME/tasks/agent-logs/master.log"

source "$OC_HOME/.env" 2>/dev/null || true

log() {
  mkdir -p "$(dirname "$MASTER_LOG")"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [$1] [linear-fetch-card] $2" | tee -a "$MASTER_LOG" >&2
}

CARD_ID="${1:-}"
if [ -z "$CARD_ID" ]; then
  log ERROR "Usage: linear-fetch-card.sh <CARD-ID>"
  exit 1
fi

if [ -z "${LINEAR_API_KEY:-}" ]; then
  log ERROR "LINEAR_API_KEY not set"
  exit 1
fi

RESPONSE=$(curl -s -X POST "$LINEAR_API" \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d "{\"query\": \"{ issue(id: \\\"$CARD_ID\\\") { id identifier title description priority priorityLabel state { name type } labels { nodes { name } } assignee { name } createdAt } }\"}")

echo "$RESPONSE" | python3 -c "
import json, sys

data = json.load(sys.stdin)
issue = data.get('data', {}).get('issue')

if not issue:
    print(json.dumps({'found': False, 'reason': 'Card not found or identifier unknown'}))
    sys.exit(1)
state_type = issue.get('state', {}).get('type', '')
state_name = issue.get('state', {}).get('name', '')

# Only Backlog (backlog) and To Do (unstarted) are eligible
if state_type not in ('backlog', 'unstarted'):
    print(json.dumps({'found': True, 'eligible': False, 'state': state_name, 'identifier': issue['identifier']}))
    sys.exit(2)

title       = (issue.get('title') or '')[:200]
description = (issue.get('description') or '')[:1000]
priority    = issue.get('priorityLabel') or 'None'
labels      = ', '.join(l['name'] for l in issue.get('labels', {}).get('nodes', []))
assignee    = (issue.get('assignee') or {}).get('name', 'unassigned')

task_body = (
    '# Linear Task: ' + issue['identifier'] + '\n'
    'Title: '      + title    + '\n'
    'Priority: '   + priority + '\n'
    'Labels: '     + labels   + '\n'
    'Assignee: '   + assignee + '\n\n'
    '## Description\n' + description + '\n\n'
    '## Instructions\n'
    'Analyze this task. Use the eval metrics and per-classification breakdown to build a '
    'detailed improvement plan. Dispatch Analyst with specific forensics context.'
)

print(json.dumps({
    'found':      True,
    'eligible':   True,
    'identifier': issue['identifier'],
    'uuid':       issue['id'],
    'title':      title,
    'state':      state_name,
    'label':      title[:50].replace(' ', '-'),
    'task_body':  task_body
}))
"
