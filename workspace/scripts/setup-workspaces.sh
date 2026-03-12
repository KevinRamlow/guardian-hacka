#!/bin/bash
# Setup sub-agent role workspaces
# Creates workspace-{role}/ dirs with SOUL.md, shared framework files, and symlinks
# Run at container startup or after fresh clone
set -euo pipefail

# OPENCLAW_HOME can be user home (Docker: /home/node) or .openclaw dir (local: $HOME/.openclaw)
OC_BASE="${OPENCLAW_HOME:-$HOME}"
OC_ROOT="${OC_BASE}/.openclaw"
[[ "$OC_BASE" == */.openclaw ]] && OC_ROOT="$OC_BASE"
AGENTS_DIR="$OC_ROOT/workspace/agents"
SHARED_DIR="$AGENTS_DIR/shared"

ROLES=(developer reviewer architect guardian-tuner debugger)
SYMLINKS=(scripts config knowledge skills)

if [ ! -d "$SHARED_DIR" ]; then
  echo "ERROR: Shared agent templates not found: $SHARED_DIR" >&2
  exit 1
fi

for role in "${ROLES[@]}"; do
  WS="$OC_ROOT/workspace-${role}"
  echo "[setup] workspace-${role}"

  mkdir -p "$WS" "$WS/memory"

  # Copy role-specific SOUL.md
  if [ -f "$AGENTS_DIR/${role}/SOUL.md" ]; then
    cp "$AGENTS_DIR/${role}/SOUL.md" "$WS/SOUL.md"
  else
    echo "  WARN: No SOUL.md template for $role"
  fi

  # Copy shared framework files
  for f in AGENTS.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md; do
    if [ -f "$SHARED_DIR/$f" ]; then
      cp "$SHARED_DIR/$f" "$WS/$f"
    fi
  done

  # Create symlinks to shared workspace resources
  for link in "${SYMLINKS[@]}"; do
    target="../workspace/${link}"
    if [ -L "$WS/$link" ]; then
      # Already a symlink — update if target changed
      current=$(readlink "$WS/$link")
      if [ "$current" != "$target" ]; then
        rm "$WS/$link"
        ln -s "$target" "$WS/$link"
        echo "  updated symlink: $link → $target"
      fi
    elif [ ! -e "$WS/$link" ]; then
      ln -s "$target" "$WS/$link"
    fi
  done
done

echo "[setup] All workspaces ready"
