# Anton Auto-Loop - Self-Training System

**Inspired by Karpathy's autoresearch** - Autonomous agent iteration for continuous improvement.

## 🎯 Two-Level Optimization

Anton optimizes **TWO things simultaneously:**

1. **Guardian Loop** (product) - Improves Guardian accuracy, cost, latency
2. **Meta Loop** (platform) - Improves Anton's own orchestration, templates, spawn efficiency

**This is the key insight from Karpathy's autoresearch:** the agent should improve both the product AND itself.

## How It Works

### Guardian Loop (every 4 hours)

```
Every 4 hours:
  1. Read OBJECTIVES.md (your goals)
  2. Generate 3 hypotheses
  3. Spawn agents to test each (fast mode, 5 min)
  4. Pick best result
  5. Run full validation (35 min)
  6. If +1pp improvement → auto-commit
  7. Update baseline, repeat
```

## Quick Start

### 1. Edit Your Objectives
```bash
code ~/.openclaw/workspace/OBJECTIVES.md
```

Set your target accuracy, priority areas, constraints.

### 2. Manual Test Run (recommended first)
```bash
bash ~/.openclaw/workspace/scripts/anton-auto-loop.sh
```

This runs one complete cycle. Check logs:
```bash
tail -f ~/.openclaw/workspace/logs/anton-auto-loop.log
```

### 3. Auto-Running (already configured)
The system runs every 4 hours automatically via launchd.

**Check status:**
```bash
launchctl list | grep anton.auto-loop
```

**Stop auto-loop:**
```bash
launchctl unload ~/Library/LaunchAgents/com.anton.auto-loop.plist
```

**Restart auto-loop:**
```bash
launchctl load ~/Library/LaunchAgents/com.anton.auto-loop.plist
```

### Meta Loop (every 24 hours)

```
Every day:
  1. Analyze recent agent failures
  2. Generate 2 meta-improvement hypotheses
  3. Spawn meta-agents to test each
  4. Pick improvements that increase success rate
  5. Auto-commit template/infrastructure changes
  6. Repeat
```

**What it improves:**
- Agent templates (CLAUDE.md, task templates)
- Spawn infrastructure (spawn-agent.sh, registry)
- Knowledge base (codemaps, error patterns)
- Success criteria definitions

**Example improvements:**
- "Simplify CLAUDE.md: 2K tokens → 800 tokens" → +10% success rate
- "Add success criteria to templates" → agents know what "done" means
- "Build common-errors.md" → agents fix issues faster
- "Batch Linear API calls" → 30s spawn → 10s spawn

## Monitoring

### Guardian State
```bash
cat ~/.openclaw/workspace/.anton-auto-state.json
```

### Meta State
```bash
cat ~/.openclaw/workspace/.anton-meta-state.json
```

### Current State (Combined)
```bash
cat ~/.openclaw/workspace/.anton-auto-state.json
```

Shows: baseline accuracy, cycle count, last improvement.

### Logs
```bash
# Main log (strategy, results)
tail -50 ~/.openclaw/workspace/logs/anton-auto-loop.log

# Stdout/stderr
tail -50 ~/.openclaw/workspace/logs/anton-auto-loop-stdout.log
```

### Agent Activity
```bash
bash ~/.openclaw/workspace/scripts/agent-peek.sh
```

Shows all spawned agents and their status.

## How It Improves

### Fast Mode Evals (5 min)
- Samples 10% of dataset (12 cases)
- Quick feedback loop
- Used for exploration

### Full Validation (35 min)
- Complete dataset (121 cases)
- Runs before commit
- Confirms improvement is real

### Hypothesis Generation
Currently uses predefined templates:
- Prompt refinement
- Archetype tuning
- Routing optimization
- Judge calibration
- Error pattern updates

**Future:** LLM-generated hypotheses based on failure analysis.

## Safety Mechanisms

### Auto-Commit Threshold
Only commits if:
- Fast mode: +1pp improvement
- Full validation: +1pp confirmed
- No regressions detected

### Budget Limits
Per cycle (4h):
- Max 5 parallel agents
- Max 3 iterations
- $10 API budget

### Rollback Detection
If any guideline type drops >1pp → alert, don't commit.

## Customization

### Change Cycle Frequency
Edit `~/Library/LaunchAgents/com.anton.auto-loop.plist`:
```xml
<key>StartInterval</key>
<integer>14400</integer>  <!-- 4 hours = 14400 seconds -->
```

Then reload:
```bash
launchctl unload ~/Library/LaunchAgents/com.anton.auto-loop.plist
launchctl load ~/Library/LaunchAgents/com.anton.auto-loop.plist
```

### Add Custom Hypotheses
Edit `scripts/anton-auto-loop.sh`, add to `HYPOTHESES` array:
```bash
HYPOTHESES=(
  "your-hypothesis:Description of what to try"
  "another-idea:Another approach"
)
```

## Expected Results

**Week 1:** 1-2pp improvement (6 cycles × ~0.3pp avg)
**Week 2:** 2-3pp improvement (learning what works)
**Week 3:** 3-4pp improvement (meta-learning kicks in)
**Month 1:** 5-8pp total improvement

**Velocity:** ~0.3-0.5pp per cycle initially, increasing over time.

## Troubleshooting

### "No improvement after 3 cycles"
- Check OBJECTIVES.md - are targets realistic?
- Review agent logs - are they understanding the task?
- Adjust hypothesis templates

### "Agents timing out"
- Increase timeout in spawn-agent.sh calls
- Check if fast-eval.sh is working
- Verify GCP credentials

### "Auto-loop not running"
```bash
launchctl list | grep anton.auto-loop
# Should show status

# If not running:
launchctl load ~/Library/LaunchAgents/com.anton.auto-loop.plist
```

### "Commits not happening"
- Check full validation logs
- Verify git config (user.name, user.email)
- Ensure +1pp threshold is met

## Next Steps

Once stable (1 week):
1. Add meta-learning (analyze git history for patterns)
2. LLM-generated hypotheses (instead of templates)
3. Multi-objective optimization (accuracy + cost + latency)
4. Cross-project learning (Guardian → Billy → Neuron)

---

**Status:** ✅ Active since 2026-03-08
**Baseline:** 79.3% accuracy
**Target:** 87% accuracy
**Next run:** Check `launchctl list | grep anton`
