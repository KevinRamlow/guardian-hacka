#!/bin/bash
# sync-replicants.sh - Bidirectional sync between Anton and Son of Anton
# Usage: bash scripts/sync-replicants.sh [--dry-run] [--to-son] [--from-son]

set -e

ANTON_ROOT="$HOME/.openclaw/workspace"
SON_HOST="caio@89.167.23.2"
SON_ROOT="/home/caio/workspace"

DRY_RUN=false
TO_SON=true
FROM_SON=true

# Parse args
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --to-son) FROM_SON=false ;;
    --from-son) TO_SON=false ;;
  esac
done

RSYNC_OPTS="-avz --delete"
[[ "$DRY_RUN" == "true" ]] && RSYNC_OPTS="$RSYNC_OPTS --dry-run"

echo "=== Replicant Sync ==="
echo "Anton: $ANTON_ROOT"
echo "Son of Anton: $SON_HOST:$SON_ROOT"
echo "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY-RUN" || echo "LIVE")"
echo ""

# Define what to sync
ANTON_TO_SON=(
  # Architecture docs (Son needs to understand Anton)
  "docs/ANTON-ARCHITECTURE.md"
  "docs/SON-OF-ANTON-SETUP.md"
  "docs/SON-OF-ANTON-HEARTBEAT.md"
  
  # Objectives (Son monitors progress toward these)
  "docs/OBJECTIVES.md"
  
  # State files (Son reads these - READ ONLY)
  ".anton-auto-state.json"
  ".anton-meta-state.json"
  
  # Sync script itself
  "scripts/sync-replicants.sh"
  
  # Skills that both need
  "skills/sync-replicants/"
  
  # NO MEMORY FILES - each entity maintains their own
)

SON_TO_ANTON=(
  # Son's monitoring reports (not memory - objective data)
  "reports/son-monitoring-$(date +%Y-%m-%d).json"
  
  # Son's state snapshot (what he last observed)
  ".son-monitor-state.json"
  
  # Backlog items Son generated
  "backlog/son-generated-tasks.json"
  
  # NO MEMORY FILES - Son keeps his own memories separate
)

# Sync Anton → Son of Anton
if [[ "$TO_SON" == "true" ]]; then
  echo "📤 Syncing Anton → Son of Anton"
  
  for FILE in "${ANTON_TO_SON[@]}"; do
    SRC="$ANTON_ROOT/$FILE"
    
    # Check if exists
    if [[ -e "$SRC" ]]; then
      echo "  → $FILE"
      
      # Create parent dir on remote
      PARENT_DIR=$(dirname "$FILE")
      ssh "$SON_HOST" "mkdir -p $SON_ROOT/$PARENT_DIR" 2>/dev/null || true
      
      # Sync
      if [[ -d "$SRC" ]]; then
        rsync $RSYNC_OPTS "$SRC/" "$SON_HOST:$SON_ROOT/$FILE/"
      else
        rsync $RSYNC_OPTS "$SRC" "$SON_HOST:$SON_ROOT/$FILE"
      fi
    else
      echo "  ⚠️  $FILE not found, skipping"
    fi
  done
  
  echo ""
fi

# Sync Son of Anton → Anton
if [[ "$FROM_SON" == "true" ]]; then
  echo "📥 Syncing Son of Anton → Anton"
  
  for FILE in "${SON_TO_ANTON[@]}"; do
    echo "  ← $FILE"
    
    # Create parent dir locally
    PARENT_DIR=$(dirname "$FILE")
    mkdir -p "$ANTON_ROOT/$PARENT_DIR"
    
    # Sync (ignore if doesn't exist on remote)
    rsync $RSYNC_OPTS "$SON_HOST:$SON_ROOT/$FILE" "$ANTON_ROOT/$FILE" 2>/dev/null || {
      echo "    (not found on Son, skipping)"
    }
  done
  
  echo ""
fi

# Generate sync report
REPORT_FILE="$ANTON_ROOT/logs/sync-replicants-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$ANTON_ROOT/logs"

cat > "$REPORT_FILE" << EOF
Replicant Sync Report
=====================
Date: $(date)
Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY-RUN" || echo "LIVE")

Anton → Son:
$(printf '  - %s\n' "${ANTON_TO_SON[@]}")

Son → Anton:
$(printf '  - %s\n' "${SON_TO_ANTON[@]}")

Status: $([ "$DRY_RUN" == "true" ] && echo "Preview only" || echo "Synced")
EOF

echo "✅ Sync complete"
echo "Report: $REPORT_FILE"

# If not dry-run, notify in #replicants
if [[ "$DRY_RUN" == "false" ]]; then
  bash "$ANTON_ROOT/scripts/notify-slack.sh" "[SYNC] Replicants synchronized (Anton ↔ Son of Anton)" 2>/dev/null || true
fi
