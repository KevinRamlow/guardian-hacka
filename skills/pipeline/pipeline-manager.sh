#!/usr/bin/env bash
# Pipeline Manager — Health Check for BOTH pipelines (system crontab, every 60s)
set -euo pipefail

TASKS_DIR="/root/.openclaw/tasks"
LOG_FILE="$TASKS_DIR/pipeline.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE"; }

check_pipeline() {
  local PFILE="$1"
  local PNAME=$(jq -r '.name' "$PFILE")

  [[ ! -f "$PFILE" ]] && return
  [[ "$(jq -r '.paused' "$PFILE")" == "true" ]] && return

  local STALL_TIMEOUT=$(jq -r '.config.stallTimeoutMin' "$PFILE")
  local STEER_GRACE=$(jq -r '.config.steerGraceMin' "$PFILE")
  local RETRY_MAX=$(jq -r '.config.retryMax' "$PFILE")
  local MAX_WORKERS=$(jq -r '.config.maxWorkers' "$PFILE")
  local NOW_S=$(date +%s)
  local CHANGED="false"
  local NEEDS_SPAWN="false"
  local RUNNING_COUNT=$(jq '.running | length' "$PFILE")

  # Health check running tasks
  for i in $(seq 0 $((RUNNING_COUNT - 1))); do
    local TASK_ID=$(jq -r ".running[$i].id // empty" "$PFILE")
    [[ -z "$TASK_ID" ]] && continue

    local LABEL=$(jq -r ".running[$i].label // empty" "$PFILE")
    local LAST_HB=$(jq -r ".running[$i].lastHeartbeat // .running[$i].startedAt // empty" "$PFILE")
    local STEERED=$(jq -r ".running[$i].steered // false" "$PFILE")
    local RETRIES=$(jq -r ".running[$i].retries // 0" "$PFILE")

    [[ -z "$LAST_HB" ]] && continue

    local HB_EPOCH=$(date -d "$LAST_HB" +%s 2>/dev/null || echo 0)
    [[ "$HB_EPOCH" == "0" ]] && continue
    local ELAPSED_MIN=$(( (NOW_S - HB_EPOCH) / 60 ))

    # Check Linear for recent activity (heartbeat proxy)
    if [[ "$ELAPSED_MIN" -ge "$STALL_TIMEOUT" ]]; then
      source "$TASKS_DIR/../.openclaw/workspace/.env.linear" 2>/dev/null || \
        source /root/.openclaw/workspace/.env.linear 2>/dev/null || true

      if [[ -n "${LINEAR_API_KEY:-}" ]]; then
        local LAST_COMMENT_AT=$(curl -sf -X POST https://api.linear.app/graphql \
          -H "Authorization: $LINEAR_API_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"query\":\"query{issue(id:\\\"$TASK_ID\\\"){comments(first:1,orderBy:createdAt){nodes{createdAt}}}}\"}" 2>/dev/null | \
          jq -r '.data.issue.comments.nodes[0].createdAt // empty' 2>/dev/null)

        if [[ -n "$LAST_COMMENT_AT" ]]; then
          local COMMENT_EPOCH=$(date -d "$LAST_COMMENT_AT" +%s 2>/dev/null || echo 0)
          if [[ "$COMMENT_EPOCH" -gt "$HB_EPOCH" ]]; then
            jq --argjson idx "$i" --arg hb "$LAST_COMMENT_AT" \
              '.running[$idx].lastHeartbeat = $hb | .running[$idx].steered = false' \
              "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
            CHANGED="true"
            continue
          fi
        fi
      fi

      if [[ "$STEERED" == "false" ]]; then
        log "[$PNAME] STALL: $TASK_ID stalled ${ELAPSED_MIN}min — marking for steer"
        jq --argjson idx "$i" '.running[$idx].steered = true | .running[$idx].needsSteer = true' \
          "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
        CHANGED="true"

      elif [[ "$ELAPSED_MIN" -ge "$((STALL_TIMEOUT + STEER_GRACE))" ]]; then
        if [[ "$RETRIES" -ge "$RETRY_MAX" ]]; then
          log "[$PNAME] DLQ: $TASK_ID ${ELAPSED_MIN}min stalled, ${RETRIES} retries → DLQ"
          jq --argjson idx "$i" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '.dlq += [.running[$idx] + {failedAt: $now, lastError: "stalled after steer, max retries"}] | .running |= del(.[$idx]) | .stats.totalFailed += 1' \
            "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
          echo "$PNAME:$TASK_ID" >> "$TASKS_DIR/dlq-alert.trigger"
          CHANGED="true"
        else
          log "[$PNAME] RETRY: $TASK_ID → re-queue (retry $((RETRIES+1))/$RETRY_MAX)"
          jq --argjson idx "$i" --argjson retries "$((RETRIES+1))" \
            '.queue = [.running[$idx] + {retries: $retries, steered: false, needsSteer: false}] + .queue | .running |= del(.[$idx]) | .stats.totalRetried += 1' \
            "$PFILE" > "${PFILE}.tmp" && mv "${PFILE}.tmp" "$PFILE"
          NEEDS_SPAWN="true"
          CHANGED="true"
        fi
        # Indices shifted — restart this pipeline check
        check_pipeline "$PFILE"
        return
      fi
    fi
  done

  # Check if queue needs processing
  local RUNNING_NOW=$(jq '.running | length' "$PFILE")
  local QUEUE_LEN=$(jq '.queue | length' "$PFILE")
  local SLOTS=$((MAX_WORKERS - RUNNING_NOW))

  if [[ "$SLOTS" -gt 0 && "$QUEUE_LEN" -gt 0 ]]; then
    NEEDS_SPAWN="true"
  fi

  if [[ "$NEEDS_SPAWN" == "true" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TASKS_DIR/spawn-${PNAME}.trigger"
    log "[$PNAME] TRIGGER: spawn needed (queue=$QUEUE_LEN, slots=$SLOTS)"
  fi

  if [[ "$CHANGED" == "true" || "$NEEDS_SPAWN" == "true" ]]; then
    local FINAL_R=$(jq '.running | length' "$PFILE")
    local FINAL_Q=$(jq '.queue | length' "$PFILE")
    local FINAL_D=$(jq '.dlq | length' "$PFILE")
    log "[$PNAME] STATUS: running=$FINAL_R queue=$FINAL_Q dlq=$FINAL_D"
  fi
}

# Run both pipelines
check_pipeline "$TASKS_DIR/pipeline-long.json"
check_pipeline "$TASKS_DIR/pipeline-fast.json"
