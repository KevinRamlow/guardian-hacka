#!/usr/bin/env bash
# Pipeline CLI — manages both long and fast pipelines
set -euo pipefail

TASKS_DIR="/root/.openclaw/tasks"

usage() {
  echo "Usage: pipeline-ctl.sh <pipeline> <command> [args]"
  echo ""
  echo "Pipelines: long | fast"
  echo ""
  echo "Commands:"
  echo "  status                  Show pipeline status"
  echo "  add <ID> <task> [opts]  Add task (--priority N --model M)"
  echo "  pause                   Pause (finish running, no new)"
  echo "  resume                  Resume"
  echo "  retry <ID>              DLQ → queue"
  echo "  retry-all               All DLQ → queue"
  echo "  kill <ID>               Force-kill → DLQ"
  echo "  config <key> <value>    Update config"
  echo "  clear-done              Clear completed"
  echo "  log [N]                 Last N log lines"
  echo ""
  echo "Shortcuts:"
  echo "  pipeline-ctl.sh all     Show both pipelines"
  exit 1
}

[[ $# -lt 1 ]] && usage

# Handle "all" shortcut
if [[ "$1" == "all" ]]; then
  for p in long fast; do
    PFILE="$TASKS_DIR/pipeline-${p}.json"
    [[ ! -f "$PFILE" ]] && continue
    echo "━━━ ${p^^} PIPELINE ━━━"
    DESC=$(jq -r '.description' "$PFILE")
    echo "$DESC"
    echo ""
    RUNNING=$(jq '.running | length' "$PFILE")
    QUEUE=$(jq '.queue | length' "$PFILE")
    DONE=$(jq '.done | length' "$PFILE")
    DLQ=$(jq '.dlq | length' "$PFILE")
    PAUSED=$(jq -r '.paused' "$PFILE")
    MAX=$(jq -r '.config.maxWorkers' "$PFILE")
    RT=$(jq -r '.config.defaultRuntime' "$PFILE")
    echo "State: $([ "$PAUSED" = "true" ] && echo "⏸ PAUSED" || echo "▶ ACTIVE")  |  Runtime: $RT  |  Workers: $RUNNING/$MAX"
    echo "Queue: $QUEUE  |  Done: $DONE  |  DLQ: $DLQ"
    if [[ "$RUNNING" -gt 0 ]]; then
      echo ""
      echo "Running:"
      jq -r '.running[] | "  \(.id) [\(.label)] \(.retries // 0) retries, started \(.startedAt)"' "$PFILE"
    fi
    if [[ "$QUEUE" -gt 0 ]]; then
      echo ""
      echo "Queued:"
      jq -r '.queue[] | "  \(.id) pri=\(.priority // 99)"' "$PFILE"
    fi
    if [[ "$DLQ" -gt 0 ]]; then
      echo ""
      echo "DLQ:"
      jq -r '.dlq[] | "  \(.id) — \(.lastError)"' "$PFILE"
    fi
    echo ""
  done
  exit 0
fi

# Require pipeline name
PIPELINE="$1"
shift

case "$PIPELINE" in
  long|fast) PFILE="$TASKS_DIR/pipeline-${PIPELINE}.json" ;;
  *) echo "Unknown pipeline: $PIPELINE (use: long | fast)" && exit 1 ;;
esac

