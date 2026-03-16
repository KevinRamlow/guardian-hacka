#!/bin/bash
# git-self.sh — Anton's self-modification git helper
#
# Usage:
#   git-self.sh status                       # show what changed vs remote main
#   git-self.sh commit "msg" [branch-name]   # stage workspace changes, commit, push
#   git-self.sh pr "title" ["body"]          # create PR
#   git-self.sh sync                         # pull latest from remote main into workspace
#
# Flags:
#   --force-reclone   delete /tmp/replicants-self-clone and re-clone fresh
#
# WHY THIS SCRIPT EXISTS:
#   The replicants-anton repo root has workspace/ as a subdirectory.
#   Anton works inside workspace/, but git operations need to happen from the repo root.
#   This script handles that mapping: it clones the full repo to /tmp, copies the live
#   workspace files in, commits, and pushes. No manual git init needed.

set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_HOME:-$HOME}/.openclaw"
WORKSPACE="${OPENCLAW_DIR}/workspace"
CLONE_DIR="/tmp/replicants-self-clone"
REPO="brandlovers-team/replicants-anton"
REMOTE_URL="https://github.com/${REPO}.git"

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[git-self] $*"; }
die() { echo "[git-self] ERROR: $*" >&2; exit 1; }

copy_workspace_to_clone() {
  if command -v rsync &>/dev/null; then
    rsync -a --delete \
      --exclude='.git' \
      --exclude='sessions/' \
      --exclude='**/sessions/' \
      "${WORKSPACE}/" "${CLONE_DIR}/workspace/"
  else
    rm -rf "${CLONE_DIR}/workspace"
    cp -r "${WORKSPACE}" "${CLONE_DIR}/workspace"
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
  echo "Usage: git-self.sh <status|commit|pr|sync> [args] [--force-reclone]"
  echo ""
  echo "  status                       show what changed vs origin/main"
  echo "  commit \"msg\" [branch]        commit workspace changes and push"
  echo "  pr \"title\" [\"body\"]          create GitHub PR from current branch"
  echo "  sync                         pull origin/main into live workspace"
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
    [ ${#ARGS[@]} -ge 2 ] || die "Usage: git-self.sh commit \"message\" [branch-name]"
    COMMIT_MSG="${ARGS[1]}"
    BRANCH_NAME="${ARGS[2]:-anton/self/$(date +%Y%m%d-%H%M%S)}"

    ensure_clone

    log "Fetching latest main..."
    git -C "${CLONE_DIR}" fetch origin main --depth=50

    log "Creating branch '${BRANCH_NAME}' from origin/main..."
    git -C "${CLONE_DIR}" checkout -B "${BRANCH_NAME}" origin/main

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

    log "Pushing '${BRANCH_NAME}' to origin..."
    git -C "${CLONE_DIR}" push -u origin "${BRANCH_NAME}"

    echo ""
    echo "============================================================"
    echo " Branch pushed: ${BRANCH_NAME}"
    echo " Next step: bash scripts/git-self.sh pr \"PR title\""
    echo "============================================================"
    ;;

  # ── pr ─────────────────────────────────────────────────────────────────────
  pr)
    [ ${#ARGS[@]} -ge 2 ] || die "Usage: git-self.sh pr \"title\" [\"body\"]"
    PR_TITLE="${ARGS[1]}"
    PR_BODY="${ARGS[2]:-Automated self-improvement by Anton [bot].}"

    command -v gh &>/dev/null || die "'gh' CLI not found — cannot create PR."

    CURRENT_BRANCH="$(git -C "${CLONE_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "${CURRENT_BRANCH}" ] || die "Could not detect branch in clone. Run 'commit' first."
    [ "${CURRENT_BRANCH}" != "main" ] || die "HEAD is on main — run 'commit' first to create a branch."

    log "Creating PR from '${CURRENT_BRANCH}'..."
    gh pr create \
      --repo "${REPO}" \
      --title "${PR_TITLE}" \
      --body "${PR_BODY}" \
      --base main \
      --head "${CURRENT_BRANCH}"
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
    die "Unknown command '${CMD}'. Valid: status | commit | pr | sync"
    ;;

esac
