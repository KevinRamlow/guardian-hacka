**STATUS: DEPRECATED**

---
name: sync-replicants
description: Bidirectional synchronization between Anton (Mac) and Son of Anton (VPS). Keeps architecture docs, objectives, state files, and memories in sync.
triggers:
  - "sync with son of anton"
  - "sync replicants"
  - "update son of anton"
  - "sync to son"
  - "sync from son"
---

# Sync Replicants - Anton ↔ Son of Anton Synchronization

## Purpose

Keep Anton (Caio's Mac) and Son of Anton (89.167.23.2) synchronized so they:
- Share architecture knowledge (docs, objectives)
- Monitor each other's state (observable data)
- Coordinate on shared goals
- Exchange structured reports (not memories)

## Philosophy: Separate Entities

**Anton and Son of Anton are distinct entities**, not clones:

- **Shared:** Objective knowledge (docs, code, goals, state)
- **Separate:** Subjective experience (memories, observations, identity)

**Why separate memories?**
- Anton's memories reflect his work (Guardian improvements, coding)
- Son's memories reflect his observations (monitoring, coordination)
- Merging would blur identity and responsibility
- Each maintains their own perspective and learning

**Communication:** Structured reports, not memory merge
- Son sends monitoring reports (JSON, objective data)
- Anton reads reports but doesn't import Son's memories
- Son reads Anton's state but doesn't import Anton's memories

## When to Sync

### Automatic (Scheduled)
- **Every 4 hours:** After Guardian loop completes (aligned with monitoring)
- **Every 24 hours:** After Meta loop completes
- **On significant changes:** OBJECTIVES.md edited, new architecture docs

### Manual (On Demand)
- After major SOUL.md changes
- After creating new skills/scripts
- After architecture updates
- Before major changes (to backup current state)

## What Gets Synced

### Anton → Son of Anton (📤)

**Architecture & Docs (Shared Knowledge):**
- `docs/ANTON-ARCHITECTURE.md` - System design
- `docs/SON-OF-ANTON-SETUP.md` - Son's monitoring guide
- `docs/SON-OF-ANTON-HEARTBEAT.md` - Heartbeat logic
- `OBJECTIVES.md` - Current goals

**State Files (Observable Data):**
- `.anton-auto-state.json` - Guardian loop state (READ ONLY for Son)
- `.anton-meta-state.json` - Meta loop state (READ ONLY for Son)

**Scripts & Skills (Shared Code):**
- `scripts/sync-replicants.sh` - Sync script itself
- `skills/sync-replicants/` - This skill

**NOT Synced:**
- ❌ `memory/` - Anton's memories stay with Anton
- ❌ `MEMORY.md` - Anton's long-term memory is separate

### Son of Anton → Anton (📥)

**Monitoring Reports (Structured Data):**
- `reports/son-monitoring-YYYY-MM-DD.json` - Objective observations

**Son's State:**
- `.son-monitor-state.json` - Last monitoring snapshot

**Generated Work:**
- `backlog/son-generated-tasks.json` - Tasks Son created

**NOT Synced:**
- ❌ Son's memory files - Son's memories stay with Son
- ❌ Son's SOUL.md - Each entity maintains their own identity

## Usage

### Basic Sync (Bidirectional)
```bash
bash scripts/sync-replicants.sh
```

Syncs everything both ways.

### Preview Changes (Dry Run)
```bash
bash scripts/sync-replicants.sh --dry-run
```

Shows what would be synced without actually doing it.

### One-Way Sync
```bash
# Anton → Son only
bash scripts/sync-replicants.sh --to-son

# Son → Anton only
bash scripts/sync-replicants.sh --from-son
```

### From Son of Anton Side
```bash
# Son of Anton can also initiate sync
ssh caio@<anton-mac-ip> "bash ~/.openclaw/workspace/scripts/sync-replicants.sh --from-son"
```

## Setup Requirements

### SSH Keys
Son of Anton must have passwordless SSH to Anton's Mac:

```bash
# On Son of Anton (89.167.23.2)
ssh-keygen -t ed25519 -C "son-of-anton"
cat ~/.ssh/id_ed25519.pub

# On Anton (Caio's Mac)
echo "<pubkey>" >> ~/.ssh/authorized_keys

# Test
ssh caio@<anton-ip> "echo 'Connected!'"
```

### Directory Structure
Both machines need:
```
~/.openclaw/workspace/
├── docs/
├── memory/
├── scripts/
├── skills/
├── logs/
├── backlog/
└── [state files]
```

Son of Anton uses `/home/caio/workspace/` instead of `~/.openclaw/workspace/`.

## Automated Sync Schedule

### Via Launchd (Anton's Mac)
```xml
<!-- ~/Library/LaunchAgents/com.anton.sync-replicants.plist -->
<key>StartInterval</key>
<integer>14400</integer>  <!-- 4 hours -->
```

Load:
```bash
launchctl load ~/Library/LaunchAgents/com.anton.sync-replicants.plist
```

### Via Cron (Son of Anton's VPS)
```cron
# Sync every 4 hours
0 */4 * * * ssh caio@<anton-ip> "bash ~/.openclaw/workspace/scripts/sync-replicants.sh" >> /home/caio/logs/sync.log 2>&1
```

## Conflict Resolution

### File Conflicts
If both sides modified the same file:
- **State files:** Son's view wins (he's the observer)
- **Objectives:** Anton's version wins (Caio edits locally)
- **Memory files:** Merge manually (both have unique observations)
- **Docs:** Anton's version wins (primary source)

