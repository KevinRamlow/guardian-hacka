# Son of Anton - Multi-Agent Setup

**Status:** Backlog (AUTO-302)
**Created:** 2026-03-08

## Goal
Deploy Son of Anton as separate agent on dedicated VM for multi-agent collaboration with Anton.

## What Exists (Ready)

✅ **Workspace cloned:**
- Location: `~/.openclaw/agents/son-of-anton/workspace/`
- SOUL.md: research assistant role, learns from Anton
- IDENTITY.md: 🔬 Son of Anton, curious explorer
- HEARTBEAT.md: simplified (no spawning, reports to Anton)
- USER.md: same context as Anton (Caio)
- TOOLS.md, AGENTS.md: inherited from Anton

✅ **Config prepared:**
- File: `/tmp/openclaw-new.json`
- Entry in `agents.list` for son-of-anton
- Heartbeat: every 10min (vs Anton's 5min)
- Target channel: `anton-lab`
- Workspace: isolated from Anton

✅ **Documentation:**
- `~/.openclaw/agents/README.md` - multi-agent overview
- This file - setup instructions

## What Needs To Be Done

### 1. Infrastructure
- [ ] Provision VM (or repurpose Billy VM at 89.167.64.183)
- [ ] Install OpenClaw on VM
- [ ] Configure network/firewall

### 2. Slack Setup
- [ ] Create #anton-lab channel
- [ ] Invite both bots to channel
- [ ] Decide: shared bot token or separate bot for son-of-anton?

### 3. Deployment
- [ ] Copy `~/.openclaw/agents/son-of-anton/` to VM
- [ ] Configure environment variables on VM:
  - Linear API keys
  - GCP credentials
  - Slack tokens
  - GitHub tokens
- [ ] Apply openclaw.json config on VM
- [ ] Start son-of-anton gateway

### 4. Testing
- [ ] Both agents appear in #anton-lab
- [ ] Anton can assign tasks to son-of-anton
- [ ] Son-of-anton reports findings back
- [ ] No session conflicts
- [ ] Heartbeats working for both

## Architecture

```
Main Machine (Anton)
├── ~/.openclaw/workspace/           # Anton's workspace
├── ~/.openclaw/agents/
│   ├── main/                        # Anton's agent config
│   └── son-of-anton/                # Son's workspace (prepared)
└── openclaw.json                    # Gateway config

VM (Son of Anton)
├── ~/.openclaw/workspace/           # Son's workspace (copy from main)
├── SOUL.md                          # Research assistant persona
├── HEARTBEAT.md                     # Supervised mode
└── openclaw.json                    # Gateway config (son-of-anton entry)
```

## Roles

### Anton (main)
- **Role:** Orchestrator & coordinator
- **Capabilities:** Full autonomy, spawns agents, makes decisions
- **Heartbeat:** Every 5min
- **Channels:** DM with Caio, #tech-gua-ma-internal, #anton-lab

### Son of Anton
- **Role:** Research assistant & hypothesis tester
- **Capabilities:** Deep analysis, testing, exploration (supervised)
- **Heartbeat:** Every 10min
- **Channels:** #anton-lab only

## Workflow Example

1. Caio asks Anton: "improve Guardian accuracy by 5pp"
2. Anton creates hypotheses, assigns research to Son of Anton in #anton-lab
3. Son of Anton explores solutions, tests edge cases, reports findings
4. Anton reviews findings, decides on approach, spawns production agents
5. Both agents collaborate on validation

## Success Criteria

- [ ] Both agents active and responsive in #anton-lab
- [ ] Can @ mention to assign tasks
- [ ] Son-of-anton learns from Anton's corrections
- [ ] No duplicate work (clear division of labor)
- [ ] Anton maintains final decision authority

## Notes

- Son of Anton has NO memory of Anton's work (fresh MEMORY.md)
- Son of Anton CANNOT spawn agents without approval
- Son of Anton CANNOT make production changes
- Son of Anton asks questions before acting
- All files ready in `~/.openclaw/agents/son-of-anton/`
