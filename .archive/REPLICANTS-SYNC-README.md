# Replicants Sync - Quick Setup

**Status:** ✅ Scripts ready, SSH setup required

## What This Does

Keeps Anton (your Mac) and Son of Anton (VPS 89.167.23.2) synchronized:
- Architecture docs
- Objectives & state files
- Memory & observations
- Generated backlogs

## Quick Setup (5 minutes)

### 1. SSH Key Exchange

**On Son of Anton (89.167.23.2):**
```bash
ssh-keygen -t ed25519 -C "son-of-anton" -f ~/.ssh/id_son
cat ~/.ssh/id_son.pub
# Copy the output
```

**On your Mac:**
```bash
echo "<paste-pubkey-here>" >> ~/.ssh/authorized_keys

# Test connection
ssh -i ~/.ssh/id_son caio@$(ipconfig getifaddr en0) "echo 'Connected!'"
```

**Update Son's SSH config:**
```bash
# On 89.167.23.2
echo "
Host anton-mac
  HostName <your-mac-ip>
  User caio
  IdentityFile ~/.ssh/id_son
" >> ~/.ssh/config
```

### 2. Get Your Mac IP

```bash
# On your Mac
ipconfig getifaddr en0  # WiFi
# or
ipconfig getifaddr en1  # Ethernet

# Should output something like: 192.168.1.x or 10.0.0.x
```

### 3. Test Sync (Dry Run)

```bash
# On your Mac
bash ~/.openclaw/workspace/scripts/sync-replicants.sh --dry-run
```

Should show what would be synced without actually doing it.

### 4. Run First Sync

```bash
bash ~/.openclaw/workspace/scripts/sync-replicants.sh
```

Should sync files to Son of Anton.

### 5. Enable Auto-Sync

```bash
launchctl load ~/Library/LaunchAgents/com.anton.sync-replicants.plist
launchctl list | grep sync-replicants
```

Should show the job loaded.

## What Gets Synced

### Anton → Son (every 4h)
- OBJECTIVES.md (goals)
- .anton-auto-state.json (observable state)
- .anton-meta-state.json (observable state)
- docs/ (architecture, setup)
- scripts/ + skills/ (shared code)
- ❌ **NOT memory/** - Anton's memories stay with Anton

### Son → Anton (when Son has data)
- reports/son-monitoring-*.json (structured observations)
- .son-monitor-state.json (snapshot)
- backlog/son-generated-tasks.json (generated work)
- ❌ **NOT memory/** - Son's memories stay with Son

## Philosophy: Separate Entities

Anton and Son of Anton are **distinct entities**, not clones:
- **Shared:** Objective knowledge (docs, code, goals, state)
- **Separate:** Subjective experience (memories, identity, observations)

**Communication:** Structured reports (JSON), not memory merge
- Son sends monitoring reports with objective data
- Anton reads reports but maintains own memory
- Each entity keeps their own perspective

## Check Status

```bash
bash ~/.openclaw/workspace/.shortcuts/sync-status
```

## Troubleshooting

### "Connection refused"
- Verify Mac IP: `ipconfig getifaddr en0`
- Check SSH running: `sudo systemsetup -getremotelogin`
- Enable if needed: `sudo systemsetup -setremotelogin on`

### "Permission denied (publickey)"
- Re-do SSH key setup above
- Check authorized_keys: `cat ~/.ssh/authorized_keys`

### "File not found"
- Son doesn't have directory structure yet
- SSH to Son: `ssh caio@89.167.23.2`
- Create dirs: `mkdir -p ~/workspace/{docs,memory,scripts,skills,logs,backlog}`

### Sync taking too long
- Check network: `ping 89.167.23.2`
- Try one-way sync: `bash scripts/sync-replicants.sh --to-son`

## Integration

**Auto-loops will sync automatically:**
- Guardian loop: after each cycle (every 4h)
- Meta loop: after improvements (every 24h)
- Manual sync: `bash scripts/sync-replicants.sh`

**Son of Anton monitoring:**
- Reads synced state files
- Posts updates to #replicants
- Syncs observations back to Anton

## Commands Cheat Sheet

```bash
# Status
bash .shortcuts/sync-status

# Dry run (preview)
bash scripts/sync-replicants.sh --dry-run

# Sync both ways
bash scripts/sync-replicants.sh

# One-way syncs
bash scripts/sync-replicants.sh --to-son    # Anton → Son
bash scripts/sync-replicants.sh --from-son  # Son → Anton

# Check launchd job
launchctl list | grep sync-replicants

# View logs
tail -f ~/.openclaw/workspace/logs/sync-replicants-stdout.log
```

## Next Steps

1. ✅ Complete SSH setup (above)
2. ✅ Test sync manually
3. ✅ Enable auto-sync launchd job
4. 📋 Update Son of Anton's HEARTBEAT.md (see docs/SON-OF-ANTON-HEARTBEAT.md)
5. 📋 Verify sync working in 4 hours

---

**Docs:** `skills/sync-replicants/SKILL.md`
**Script:** `scripts/sync-replicants.sh`
**Status:** `.shortcuts/sync-status`
