#!/bin/bash
# Task Manager for Anton's orchestration workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
LINEAR_SCRIPT="/Users/fonsecabc/.openclaw/workspace/skills/linear/scripts/linear.sh"
STATE_FILE="/Users/fonsecabc/.openclaw/tasks/state.json"

# Ensure state directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# Initialize state file if doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo '{"active_agents": {}, "active_workflows": {}, "tasks": {}}' > "$STATE_FILE"
fi

# Helper: Call Linear CLI (Anton's workspace)
linear() {
    # Source Anton's Linear config
    if [ -f "/Users/fonsecabc/.openclaw/workspace/.env.linear" ]; then
        source /Users/fonsecabc/.openclaw/workspace/.env.linear
    fi
    source /Users/fonsecabc/.openclaw/workspace/.env.secrets 2>/dev/null; export LINEAR_API_KEY="${LINEAR_API_KEY}"
    export LINEAR_DEFAULT_TEAM="${LINEAR_DEFAULT_TEAM:-AUT}"
    "$LINEAR_SCRIPT" "$@"
}

# Helper: Update state file
update_state() {
    local key="$1"
    local value="$2"
    jq "$key = $value" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Helper: Get from state
get_state() {
    local key="$1"
    jq -r "$key" "$STATE_FILE"
}

cmd_status() {
    echo "=== Anton's Active Work ==="
    echo
    
    # Active sub-agents
    echo "🤖 Active Sub-Agents:"
    subagents_output=$(openclaw sessions list --kinds subagent --active-minutes 300 2>/dev/null || echo "[]")
    if [ "$subagents_output" = "[]" ] || [ -z "$subagents_output" ]; then
        echo "  None running"
    else
        echo "$subagents_output" | jq -r '.[] | "  - \(.label // .sessionKey): \(.lastMessage.content[0:80] // "running")..."'
    fi
    echo
    
    # Active workflows
    echo "🔄 Active Workflows:"
    if [ -d "/Users/fonsecabc/.openclaw/workflows" ]; then
        workflows=$(find /Users/fonsecabc/.openclaw/workflows -name "*-state.json" 2>/dev/null | wc -l)
        if [ "$workflows" -gt 0 ]; then
            for state_file in /Users/fonsecabc/.openclaw/workflows/*-state.json; do
                status=$(jq -r '.status' "$state_file")
                workflow_id=$(jq -r '.workflow_id' "$state_file")
                iteration=$(jq -r '.current_iteration' "$state_file")
                checkpoint=$(jq -r '.current_checkpoint' "$state_file")
                echo "  - $workflow_id: $status (iter $iteration, checkpoint: $checkpoint)"
            done
        else
            echo "  None active"
        fi
    else
        echo "  None active"
    fi
    echo
    
    # Linear tasks with anton-orchestrator label
    echo "📋 Open Tasks (Linear):"
    linear my-issues | grep -i "anton\|gua-1100\|billy" || echo "  None found"
}

cmd_agents() {
    echo "🤖 Active Sub-Agents:"
    openclaw sessions list --kinds subagent --active-minutes 300 2>/dev/null | jq -r '.[] | "- [\(.label // "unlabeled")] \(.sessionKey)\n  Task: \(.lastMessage.content[0:100] // "no description")..."'
}

cmd_workflows() {
    echo "🔄 Active Workflows:"
    if [ -d "/Users/fonsecabc/.openclaw/workflows" ]; then
        for state_file in /Users/fonsecabc/.openclaw/workflows/*-state.json; do
            [ -f "$state_file" ] || continue
            workflow_id=$(jq -r '.workflow_id' "$state_file")
            status=$(jq -r '.status' "$state_file")
            iteration=$(jq -r '.current_iteration' "$state_file")
            checkpoint=$(jq -r '.current_checkpoint' "$state_file")
            variables=$(jq -r '.variables | to_entries | map("\(.key)=\(.value)") | join(", ")' "$state_file")
            
            echo "Workflow: $workflow_id"
            echo "  Status: $status"
            echo "  Iteration: $iteration"
            echo "  Checkpoint: $checkpoint"
            echo "  Variables: $variables"
            echo
        done
    else
        echo "No workflows directory found"
    fi
}

cmd_tasks() {
    echo "📋 Anton's Tasks (Linear):"
    linear my-issues
}

cmd_track_experiment() {
    local exp_id="$1"
    local description="$2"
    local completion_promise="$3"
    
    if [ -z "$exp_id" ] || [ -z "$description" ]; then
        echo "Usage: track-experiment <id> <description> [completion-promise]"
        exit 1
    fi
    
    local title="[EXPERIMENT] $exp_id: $description"
    local body="**Completion Promise:** ${completion_promise:-Not specified}

**Status:** In Progress
**Type:** Experiment
**Tracked by:** Anton Task Manager

This task tracks an experiment run by Anton's sub-agent orchestration."
    
    linear create "$title" "$body"
    echo "✅ Experiment tracked in Linear"
}

cmd_track_agent() {
    local session_key="$1"
    local task_desc="$2"
    
    if [ -z "$session_key" ] || [ -z "$task_desc" ]; then
        echo "Usage: track-agent <session-key> <task-description>"
        exit 1
    fi
    
    local title="[SUB-AGENT] $task_desc"
    local body="**Session:** $session_key
**Status:** Running
**Type:** Sub-agent task

Spawned by Anton orchestrator."
    
    linear create "$title" "$body"
    
    # Update local state
    update_state ".active_agents[\"$session_key\"]" "{\"task\": \"$task_desc\", \"started\": \"$(date -Iseconds)\"}"
    echo "✅ Sub-agent tracked"
}

cmd_create() {
    local title="$1"
    local description="$2"
    local priority="${3:-medium}"
    
    if [ -z "$title" ]; then
        echo "Usage: create <title> [description] [priority]"
        exit 1
    fi
    
    linear create "$title" "$description"
    echo "✅ Task created"
}

cmd_update() {
    local task_id="$1"
    local status="$2"
    
    if [ -z "$task_id" ] || [ -z "$status" ]; then
        echo "Usage: update <task-id> <status>"
        echo "Status: todo|progress|review|done|blocked"
        exit 1
    fi
    
    linear status "$task_id" "$status"
    echo "✅ Task updated to $status"
}

cmd_note() {
    local task_id="$1"
    shift
    local note="$*"
    
    if [ -z "$task_id" ] || [ -z "$note" ]; then
        echo "Usage: note <task-id> <note-text>"
        exit 1
    fi
    
    linear comment "$task_id" "$note"
    echo "✅ Note added"
}

cmd_complete() {
    local task_id="$1"
    shift
    local results="$*"
    
    if [ -z "$task_id" ]; then
        echo "Usage: complete <task-id> [results-summary]"
        exit 1
    fi
    
    if [ -n "$results" ]; then
        linear comment "$task_id" "**Completed:** $results"
    fi
    linear status "$task_id" "done"
    echo "✅ Task marked complete"
}

cmd_standup() {
    echo "=== Daily Standup ($(date +%Y-%m-%d)) ==="
    echo
    echo "📋 Your TODO items:"
    linear my-todos
    echo
    echo "🔥 Urgent/High priority:"
    linear urgent
    echo
    echo "🚧 Recently completed:"
    linear my-issues | grep -i "done" | head -5 || echo "  None"
}

cmd_eod() {
    echo "=== End of Day Summary ($(date +%Y-%m-%d)) ==="
    echo
    
    # Count tasks by status
    total=$(linear my-issues | wc -l)
    done_today=$(linear my-issues | grep -i "done" | wc -l)
    in_progress=$(linear my-issues | grep -i "progress" | wc -l)
    blocked=$(linear my-issues | grep -i "blocked" | wc -l)
    
    echo "📊 Stats:"
    echo "  Total active tasks: $total"
    echo "  Completed today: $done_today"
    echo "  In progress: $in_progress"
    echo "  Blocked: $blocked"
    echo
    echo "✅ Completed Today:"
    linear my-issues | grep -i "done" | head -10 || echo "  None"
}

# Main command router
case "$1" in
    status)
        cmd_status
        ;;
    agents)
        cmd_agents
        ;;
    workflows)
        cmd_workflows
        ;;
    tasks)
        cmd_tasks
        ;;
    track-experiment)
        shift
        cmd_track_experiment "$@"
        ;;
    track-agent)
        shift
        cmd_track_agent "$@"
        ;;
    create)
        shift
        cmd_create "$@"
        ;;
    update)
        shift
        cmd_update "$@"
        ;;
    note)
        shift
        cmd_note "$@"
        ;;
    complete)
        shift
        cmd_complete "$@"
        ;;
    standup)
        cmd_standup
        ;;
    eod)
        cmd_eod
        ;;
    *)
        echo "Anton Task Manager"
        echo
        echo "Usage: $0 <command> [args]"
        echo
        echo "Commands:"
        echo "  status              - Show all active work (agents + workflows + tasks)"
        echo "  agents              - List active sub-agents"
        echo "  workflows           - List active workflows"
        echo "  tasks               - Show Linear tasks"
        echo
        echo "  track-experiment <id> <desc> [promise]  - Track new experiment"
        echo "  track-agent <session> <desc>            - Track new sub-agent"
        echo "  create <title> [desc] [priority]        - Create task"
        echo
        echo "  update <task-id> <status>               - Update task status"
        echo "  note <task-id> <text>                   - Add progress note"
        echo "  complete <task-id> [results]            - Mark complete"
        echo
        echo "  standup                                 - Morning standup summary"
        echo "  eod                                     - End of day summary"
        ;;
esac
