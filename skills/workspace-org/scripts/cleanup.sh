#!/bin/bash
# Workspace Organization - Cleanup Script
# Removes old temp files, logs, and orphaned assets

set -euo pipefail

WORKSPACE="/Users/fonsecabc/.openclaw/workspace"
DRY_RUN=false
AUTO_YES=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--yes]"
            exit 1
            ;;
    esac
done

# Stats
FILES_REMOVED=0
SPACE_FREED=0

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

get_file_size() {
    if [[ -f "$1" ]] || [[ -d "$1" ]]; then
        du -sb "$1" 2>/dev/null | cut -f1 || echo "0"
    else
        echo "0"
    fi
}

remove_file() {
    local file="$1"
    local size=$(get_file_size "$file")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would remove: $file ($(numfmt --to=iec-i --suffix=B $size))"
        FILES_REMOVED=$((FILES_REMOVED + 1))
        SPACE_FREED=$((SPACE_FREED + size))
        return 0
    fi
    
    if [[ "$AUTO_YES" == false ]]; then
        read -p "Remove $file? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "  Skipped"
            return 0
        fi
    fi
    
    if command -v trash &> /dev/null; then
        trash "$file" && FILES_REMOVED=$((FILES_REMOVED + 1)) && SPACE_FREED=$((SPACE_FREED + size))
    else
        rm -rf "$file" && FILES_REMOVED=$((FILES_REMOVED + 1)) && SPACE_FREED=$((SPACE_FREED + size))
    fi
}

# Banner
echo ""
if [[ "$DRY_RUN" == true ]]; then
    log_warn "🧹 WORKSPACE CLEANUP (DRY-RUN MODE)"
    log_warn "No files will be deleted"
else
    log_info "🧹 WORKSPACE CLEANUP"
fi
echo ""

cd "$WORKSPACE" || exit 1

# 1. Clean temp files in workspace root
log_info "Cleaning temp files in workspace root..."
found=0
shopt -s nullglob
for file in *.tmp *.log; do
    if [[ -f "$file" ]]; then
        remove_file "$file"
        found=$((found + 1))
    fi
done
shopt -u nullglob
if [[ $found -eq 0 ]]; then
    echo "  No temp files found"
fi

# 2. Clean old session transcripts (>30 days)
log_info "Cleaning session transcripts older than 30 days..."
if [[ -d ".sessions" ]]; then
    found=0
    while IFS= read -r -d '' file; do
        remove_file "$file"
        found=$((found + 1))
    done < <(find .sessions -type f -name "*.md" -mtime +30 -print0 2>/dev/null)
    if [[ $found -eq 0 ]]; then
        echo "  No old transcripts found"
    fi
else
    echo "  .sessions directory not found"
fi

# 3. Clean orphaned screenshots/downloads
log_info "Cleaning orphaned media in media/inbound..."
if [[ -d "media/inbound" ]]; then
    found=0
    while IFS= read -r -d '' file; do
        # Check if referenced in any recent file
        filename=$(basename "$file")
        if ! grep -r --include="*.md" -q "$filename" memory/ tasks/ 2>/dev/null; then
            remove_file "$file"
            found=$((found + 1))
        fi
    done < <(find media/inbound -type f -mtime +7 -print0 2>/dev/null)
    if [[ $found -eq 0 ]]; then
        echo "  No orphaned media found"
    fi
else
    echo "  media/inbound directory not found"
fi

# 4. Clean old memory logs (>90 days)
log_info "Cleaning memory logs older than 90 days..."
if [[ -d "memory" ]]; then
    found=0
    while IFS= read -r -d '' file; do
        # Keep MEMORY.md
        if [[ "$(basename "$file")" != "MEMORY.md" ]]; then
            remove_file "$file"
            found=$((found + 1))
        fi
    done < <(find memory -type f -name "*.md" -mtime +90 -print0 2>/dev/null)
    if [[ $found -eq 0 ]]; then
        echo "  No old memory logs found"
    fi
else
    echo "  memory directory not found"
fi

# 5. Clean old task history (>90 days)
log_info "Cleaning task history older than 90 days..."
if [[ -d "tasks/history" ]]; then
    found=0
    while IFS= read -r -d '' file; do
        remove_file "$file"
        found=$((found + 1))
    done < <(find tasks/history -type f -name "*.md" -mtime +90 -print0 2>/dev/null)
    if [[ $found -eq 0 ]]; then
        echo "  No old task history found"
    fi
else
    echo "  tasks/history directory not found"
fi

# 6. Clean agent logs (>30 days)
log_info "Cleaning agent logs older than 30 days..."
if [[ -d ".agents" ]] || [[ -d "logs" ]]; then
    found=0
    for dir in .agents logs; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                remove_file "$file"
                found=$((found + 1))
            done < <(find "$dir" -type f \( -name "*.log" -o -name "*.txt" \) -mtime +30 -print0 2>/dev/null)
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "  No old agent logs found"
    fi
else
    echo "  No agent log directories found"
fi

# 7. Clean broken symlinks
log_info "Cleaning broken symlinks..."
found=0
while IFS= read -r -d '' link; do
    # Skip protected directories
    if [[ "$link" =~ ^./skills/ ]] || [[ "$link" =~ ^./.git/ ]]; then
        continue
    fi
    if [[ ! -e "$link" ]]; then
        remove_file "$link"
        found=$((found + 1))
    fi
done < <(find . -type l -print0 2>/dev/null)
if [[ $found -eq 0 ]]; then
    echo "  No broken symlinks found"
fi

# 8. Clean empty directories
log_info "Cleaning empty directories..."
found=0
while IFS= read -r -d '' dir; do
    # Skip protected directories
    if [[ "$dir" =~ ^./skills ]] || [[ "$dir" =~ /.git/ ]] || [[ "$dir" =~ ^./tasks$ ]] || [[ "$dir" =~ ^./memory$ ]] || [[ "$dir" =~ ^./config ]]; then
        continue
    fi
    if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir")" ]]; then
        remove_file "$dir"
        found=$((found + 1))
    fi
done < <(find . -type d -empty -print0 2>/dev/null)
if [[ $found -eq 0 ]]; then
    echo "  No empty directories found"
fi

# Summary
echo ""
log_success "═══════════════════════════════════════"
if [[ "$DRY_RUN" == true ]]; then
    log_success "SUMMARY (DRY-RUN)"
else
    log_success "SUMMARY"
fi
log_success "═══════════════════════════════════════"
echo -e "${GREEN}Files cleaned:${NC} $FILES_REMOVED"
echo -e "${GREEN}Space freed:${NC} $(numfmt --to=iec-i --suffix=B $SPACE_FREED) ($(echo "scale=2; $SPACE_FREED / 1048576" | bc)MB)"
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    log_warn "This was a dry-run. No files were actually deleted."
    log_info "Run without --dry-run to perform cleanup."
fi
echo ""
