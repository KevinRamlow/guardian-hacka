# Billy Worker Pipeline

**Status:** Active (started 2026-03-05 23:44 UTC)

## Overview

Autonomous deployment pipeline for Billy improvements. Workers continuously implement and deploy features without approval gates.

## Context

- **Billy status:** Private (only Caio's testers: U04PHF0L65P, U0388ARSD9N, U03Q5D4P4BV, U05M0ADSLKT)
- **Deployment target:** 89.167.64.183:18790
- **Autonomy level:** Full - workers implement + deploy directly
- **Backlog source:** CAI-73 analysis (Slack intelligence, 20+ improvement ideas)

## Pipeline Flow

```
CAI-73 Analysis → Creates Linear backlog (20+ tasks)
    ↓
Anton spawns 3 worker agents
    ↓
Each worker:
  1. Picks top priority task from backlog
  2. Analyzes requirement
  3. Implements feature/improvement
  4. Tests locally
  5. Deploys to Billy VM (89.167.64.183)
  6. Restarts Billy gateway
  7. Marks task Done in Linear
  8. Picks next task
    ↓
Continuous loop until backlog cleared
```

## Worker Rules

**DO:**
- Implement immediately without asking
- Deploy directly to Billy VM
- Make aggressive improvements (new features, integrations, automations)
- Test before deploying
- Log progress to Linear
- Pick next task when current done

**DON'T:**
- Ask for approval on design decisions
- Wait for confirmation before deploying
- Hold back on scope ("too ambitious")
- Stop until backlog is cleared

**ONLY escalate if:**
- Technical blocker (missing credentials, API access, etc.)
- External dependency needed from Caio
- Breaking change that affects existing testers

## Deployment Commands

**Deploy to Billy VM:**
```bash
# Copy changed files
rsync -av /root/.openclaw/workspace/path/to/changed/files root@89.167.64.183:/root/.openclaw/workspace/path/

# Restart Billy gateway
ssh root@89.167.64.183 "pkill -f 'openclaw gateway' && sleep 2 && cd /root && nohup openclaw gateway > billy-gateway.log 2>&1 &"

# Verify
ssh root@89.167.64.183 "ps aux | grep openclaw | grep -v grep"
```

## Priority Guidance

Focus on (in order):
1. **High-impact, high-frequency needs** (what people ask about most)
2. **Data access improvements** (new queries, data sources, relationships)
3. **Automation** (manual tasks Billy can do automatically)
4. **UX improvements** (faster, clearer, more intuitive)
5. **Proactive features** (insights, alerts, recommendations)

## Success Metrics

- Number of improvements deployed
- Time to deployment (per task)
- Backlog clearance rate
- Worker utilization (% of time actively working vs idle)

## Active Workers

**Spawned:** 2026-03-06 00:19 UTC

- **Worker 1:** CAI-74 (campaign comment export) - session: 7c2e7a43-9697-40d6-a271-370a0f84585b
- **Worker 2:** CAI-75 (brand creation automation) - session: c2f0f530-9460-441b-a91b-c1565e250041
- **Worker 3:** CAI-79 (campaign performance dashboard) - session: a56ef948-2484-4a06-9a84-42520a724740

## Current Status

- **CAI-73 (analysis):** ✅ Complete (15 min runtime)
- **Workers:** 🚀 3 active (implementing P0 tasks)
- **Backlog:** 23 tasks (3 P0, 5 P1, 15 P2) - 3 In Progress, 20 Backlog
