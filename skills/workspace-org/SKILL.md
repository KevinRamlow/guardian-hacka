# Workspace Organization Skill

Keep Anton's workspace clean and organized by automatically removing old temporary files, logs, and orphaned assets.

## Purpose

Prevent workspace bloat by cleaning up:
- Temporary files and old logs
- Orphaned screenshots and downloads
- Empty directories and broken symlinks
- Old session transcripts

## Usage

### Manual Cleanup

**Dry-run mode (safe, shows what would be deleted):**
```bash
cd /Users/fonsecabc/.openclaw/workspace/skills/workspace-org
./scripts/cleanup.sh --dry-run
```

**Interactive mode (prompts before deleting):**
```bash
./scripts/cleanup.sh
```

**Auto mode (no prompts, use with caution):**
```bash
./scripts/cleanup.sh --yes
```

### Automated Weekly Cleanup

**Setup cron job (runs Sundays at 2 AM):**
```bash
./scripts/schedule-weekly.sh
```

**Check cron status:**
```bash
crontab -l | grep workspace-org
```

## What Gets Cleaned

### Temp Files
- `*.tmp` and `*.log` files in workspace root
- Session transcripts older than 30 days
- Orphaned screenshots/downloads in media/inbound

### Old Logs
- Memory logs (`memory/*.md`) older than 90 days
- Task history (`tasks/history/*.md`) older than 90 days
- Agent logs older than 30 days

### Orphaned Assets
- Images in `media/inbound/` with no references in recent files
- Empty directories (excluding protected paths)
- Broken symlinks

## What's Protected

- All current memory files (last 90 days)
- All Linear task state
- All skills (everything in `skills/`)
- Workspace config (SOUL.md, USER.md, AGENTS.md, etc.)
- Recent logs (< 30 days)
- Git repositories

## Output

The script provides:
- Count of files cleaned
- Space freed (in MB)
- Summary by category
- Safe mode by default (prompts before deletion)

## Examples

```bash
# See what would be cleaned without deleting anything
./scripts/cleanup.sh --dry-run

# Clean interactively (prompts for confirmation)
./scripts/cleanup.sh

# Clean automatically (for cron jobs)
./scripts/cleanup.sh --yes

# Setup weekly automated cleanup
./scripts/schedule-weekly.sh
```

## Safety

- **Dry-run first**: Always test with `--dry-run` before actual cleanup
- **Interactive by default**: Prompts before deleting unless `--yes` flag used
- **Protected paths**: Skills, config files, and git repos are never touched
- **Retention policies**: Conservative defaults (30-90 days)
- **Trash support**: Uses `trash` if available (recoverable), falls back to `rm`
