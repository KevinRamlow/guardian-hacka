#!/bin/bash
# Human review queue for self-improvement deployments
# Manages review requests for unsafe/large changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUEUE_FILE="$SCRIPT_DIR/pending-reviews.json"

# Add review request
add() {
  local experiment_id=$1
  local target=$2
  local change_summary=$3
  local diff=$4
  local expected_improvement=$5
  
  local entry=$(jq -n \
    --arg exp "$experiment_id" \
    --arg tgt "$target" \
    --arg sum "$change_summary" \
    --arg diff "$diff" \
    --arg imp "$expected_improvement" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      experiment_id: $exp,
      target: $tgt,
      change_summary: $sum,
      diff: $diff,
      expected_improvement: $imp,
      status: "pending",
      created_at: $ts
    }')
  
  jq --argjson entry "$entry" '. += [$entry]' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  
  echo "Review request created for $experiment_id"
}

# List pending reviews
list() {
  local status=${1:-pending}
  
  if [[ ! -s "$QUEUE_FILE" ]] || [[ "$(jq '. | length' "$QUEUE_FILE")" == "0" ]]; then
    echo "No reviews in queue"
    return
  fi
  
  if [[ "$status" == "all" ]]; then
    jq -r '.[] | "\(.experiment_id) | \(.target) | \(.status) | \(.expected_improvement)"' "$QUEUE_FILE"
  else
    jq -r --arg status "$status" '
      .[] | select(.status == $status) | 
      "\(.experiment_id) | \(.target) | \(.expected_improvement)"
    ' "$QUEUE_FILE"
  fi
}

# Show review details
show() {
  local experiment_id=$1
  
  local review=$(jq --arg exp "$experiment_id" '.[] | select(.experiment_id == $exp)' "$QUEUE_FILE")
  
  if [[ -z "$review" ]]; then
    echo "Review not found: $experiment_id"
    return 1
  fi
  
  echo "$review" | jq -r '
    "Experiment: \(.experiment_id)",
    "Target: \(.target)",
    "Summary: \(.change_summary)",
    "Expected improvement: \(.expected_improvement)",
    "Status: \(.status)",
    "Created: \(.created_at)",
    "",
    "Diff:",
    "\(.diff)"
  '
}

# Approve review
approve() {
  local experiment_id=$1
  
  jq --arg exp "$experiment_id" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    map(if .experiment_id == $exp then .status = "approved" | .reviewed_at = $ts else . end)
  ' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  
  echo "Approved: $experiment_id"
  echo "Run: bash experiments/experiment-runner.sh deploy $experiment_id"
}

# Reject review
reject() {
  local experiment_id=$1
  local reason=${2:-No reason provided}
  
  jq --arg exp "$experiment_id" --arg rsn "$reason" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    map(if .experiment_id == $exp then .status = "rejected" | .rejection_reason = $rsn | .reviewed_at = $ts else . end)
  ' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  
  echo "Rejected: $experiment_id"
  echo "Reason: $reason"
}

# Dashboard view
dashboard() {
  echo "=== Review Queue Dashboard ==="
  echo ""
  
  local total=$(jq '. | length' "$QUEUE_FILE")
  local pending=$(jq '[.[] | select(.status == "pending")] | length' "$QUEUE_FILE")
  local approved=$(jq '[.[] | select(.status == "approved")] | length' "$QUEUE_FILE")
  local rejected=$(jq '[.[] | select(.status == "rejected")] | length' "$QUEUE_FILE")
  
  echo "Total reviews: $total"
  echo "Pending: $pending"
  echo "Approved: $approved"
  echo "Rejected: $rejected"
  echo ""
  
  if (( pending > 0 )); then
    echo "Pending reviews:"
    list pending
  fi
}

# Main command router
case "${1:-}" in
  add)
    if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]] || [[ -z "${4:-}" ]] || [[ -z "${5:-}" ]] || [[ -z "${6:-}" ]]; then
      echo "Usage: $0 add <experiment_id> <target> <summary> <diff> <expected_improvement>"
      exit 1
    fi
    add "$2" "$3" "$4" "$5" "$6"
    ;;
  list)
    list "${2:-pending}"
    ;;
  show)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 show <experiment_id>"
      exit 1
    fi
    show "$2"
    ;;
  approve)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 approve <experiment_id>"
      exit 1
    fi
    approve "$2"
    ;;
  reject)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 reject <experiment_id> [reason]"
      exit 1
    fi
    reject "$2" "${3:-No reason provided}"
    ;;
  dashboard)
    dashboard
    ;;
  *)
    echo "Usage: $0 {add|list|show|approve|reject|dashboard}"
    exit 1
    ;;
esac
