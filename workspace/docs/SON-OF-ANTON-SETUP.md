# Son of Anton - Monitoring Setup

**Role:** Monitor Anton's auto-loop health and coordinate backlog generation

**Location:** 89.167.23.2 (ClawdBot framework)
**Channel:** #replicants (C0AJTTFLN4X)

## What Son of Anton Does

### 1. Monitor Anton Auto-Loops

**Every 4 hours (aligned with Guardian loop):**
- SSH to Caio's Mac: `ssh caio@<mac-ip>`
- Check Guardian state:
  ```bash
  cat ~/.openclaw/workspace/.anton-auto-state.json
  ```
- Check Meta state:
  ```bash
  cat ~/.openclaw/workspace/.anton-meta-state.json
  ```
- Verify launchd jobs:
  ```bash
  launchctl list | grep anton
  ```

**Post to #replicants:**
```
[ANTON-STATUS] Cycle X complete
Guardian: 79.3% → 80.1% (+0.8pp)
Meta: 60% → 62% success rate
Agents: 2 running, 3 queued
Next run: 17:00 BRT
```

### 2. Health Checks

**Alert conditions:**
- No improvement after 3 cycles
- Launchd jobs not running
- Agent success rate < 50%
- Logs show repeated errors

**Alert format:**
```
⚠️ [ANTON-HEALTH] Issue detected
Problem: No improvement in 3 cycles
Last baseline: 79.3%
Last run: 2h ago
Action needed: Check logs + objectives
```

### 3. Backlog Coordination

**If Anton's Linear queue empty:**
1. Run backlog generator:
   ```bash
   ssh caio@<mac-ip> "cd ~/.openclaw/workspace && bash scripts/backlog-generator.sh"
   ```
2. Verify tasks created in Linear CAI workspace
3. Notify #replicants:
   ```
   [BACKLOG] Generated 3 new tasks for Anton
   - GUA accuracy improvement
   - Template optimization
   - Spawn efficiency
   ```

### 4. Daily Summary

**Every day at 09:00 BRT:**
- Summarize last 24h activity
- Guardian progress (accuracy delta)
- Meta improvements (success rate, spawn time)
- Git commits from auto-loop
- Upcoming objectives

**Format:**
```
📊 [DAILY-SUMMARY] Anton Auto-Loop Day 1

Guardian Loop (6 cycles):
  - Baseline: 79.3% → 80.5% (+1.2pp)
  - Best improvement: +0.8pp (archetype tuning)
  - Commits: 2 auto-commits

Meta Loop (1 cycle):
  - Agent success: 60% → 65% (+5%)
  - Improvements: CLAUDE.md simplified, common-errors.md created
  - Commits: 1 auto-commit

Next target: 87% accuracy (6.5pp remaining)
ETA: ~5-7 days at current pace
```

## Implementation (ClawdBot)

### Heartbeat Configuration

Add to ClawdBot's `HEARTBEAT.md` on 89.167.23.2:

```markdown
## Anton Auto-Loop Monitoring

### Every 4 hours (aligned with Guardian cycle)

1. **Check Anton state:**
   ```bash
   ssh caio@<mac-ip> -o ConnectTimeout=10 "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status" 2>&1
   ```

2. **Parse output:**
   - Guardian baseline accuracy
   - Meta agent success rate
   - Active/queued agents
   - Last run timestamp

3. **Post to #replicants if:**
   - State changed (improvement or regression)
   - Health issue detected
   - No runs in last 6 hours

4. **Alert conditions:**
   - No improvement after 3 cycles → "[ALERT] Anton stagnant"
   - Launchd jobs down → "[ALERT] Auto-loops offline"
   - Success rate <50% → "[ALERT] Agents failing"

### Every 24 hours (09:00 BRT)

1. **Generate daily summary:**
   - Read `.anton-auto-state.json` for Guardian deltas
   - Read `.anton-meta-state.json` for Meta deltas
   - Count git commits with "AUTO-LOOP" or "META-LOOP" in message
   - Calculate ETA to target based on avg improvement rate

2. **Post summary to #replicants**

### Backlog Check (every 4h)

1. **Check Linear queue:**
   ```bash
   # Query Linear API for CAI workspace Todo count
   ```

2. **If queue empty:**
   - Run backlog generator on Anton's machine
   - Verify tasks created
   - Notify #replicants

### Health Recovery

If alerts triggered:
1. First attempt: restart launchd jobs remotely
2. If fails: notify Caio in DM
3. Log issue to Son of Anton's memory
```

### SSH Configuration

Son of Anton needs SSH access to Caio's Mac.

**On 89.167.23.2 (Son of Anton):**
```bash
# Generate SSH key if not exists
ssh-keygen -t ed25519 -C "son-of-anton@clawdbot"

# Copy public key
cat ~/.ssh/id_ed25519.pub
```

**On Caio's Mac:**
```bash
# Add Son of Anton's public key
echo "<pubkey from above>" >> ~/.ssh/authorized_keys

# Test connection from Son of Anton
ssh caio@<mac-ip> "echo 'Connected!'"
```

### Environment Variables

Son of Anton needs:
```bash
# In ClawdBot config or .env
ANTON_MAC_IP="<caio-mac-ip>"  # Get from: ifconfig | grep inet
ANTON_MAC_USER="caio"
LINEAR_API_KEY="<key>"  # For backlog checks
SLACK_CHANNEL_REPLICANTS="C0AJTTFLN4X"
```

## Testing

**Manual test from Son of Anton:**
```bash
# Test SSH connection
ssh caio@<mac-ip> "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status"

# Test state files
ssh caio@<mac-ip> "cat ~/.openclaw/workspace/.anton-auto-state.json"
ssh caio@<mac-ip> "cat ~/.openclaw/workspace/.anton-meta-state.json"

# Test launchd check
ssh caio@<mac-ip> "launchctl list | grep anton"
```

**Expected output:**
- Auto-loop status (Guardian + Meta state)
- JSON with baseline accuracies and cycles
- Two launchd jobs listed

## Integration Timeline

1. **Day 1:** SSH setup + manual testing
2. **Day 2:** Heartbeat monitoring active
3. **Day 3:** Daily summaries working
4. **Week 1:** Full autonomous coordination

## Anti-Loop Rules in #replicants

**CRITICAL:** Son of Anton monitoring Anton creates bot-to-bot communication.

**Rules:**
- Only post status updates, not conversational responses
- Format: `[TAG] Message` (e.g., `[ANTON-STATUS]`, `[DAILY-SUMMARY]`)
- If Anton posts in #replicants, do NOT reply unless it's a question
- Max 1 post per monitoring cycle (no spam)
- Use threads for detailed logs

---

**Status:** Ready for implementation
**Owner:** Son of Anton (ClawdBot on 89.167.23.2)
**Monitored:** Anton (OpenClaw on Caio's Mac)
**Channel:** #replicants (C0AJTTFLN4X)