[[ ! -f "$PFILE" ]] && echo "Pipeline file not found: $PFILE" && exit 1
[[ $# -lt 1 ]] && usage

CMD="$1"
shift

case "$CMD" in
  status)
    RUNNING=$(jq '.running | length' "$PFILE")
    QUEUE=$(jq '.queue | length' "$PFILE")
    DONE=$(jq '.done | length' "$PFILE")
    DLQ=$(jq '.dlq | length' "$PFILE")
    PAUSED=$(jq -r '.paused' "$PFILE")
    MAX=$(jq -r '.config.maxWorkers' "$PFILE")
    RT=$(jq -r '.config.defaultRuntime' "$PFILE")
    echo "=== ${PIPELINE^^} Pipeline ==="
    echo "$(jq -r '.description' "$PFILE")"
    echo "State: $([ "$PAUSED" = "true" ] && echo "⏸ PAUSED" || echo "▶ ACTIVE")  |  Runtime: $RT"
    echo "Workers: $RUNNING/$MAX  |  Queue: $QUEUE  |  Done: $DONE  |  DLQ: $DLQ"
    if [[ "$RUNNING" -gt 0 ]]; then
      echo ""
      jq -r '.running[] | "  ▸ \(.id) [\(.label)] retries=\(.retries // 0) started=\(.startedAt)"' "$PFILE"
    fi
    if [[ "$QUEUE" -gt 0 ]]; then
      echo ""
      jq -r '.queue[] | "  ◦ \(.id) pri=\(.priority // 99) retries=\(.retries // 0)"' "$PFILE"
    fi
    if [[ "$DLQ" -gt 0 ]]; then
      echo ""
      jq -r '.dlq[] | "  ✗ \(.id) error=\(.lastError)"' "$PFILE"
    fi
    echo ""
    jq '.stats' "$PFILE"
    ;;

  add)
    [[ $# -lt 2 ]] && echo "Usage: pipeline-ctl.sh $PIPELINE add <ID> <task> [--priority N] [--model M]" && exit 1
    TASK_ID="$1"; TASK_DESC="$2"; shift 2
    PRIORITY=50; MODEL=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --priority) PRIORITY="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    DEFAULT_MODEL=$(jq -r '.config.defaultModel' "$PFILE")
    [[ -z "$MODEL" ]] && MODEL="$DEFAULT_MODEL"
    DEFAULT_RT=$(jq -r '.config.defaultRuntime' "$PFILE")

    EXISTS=$(jq --arg id "$TASK_ID" '[.queue[], .running[], .dlq[]] | map(select(.id == $id)) | length' "$PFILE")
    [[ "$EXISTS" -gt 0 ]] && echo "ERROR: $TASK_ID already in $PIPELINE pipeline" && exit 1

    jq --arg id "$TASK_ID" --arg task "$TASK_DESC" --argjson pri "$PRIORITY" \
       --arg rt "$DEFAULT_RT" --arg model "$MODEL" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.queue += [{id: $id, task: $task, priority: $pri, runtime: $rt, model: $model, addedAt: $now, retries: 0}] | .queue |= sort_by(.priority)' \
      "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] Added $TASK_ID (priority=$PRIORITY)"
    ;;

  pause)
    jq '.paused = true' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] Paused"
    ;;

  resume)
    jq '.paused = false' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] Resumed"
    ;;

  retry)
    [[ $# -lt 1 ]] && echo "Usage: retry <ID>" && exit 1
    jq --arg id "$1" \
      '(.dlq | to_entries | map(select(.value.id == $id)) | .[0].key) as $idx |
       if $idx != null then .queue += [.dlq[$idx] + {retries: 0, steered: false}] | .dlq |= del(.[$idx])
       else error("Not in DLQ") end' \
      "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] $1 → queue"
    ;;

  retry-all)
    C=$(jq '.dlq | length' "$PFILE")
    jq '.queue += [.dlq[] | . + {retries: 0, steered: false}] | .dlq = []' \
      "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] $C tasks DLQ → queue"
    ;;

  kill)
    [[ $# -lt 1 ]] && echo "Usage: kill <ID>" && exit 1
    LABEL=$(jq -r --arg id "$1" '.running[] | select(.id == $id) | .label // empty' "$PFILE")
    [[ -z "$LABEL" ]] && echo "ERROR: $1 not running in $PIPELINE" && exit 1
    jq --arg id "$1" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '(.running | to_entries | map(select(.value.id == $id)) | .[0].key) as $idx |
       .dlq += [.running[$idx] + {failedAt: $now, lastError: "manual kill"}] | .running |= del(.[$idx])' \
      "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] Killed $1 → DLQ"
    ;;

  config)
    [[ $# -lt 2 ]] && echo "Usage: config <key> <value>" && exit 1
    jq --arg k "$1" --argjson v "$2" '.config[$k] = $v' \
      "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] $1 = $2"
    ;;

  clear-done)
    C=$(jq '.done | length' "$PFILE")
    jq '.done = []' "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
    echo "[$PIPELINE] Cleared $C done"
    ;;

  log)
    LINES="${1:-20}"
    grep "\[$PIPELINE\]" "$TASKS_DIR/pipeline.log" 2>/dev/null | tail -n "$LINES" || echo "(no logs)"
    ;;

  *) usage ;;
esac
