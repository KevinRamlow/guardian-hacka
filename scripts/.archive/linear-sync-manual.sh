#!/bin/bash
# Manual Linear Task Sync - Update a specific task with sub-agent status
# Usage: ./linear-sync-manual.sh <task-id> <session-id> <status> <runtime-minutes> <model>

set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <task-id> <session-id> <status> <runtime-minutes> <model>"
  echo ""
  echo "Example:"
  echo "  $0 CAI-35 a4efdc80-3627-4349-a3b0-08dd5503b7fd running 26 anthropic/claude-opus-4-6"
  exit 1
fi

TASK_ID="$1"
SESSION_ID="$2"
STATUS="$3"
RUNTIME_MIN="$4"
MODEL="$5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

# Source Linear config
source "$WORKSPACE_DIR/.env.linear"

# Status emoji
case "$STATUS" in
  running) STATUS_EMOJI="🔄" ;;
  done) STATUS_EMOJI="✅" ;;
  error) STATUS_EMOJI="❌" ;;
  blocked) STATUS_EMOJI="⚠️" ;;
  *) STATUS_EMOJI="📍" ;;
esac

# Generate report
REPORT="**Sub-Agent Status Update** (Auto-generated)

$STATUS_EMOJI **Status:** $STATUS
⏱️ **Runtime:** ${RUNTIME_MIN}m
🤖 **Model:** $MODEL
🔑 **Session:** \`$SESSION_ID\`

_Last updated: $(date -u '+%Y-%m-%d %H:%M UTC')_"

# Get issue ID from identifier
ISSUE_ID=$(node -e "
const api = process.env.LINEAR_API_KEY;

async function getIssueId() {
  const query = \`{
    issues(filter: { identifier: { eq: \"$TASK_ID\" } }) {
      nodes {
        id
        identifier
      }
    }
  }\`;
  
  const res = await fetch('https://api.linear.app/graphql', {
    method: 'POST',
    headers: {
      'Authorization': api,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ query })
  });
  
  const json = await res.json();
  const issueId = json.data?.issues?.nodes[0]?.id;
  if (!issueId) {
    console.error('Task not found: $TASK_ID');
    process.exit(1);
  }
  console.log(issueId);
}

getIssueId();
")

if [[ -z "$ISSUE_ID" ]]; then
  echo "❌ Error: Could not find task $TASK_ID"
  exit 1
fi

# Add comment
node -e "
const api = process.env.LINEAR_API_KEY;

async function addComment() {
  const mutation = \`mutation {
    commentCreate(
      input: {
        issueId: \"$ISSUE_ID\"
        body: $(echo "$REPORT" | jq -Rs .)
      }
    ) {
      success
      comment { id }
    }
  }\`;
  
  const res = await fetch('https://api.linear.app/graphql', {
    method: 'POST',
    headers: {
      'Authorization': api,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ query: mutation })
  });
  
  const json = await res.json();
  if (json.data?.commentCreate?.success) {
    console.log('✅ Updated $TASK_ID with status: $STATUS');
  } else {
    console.error('❌ Failed to update:', json.errors || json);
    process.exit(1);
  }
}

addComment();
"

# If status is "done", update task status too
if [[ "$STATUS" == "done" ]]; then
  echo "  ✅ Marking task as Done..."
  node -e "
  const api = process.env.LINEAR_API_KEY;
  
  async function markDone() {
    // Get Done state ID
    const stateQuery = \`{
      workflowStates(filter: { name: { eq: \"Done\" } }) {
        nodes { id name }
      }
    }\`;
    
    let res = await fetch('https://api.linear.app/graphql', {
      method: 'POST',
      headers: {
        'Authorization': api,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ query: stateQuery })
    });
    
    let json = await res.json();
    const stateId = json.data?.workflowStates?.nodes[0]?.id;
    
    if (!stateId) {
      console.warn('⚠️  Could not find Done status');
      return;
    }
    
    // Update task
    const mutation = \`mutation {
      issueUpdate(
        id: \"$ISSUE_ID\"
        input: { stateId: \"\${stateId}\" }
      ) {
        success
        issue { identifier state { name } }
      }
    }\`;
    
    res = await fetch('https://api.linear.app/graphql', {
      method: 'POST',
      headers: {
        'Authorization': api,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ query: mutation })
    });
    
    json = await res.json();
    if (json.data?.issueUpdate?.success) {
      console.log('  ✅ Task marked as Done');
    }
  }
  
  markDone();
  "
fi
