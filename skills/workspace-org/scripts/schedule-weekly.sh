#!/bin/bash
# Schedule weekly workspace cleanup (Sundays at 2 AM)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup.sh"
LOG_FILE="/Users/fonsecabc/.openclaw/workspace/logs/workspace-cleanup.log"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Cron entry (Sundays at 2 AM, auto-yes mode, log to file)
CRON_ENTRY="0 2 * * 0 $CLEANUP_SCRIPT --yes >> $LOG_FILE 2>&1"

# Check if already scheduled
if crontab -l 2>/dev/null | grep -F "$CLEANUP_SCRIPT" >/dev/null; then
    log_warn "Workspace cleanup is already scheduled in cron"
    echo ""
    echo "Current entry:"
    crontab -l | grep -F "$CLEANUP_SCRIPT"
    echo ""
    read -p "Replace with new schedule? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing schedule"
        exit 0
    fi
    # Remove old entry
    (crontab -l 2>/dev/null | grep -vF "$CLEANUP_SCRIPT") | crontab -
fi

# Add new cron entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

log_success "Scheduled weekly workspace cleanup"
echo ""
echo "Schedule: Sundays at 2:00 AM"
echo "Script:   $CLEANUP_SCRIPT --yes"
echo "Log:      $LOG_FILE"
echo ""
log_info "View cron jobs: crontab -l"
log_info "Edit cron jobs: crontab -e"
log_info "Remove this job: crontab -e (delete the line with $CLEANUP_SCRIPT)"
echo ""