### Handling Conflicts Manually
```bash
# Check for conflicts
bash scripts/sync-replicants.sh --dry-run

# If conflicts detected:
# 1. Backup both versions
# 2. Decide which wins
# 3. Sync one-way
bash scripts/sync-replicants.sh --to-son  # or --from-son
```

## Sync Health Check

```bash
# Check last sync time
ls -lh ~/.openclaw/workspace/logs/sync-replicants-*.log | tail -1

# Verify Son has latest
ssh caio@89.167.23.2 "stat /home/caio/workspace/OBJECTIVES.md"

# Compare file checksums
md5 ~/.openclaw/workspace/OBJECTIVES.md
ssh caio@89.167.23.2 "md5sum /home/caio/workspace/OBJECTIVES.md"
```

## Integration with Auto-Loops

### Guardian Loop (Anton)
After each cycle:
```bash
# At end of anton-auto-loop.sh
if [[ "$DELTA" -ge 1.0 ]]; then
  # Committed improvement
  bash scripts/sync-replicants.sh --to-son
fi
```

### Meta Loop (Anton)
After improvements:
```bash
# At end of anton-meta-loop.sh
if [[ ${#IMPROVEMENTS[@]} -gt 0 ]]; then
  # Committed meta-improvements
  bash scripts/sync-replicants.sh --to-son
fi
```

### Monitoring Loop (Son of Anton)
After posting status:
```bash
# In Son's heartbeat
# Sync Son's observations back to Anton
rsync logs/son-monitoring.log caio@<anton-ip>:~/.openclaw/workspace/logs/
```

## Example Sync Flow

**Scenario:** Anton completes Guardian loop, improves accuracy +1.2pp

```
1. Anton commits changes to git
2. Updates .anton-auto-state.json (baseline: 79.3% → 80.5%)
3. Runs sync-replicants.sh --to-son
4. Son receives:
   - New baseline in .anton-auto-state.json
   - Today's memory with improvement details
   - Updated OBJECTIVES.md (if modified)
5. Son's next heartbeat sees new baseline
6. Son posts to #replicants: "Guardian: 79.3% → 80.5% (+1.2pp)"
7. Son logs observation to logs/son-monitoring.log
8. On next sync, Anton receives Son's log
9. Both are in sync
```

## Troubleshooting

### "Permission denied" errors
```bash
# Fix SSH keys
ssh-copy-id caio@<anton-ip>  # from Son

# Or manually
cat ~/.ssh/id_ed25519.pub | ssh caio@<anton-ip> "cat >> ~/.ssh/authorized_keys"
```

### "No such file or directory"
```bash
# Create missing directories
ssh caio@89.167.23.2 "mkdir -p /home/caio/workspace/{docs,memory,scripts,skills,logs,backlog}"
```

### Sync taking too long
```bash
# Check what's being transferred
bash scripts/sync-replicants.sh --dry-run

# Exclude large files if needed (edit sync-replicants.sh)
RSYNC_OPTS="$RSYNC_OPTS --exclude '*.log' --exclude '.runs'"
```

### Files out of sync
```bash
# Force full re-sync
bash scripts/sync-replicants.sh --to-son
bash scripts/sync-replicants.sh --from-son
```

## Monitoring Sync Health

### Dashboard View
```bash
# On Anton
bash .shortcuts/sync-status
```

Create `.shortcuts/sync-status`:
```bash
#!/bin/bash
echo "=== Replicant Sync Status ==="
LAST_SYNC=$(ls -t logs/sync-replicants-*.log 2>/dev/null | head -1)
if [[ -n "$LAST_SYNC" ]]; then
  echo "Last sync: $(stat -f "%Sm" "$LAST_SYNC")"
  echo ""
  tail -10 "$LAST_SYNC"
else
  echo "No syncs yet"
fi
```

### Sync Metrics
- **Sync frequency:** Every 4h (6x/day)
- **Sync duration:** ~5-10 seconds
- **Data transferred:** ~50-100KB per sync
- **Conflicts:** Should be rare (<1% of syncs)

## Best Practices

1. **Sync before major changes:** Backup current state
2. **Sync after commits:** Keep Son informed immediately
3. **Review sync logs:** Check for conflicts/issues
4. **Test dry-run first:** Preview before live sync
5. **Monitor sync health:** Check logs weekly

## Files NOT Synced

**Intentionally excluded:**
- `.venv/` - Python virtual environments
- `.runs/` - Large eval run data
- `node_modules/` - NPM packages
- `.git/` - Git repos (use git sync instead)
- `*.pyc` - Python bytecode
- Large binaries (>10MB)

These should be rebuilt/regenerated on each machine.

---

**Status:** Ready to use
**Schedule:** Every 4 hours (automated)
**Direction:** Bidirectional (Anton ↔ Son)
**Health:** Check `.shortcuts/sync-status`
