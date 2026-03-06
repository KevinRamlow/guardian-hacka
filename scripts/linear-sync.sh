#!/bin/bash
# Linear Task Sync - Monitor sub-agents and update Linear tasks automatically
# OPTIMIZED: Only checks tasks with active sessions, skips dead ones early

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

# Source Linear config
if [[ -f "$WORKSPACE_DIR/.env.linear" ]]; then
  source "$WORKSPACE_DIR/.env.linear"
else
  echo "Error: .env.linear not found"
  exit 1
fi

# Check API key
if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "Error: LINEAR_API_KEY not set"
  exit 1
fi

# Function to call Linear GraphQL API
linear_query() {
  local query="$1"
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$query" | jq -Rs .)}" | jq -r '.data // .errors'
}

# Function to add comment to Linear task
add_task_comment() {
  local issue_id="$1"
  local comment="$2"
  local escaped_comment=$(echo "$comment" | jq -Rs .)
  local mutation="mutation {
    commentCreate(input: { issueId: \"$issue_id\", body: $escaped_comment }) {
      success
    }
  }"
  linear_query "$mutation"
}

# Function to update task status
update_task_status() {
  local issue_id="$1"
  local status_name="$2"
  local state_query="{
    workflowStates(filter: { name: { eq: \"$status_name\" } }) {
      nodes { id name }
    }
  }"
  local state_id=$(linear_query "$state_query" | jq -r '.workflowStates.nodes[0].id // empty')
  if [[ -z "$state_id" ]]; then
    echo "  Warning: Status '$status_name' not found"
    return 1
  fi
  local mutation="mutation {
    issueUpdate(id: \"$issue_id\", input: { stateId: \"$state_id\" }) {
      success
      issue { identifier state { name } }
    }
  }"
  linear_query "$mutation"
}

# Get active subagents FIRST — if none, skip everything
get_active_sessions() {
  openclaw sessions-list --requester agent:main:main --json 2>/dev/null || echo '{"active":[],"recent":[]}'
}

sync_tasks() {
  echo "Starting Linear task sync..."

  # Step 1: Get active sessions first
  local all_agents=$(get_active_sessions)
  local active_count=$(echo "$all_agents" | jq '[.active[]?] | length')
  local recent_count=$(echo "$all_agents" | jq '[.recent[]?] | length')

  echo "  Active sessions: $active_count, Recent: $recent_count"

  # If nothing active or recently completed, skip the Linear API call entirely
  if [[ "$active_count" -eq 0 && "$recent_count" -eq 0 ]]; then
    echo "  No active or recent sessions — skipping Linear query"
    echo "Sync complete (no-op)"
    return 0
  fi

  # Step 2: Only now fetch Linear tasks (only In Progress ones to reduce payload)
  local tasks_query="{
    issues(filter: { team: { key: { eq: \"CAI\" } }, state: { name: { in: [\"In Progress\", \"In Review\"] } } }) {
      nodes {
        id
        identifier
        title
        state { name }
        description
      }
    }
  }"

  local tasks=$(linear_query "$tasks_query")
  local task_count=$(echo "$tasks" | jq '[.issues.nodes[]?] | length')
  echo "  In-progress Linear tasks: $task_count"

  echo "$tasks" | jq -c '.issues.nodes[]' 2>/dev/null | while read -r task; do
    local task_id=$(echo "$task" | jq -r '.id')
    local task_identifier=$(echo "$task" | jq -r '.identifier')
    local task_title=$(echo "$task" | jq -r '.title')
    local task_description=$(echo "$task" | jq -r '.description // ""')
    local task_state=$(echo "$task" | jq -r '.state.name')

    # Look for session ID in description
    local session_id=$(echo "$task_description" | grep -oP 'Session:\*\* \K[a-f0-9-]{36}|Session: `?\K[a-f0-9-]{36}' | head -1)
    if [[ -z "$session_id" ]]; then
      continue
    fi

    echo "  Checking $task_identifier: $task_title (session: ${session_id:0:8}...)"

    # Check active
    local active_match=$(echo "$all_agents" | jq -r --arg sid "$session_id" \
      '.active[]? | select(.sessionKey | contains($sid)) // empty' | head -1)

    if [[ -n "$active_match" ]]; then
      local status=$(echo "$active_match" | jq -r '.status')
      local runtime_ms=$(echo "$active_match" | jq -r '.runtimeMs')
      local runtime_min=$((runtime_ms / 60000))
      local model=$(echo "$active_match" | jq -r '.model')
      echo "    Active: ${runtime_min}m, model=$model, status=$status"
      continue
    fi

    # Check recently completed
    local done_match=$(echo "$all_agents" | jq -r --arg sid "$session_id" \
      '.recent[]? | select(.sessionKey | contains($sid)) // empty' | head -1)

    if [[ -n "$done_match" ]]; then
      local status=$(echo "$done_match" | jq -r '.status')
      if [[ "$status" == "done" && "$task_state" != "Done" ]]; then
        echo "    Completed — updating to Done"
        update_task_status "$task_id" "Done"
      fi
    fi
  done

  echo "Sync complete"
}

sync_tasks
