#!/bin/bash
# install-branch-guard.sh — Install pre-commit hook that blocks commits to protected branches
# Run once per repo clone. Idempotent.
#
# Usage: bash scripts/install-branch-guard.sh /path/to/repo [/path/to/repo2 ...]
#
# Protected branches: main, develop, homolog, feat/GUA-*, feat/gua-*
# Anton agents must work on their own branches (e.g., anton/GUA-1101-fix-X)

set -euo pipefail

HOOK_CONTENT='#!/bin/bash
# Branch guard — prevent commits to protected branches
# Installed by install-branch-guard.sh

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")

# Protected branch patterns
PROTECTED_EXACT="main develop homolog"
PROTECTED_PREFIX="feat/GUA- feat/gua- feat/Gua- release/ hotfix/"

# Check exact matches
for p in $PROTECTED_EXACT; do
  if [ "$BRANCH" = "$p" ]; then
    echo ""
    echo "============================================================"
    echo "  BLOCKED: Cannot commit to protected branch: $BRANCH"
    echo "  Create your own branch: git checkout -b anton/$BRANCH-fix"
    echo "============================================================"
    echo ""
    exit 1
  fi
done

# Check prefix matches
for p in $PROTECTED_PREFIX; do
  case "$BRANCH" in
    ${p}*)
      echo ""
      echo "============================================================"
      echo "  BLOCKED: Cannot commit to protected branch: $BRANCH"
      echo "  Create your own branch: git checkout -b anton/${BRANCH}-fix"
      echo "============================================================"
      echo ""
      exit 1
      ;;
  esac
done

# Also run existing pre-commit if present (e.g., ruff/pre-commit framework)
if [ -f "$(dirname "$0")/pre-commit.original" ]; then
  exec "$(dirname "$0")/pre-commit.original" "$@"
fi
'

install_hook() {
  local REPO="$1"
  local HOOKS_DIR="$REPO/.git/hooks"

  if [ ! -d "$HOOKS_DIR" ]; then
    echo "SKIP: Not a git repo: $REPO"
    return
  fi

  # Backup existing pre-commit if it exists and is not our guard
  if [ -f "$HOOKS_DIR/pre-commit" ]; then
    if grep -q "Branch guard" "$HOOKS_DIR/pre-commit" 2>/dev/null; then
      echo "OK: Already installed in $REPO"
      return
    fi
    cp "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit.original"
    echo "  Backed up existing pre-commit → pre-commit.original"
  fi

  echo "$HOOK_CONTENT" > "$HOOKS_DIR/pre-commit"
  chmod +x "$HOOKS_DIR/pre-commit"
  echo "INSTALLED: Branch guard in $REPO"
}

# Default repos if none specified
if [ $# -eq 0 ]; then
  REPOS=(
    "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/guardian-agents-api-real"
    "/Users/fonsecabc/brandlovrs/ai/guardian/guardian-agents-api"
    "/Users/fonsecabc/brandlovrs/ai/guardian/guardian-api"
    "/Users/fonsecabc/brandlovrs/ai/guardian/guardian-ads-treatment"
  )
else
  REPOS=("$@")
fi

for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    install_hook "$repo"
  else
    echo "SKIP: Directory not found: $repo"
  fi
done
