#!/bin/bash
# Main loop orchestrator for self-improvement system
# Runs the full improvement cycle: observe → analyze → experiment → deploy → meta-learn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/state.json"

# Update state timestamp
update_state() {
  local field=$1
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  jq --arg field "$field" --arg ts "$timestamp" '.[$field] = $ts' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Increment state counter
increment_state() {
  local field=$1
  local amount=${2:-1}
  
  jq --arg field "$field" --argjson amount "$amount" '.[$field] = (.[$field] + $amount)' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Check if previous step data exists
check_dependency() {
  local step=$1
  
  case "$step" in
    analyze)
      # Need observations
      if [[ ! -d "$WORKSPACE_ROOT/observations" ]] || [[ -z "$(ls -A "$WORKSPACE_ROOT/observations" 2>/dev/null)" ]]; then
        echo "WARN: No observations found, skipping analysis" >&2
        return 1
      fi
      ;;
    experiment)
      # Need hypotheses
      if [[ ! -d "$WORKSPACE_ROOT/analysis/hypotheses" ]] || [[ -z "$(ls -A "$WORKSPACE_ROOT/analysis/hypotheses" 2>/dev/null)" ]]; then
        echo "WARN: No hypotheses found, skipping experiment evaluation" >&2
        return 1
      fi
      ;;
    meta)
      # Need experiment results
      if [[ ! -d "$WORKSPACE_ROOT/experiments/results" ]] || [[ -z "$(ls -A "$WORKSPACE_ROOT/experiments/results" 2>/dev/null)" ]]; then
        echo "WARN: No experiment results found, skipping meta-learning" >&2
        return 1
      fi
      ;;
  esac
  
  return 0
}

# Run observers
run_observe() {
  echo "=== Running Observers ==="
  
  if [[ ! -d "$WORKSPACE_ROOT/observers" ]]; then
    echo "ERROR: observers/ directory not found"
    return 1
  fi
  
  # Run all observer scripts
  for observer in "$WORKSPACE_ROOT/observers"/*/observer.sh; do
    if [[ -f "$observer" ]]; then
      observer_name=$(basename "$(dirname "$observer")")
      echo "Running observer: $observer_name"
      
      if bash "$observer"; then
        echo "✓ $observer_name completed"
      else
        echo "✗ $observer_name failed"
      fi
    fi
  done
  
  update_state "last_observe"
  echo "Observation complete"
}

# Run analysis
run_analyze() {
  echo "=== Running Analysis ==="
  
  if ! check_dependency "analyze"; then
    return 1
  fi
  
  if [[ ! -d "$WORKSPACE_ROOT/analyzers" ]]; then
    echo "ERROR: analyzers/ directory not found"
    return 1
  fi
  
  # Run all analyzer scripts
  for analyzer in "$WORKSPACE_ROOT/analyzers"/*/analyzer.sh; do
    if [[ -f "$analyzer" ]]; then
      analyzer_name=$(basename "$(dirname "$analyzer")")
      echo "Running analyzer: $analyzer_name"
      
      if bash "$analyzer"; then
        echo "✓ $analyzer_name completed"
      else
        echo "✗ $analyzer_name failed"
      fi
    fi
  done
  
  update_state "last_analyze"
  echo "Analysis complete"
}

# Run experiment evaluation
run_experiment() {
  echo "=== Running Experiment Evaluation ==="
  
  if ! check_dependency "experiment"; then
    return 1
  fi
  
  if [[ ! -f "$WORKSPACE_ROOT/experiments/experiment-runner.sh" ]]; then
    echo "ERROR: experiment-runner.sh not found"
    return 1
  fi
  
  # Evaluate all active experiments
  bash "$WORKSPACE_ROOT/experiments/experiment-runner.sh" evaluate-all
  
  update_state "last_experiment_eval"
  echo "Experiment evaluation complete"
}

# Run meta-learning
run_meta() {
  echo "=== Running Meta-Learning ==="
  
  if ! check_dependency "meta"; then
    return 1
  fi
  
  if [[ ! -f "$WORKSPACE_ROOT/meta/meta-learner.sh" ]]; then
    echo "ERROR: meta-learner.sh not found"
    return 1
  fi
  
  bash "$WORKSPACE_ROOT/meta/meta-learner.sh"
  
  update_state "last_meta"
  echo "Meta-learning complete"
}

# Run full loop
run_full() {
  echo "=== Running Full Improvement Loop ==="
  
  local start_time=$(date +%s)
  
  # Check budget first
  if ! bash "$SCRIPT_DIR/budget-controller.sh" check daily >/dev/null 2>&1; then
    echo "ERROR: Over daily budget, aborting loop"
    return 1
  fi
  
  # Run all steps
  run_observe || echo "Observe step failed or skipped"
  run_analyze || echo "Analyze step failed or skipped"
  run_experiment || echo "Experiment step failed or skipped"
  
  # Meta-learning only on first Monday of month
  local day_of_month=$(date +%d)
  if [[ "$day_of_month" -le 7 ]] && [[ $(date +%u) -eq 1 ]]; then
    run_meta || echo "Meta-learning step failed or skipped"
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo ""
  echo "=== Loop Complete ==="
  echo "Duration: ${duration}s"
  echo "Status: $(jq -r '.status // "unknown"' "$SCRIPT_DIR/budget-status.json")"
}

# Show status
show_status() {
  echo "=== Self-Improvement Status ==="
  echo ""
  
  echo "Last runs:"
  jq -r '
    "  Observe:    \(.last_observe // "never")",
    "  Analyze:    \(.last_analyze // "never")",
    "  Experiment: \(.last_experiment_eval // "never")",
    "  Meta:       \(.last_meta // "never")"
  ' "$STATE_FILE"
  
  echo ""
  echo "Metrics:"
  jq -r '
    "  Improvements deployed: \(.total_improvements_deployed)",
    "  Total PP gained:       \(.total_pp_gained)",
    "  Total cost:            $\(.total_cost)",
    "  Active experiments:    \(.active_experiments)",
    "  Active probations:     \(.active_probations)"
  ' "$STATE_FILE"
  
  echo ""
  bash "$SCRIPT_DIR/budget-controller.sh" status
}

# Main command router
case "${1:-}" in
  observe)
    run_observe
    ;;
  analyze)
    run_analyze
    ;;
  experiment)
    run_experiment
    ;;
  meta)
    run_meta
    ;;
  full)
    run_full
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 {observe|analyze|experiment|meta|full|status}"
    exit 1
    ;;
esac
