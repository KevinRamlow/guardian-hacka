# Pipeline — Dual Task Queue System

## Two Pipelines

**LONG** (`pipeline-long.json`) — 5 workers, ACP runtime
- Claude Code agents, hypothesis testing, iterative loops, PRs
- Stall timeout: 25 min, steer grace: 10 min, 3 retries

**FAST** (`pipeline-fast.json`) — 10 workers, subagent runtime
- Quick tasks: research, analysis, config, non-code work
- Stall timeout: 10 min, steer grace: 3 min, 2 retries

## CLI
```bash
pipeline-ctl.sh all                      # Both pipelines overview
pipeline-ctl.sh long status              # Long pipeline detail
pipeline-ctl.sh fast add CAI-XX "task"   # Add to fast queue
pipeline-ctl.sh long pause               # Pause long pipeline
pipeline-ctl.sh fast retry CAI-XX        # Retry from DLQ
pipeline-ctl.sh long kill CAI-XX         # Force-kill → DLQ
pipeline-ctl.sh fast config maxWorkers 15
```

## Architecture
```
System crontab (60s) → pipeline-manager.sh → checks BOTH pipelines
  ↓ writes spawn-{long|fast}.trigger if work needed
OpenClaw cron (120s) → Pipeline Spawner → reads triggers, spawns agents
```

## Recovery: max 3 min after any restart
