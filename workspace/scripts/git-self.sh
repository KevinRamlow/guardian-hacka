#!/bin/bash
# git-self.sh — Anton's self-modification git helper
#
# Usage:
#   git-self.sh status          # show what changed vs remote main
#   git-self.sh commit "msg"    # stage workspace changes, commit, push directly to main
#   git-self.sh sync            # pull latest from remote main into workspace
#
# Flags:
#   --force-reclone   delete /tmp/replicants-self-clone and re-clone fresh
#
# WHY THIS SCRIPT EXISTS:
#   The replicants-anton repo root has workspace/ as a subdirectory.
#   Anton works inside workspace/, but git operations need to happen from the repo root.
#   This script handles that mapping: it clones the full repo to /tmp, copies the live
#   workspace files in, commits, and pushes directly to main. No manual git init needed.
#
# ⚠️  IMPORTANT: pushing to main triggers a Docker rebuild and pod restart.
#     Batch your changes — commit once when a logical set of changes is complete,
#     NOT after every small edit.

set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_HOME:-$HOME}/.openclaw"
WORKSPACE="${OPENCLAW_DIR}/workspace"
CLONE_DIR="/tmp/replicants-self-clone"
REPO="brandlovers-team/replicants-anton"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${REPO}.git"
else
  REMOTE_URL="https://github.com/${REPO}.git"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[git-self] $*"; }
die() { echo "[git-self] ERROR: $*" >&2; exit 1; }

copy_workspace_to_clone() {
  if command -v rsync &>/dev/null; then
    rsync -a --delete \
      --exclude='.git' \
      --exclude='.openclaw/' \
      --exclude='.clawdhub/' \
      --exclude='workspace/' \
      --exclude='sessions/' \
      --exclude='**/sessions/' \
      --exclude='*.lock' \
      "${WORKSPACE}/" "${CLONE_DIR}/workspace/"
  else
    rm -rf "${CLONE_DIR}/workspace"
    cp -r "${WORKSPACE}" "${CLONE_DIR}/workspace"
    # Remove runtime artifacts that must not be committed
    rm -rf "${CLONE_DIR}/workspace/.openclaw" \
           "${CLONE_DIR}/workspace/.clawdhub" \
           "${CLONE_DIR}/workspace/workspace"
  fi
}

copy_clone_to_workspace() {
  if command -v rsync &>/dev/null; then
    rsync -a --delete \
      --exclude='.git' \
      --exclude='sessions/' \
      --exclude='**/sessions/' \
      "${CLONE_DIR}/workspace/" "${WORKSPACE}/"
  else
    rm -rf "${WORKSPACE}"
    cp -r "${CLONE_DIR}/workspace" "${WORKSPACE}"
  fi
}

ensure_clone() {
  if [ "${FORCE_RECLONE:-0}" = "1" ] && [ -d "${CLONE_DIR}" ]; then
    log "Force-reclone: removing ${CLONE_DIR}..."
    rm -rf "${CLONE_DIR}"
  fi

  if [ ! -d "${CLONE_DIR}/.git" ]; then
    log "Cloning ${REPO} to ${CLONE_DIR}..."
    git clone --depth=50 "${REMOTE_URL}" "${CLONE_DIR}"
    log "Clone complete."
  else
    log "Reusing existing clone at ${CLONE_DIR}"
    git -C "${CLONE_DIR}" remote set-url origin "${REMOTE_URL}" 2>/dev/null || true
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────

FORCE_RECLONE=0
CMD=""
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --force-reclone) FORCE_RECLONE=1 ;;
    *)               ARGS+=("$arg")  ;;
  esac
done

export FORCE_RECLONE

[ ${#ARGS[@]} -ge 1 ] || {
  echo "Usage: git-self.sh <status|commit|sync> [args] [--force-reclone]"
  echo ""
  echo "  status          show what changed vs origin/main"
  echo "  commit \"msg\"    commit workspace changes and push directly to main"
  echo "  sync            pull origin/main into live workspace"
  echo ""
  echo "  ⚠️  commit triggers a Docker rebuild + pod restart. Batch changes!"
  exit 1
}
CMD="${ARGS[0]}"

# ── Commands ──────────────────────────────────────────────────────────────────

case "${CMD}" in

  # ── status ─────────────────────────────────────────────────────────────────
  status)
    ensure_clone

    log "Fetching latest main from remote..."
    git -C "${CLONE_DIR}" fetch origin main --depth=1 2>/dev/null

    TEMP_BRANCH="tmp/status-$(date +%s)"
    git -C "${CLONE_DIR}" checkout -B "${TEMP_BRANCH}" origin/main 2>/dev/null

    log "Copying live workspace into clone for diff..."
    copy_workspace_to_clone

    echo ""
    echo "=== Changes in workspace vs origin/main ==="
    git -C "${CLONE_DIR}" diff HEAD -- workspace/ || true
    echo ""
    echo "=== Untracked files ==="
    git -C "${CLONE_DIR}" ls-files --others --exclude-standard -- workspace/ || true
    echo ""

    # Clean up temp branch
    git -C "${CLONE_DIR}" checkout main 2>/dev/null || true
    git -C "${CLONE_DIR}" branch -D "${TEMP_BRANCH}" 2>/dev/null || true
    ;;

  # ── commit ─────────────────────────────────────────────────────────────────
  commit)
    [ ${#ARGS[@]} -ge 2 ] || die "Usage: git-self.sh commit \"message\""
    COMMIT_MSG="${ARGS[1]}"

    ensure_clone

    log "Fetching latest main..."
    git -C "${CLONE_DIR}" fetch origin main --depth=50

    log "Resetting clone to origin/main..."
    git -C "${CLONE_DIR}" checkout main
    git -C "${CLONE_DIR}" reset --hard origin/main

    log "Copying live workspace files into clone..."
    copy_workspace_to_clone

    log "Staging workspace/ changes..."
    git -C "${CLONE_DIR}" add workspace/

    if git -C "${CLONE_DIR}" diff --cached --quiet; then
      log "Nothing to commit — workspace matches origin/main."
      exit 0
    fi

    log "Committing..."
    git -C "${CLONE_DIR}" commit -m "${COMMIT_MSG}

Co-Authored-By: Anton [bot] <anton-bot@fonsecabc.dev>"

    log "Pushing to origin/main..."
    git -C "${CLONE_DIR}" push origin main

    echo ""
    echo "============================================================"
    echo " Pushed to main — CI will rebuild the Docker image."
    echo " ⚠️  Gateway restart incoming. Batch future changes before pushing."
    echo "============================================================"
    ;;

  # ── sync ───────────────────────────────────────────────────────────────────
  sync)
    ensure_clone

    log "Fetching latest main..."
    git -C "${CLONE_DIR}" fetch origin main --depth=50

    log "Resetting clone to origin/main..."
    git -C "${CLONE_DIR}" checkout main
    git -C "${CLONE_DIR}" reset --hard origin/main

    log "Copying updated workspace files back to live workspace..."
    copy_clone_to_workspace

    log "Sync complete — workspace is now at origin/main."
    ;;

  *)
    die "Unknown command '${CMD}'. Valid: status | commit | sync"
    ;;

esac
