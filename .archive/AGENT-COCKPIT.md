# Agent Cockpit Dashboard

**Real-time monitoring dashboard for OpenClaw subagents.**

## 🎯 What It Does

Agent Cockpit provides a visual dashboard showing:
- All running sub-agents
- Task status and Linear integration
- Runtime and token usage
- Frozen agent detection (agents running >30min)
- Recent activity history

## 📁 Files

- **`agent-cockpit-simple.sh`** - Main dashboard generator (interactive HTML)
- **`agent-cockpit.sh`** - Advanced version with CLI text output + auto-populated HTML
- **`scripts/get-subagents-data.js`** - Node.js helper for session data extraction

## 🚀 Quick Start

### Option 1: Interactive Dashboard (Recommended)

```bash
# Generate the dashboard
./agent-cockpit-simple.sh

# Open /tmp/agent-cockpit.html in browser
# Then run in OpenClaw chat: subagents list
# Copy JSON output and paste into dashboard
```

### Option 2: Text Output

```bash
# Quick CLI view
./agent-cockpit.sh
```

### Option 3: Serve Dashboard

```bash
# Generate and serve
./agent-cockpit.sh --serve 8765

# Open http://localhost:8765/agent-cockpit.html
```

## 📊 Dashboard Features

### Overview Stats
- **Active Agents** - Currently running agents
- **Recent (30m)** - Agents completed/failed in last 30 minutes
- **Total Tracked** - All agents in current session

### Active Agents Section
For each running agent:
- Label and task ID (e.g., CAI-71)
- Runtime (with ⚠️ FROZEN warning if >30min)
- Model used
- Task preview
- Linear status integration

### Recent Activity
- Completed agents (✅)
- Failed agents (❌)
- Timeout events (⏱️)
- Token usage stats

## 🔧 Integration Points

### Linear API
Dashboard queries Linear for:
- Task status (Todo/In Progress/Done/Blocked)
- Last comment timestamp (for frozen detection)
- Task metadata

Set `LINEAR_API_KEY` in `/root/.openclaw/workspace/.env.linear`

### Frozen Agent Detection
Agent is marked **FROZEN** if:
- Runtime > 30 minutes AND
- No Linear updates in last 15 minutes

Use this to identify stuck agents that need steering/killing.

## 🎨 Dashboard Layout

```
╔══════════════════════════════════╗
║      Agent Cockpit 🦞           ║
╠══════════════════════════════════╣
║  [Active: 4] [Recent: 6] [10]   ║
╠══════════════════════════════════╣
║  🔄 Active Agents                ║
║  ┌────────────────────────────┐  ║
║  │ CAI-71: Dashboard (2m)     │  ║
║  │ CAI-74: Campaign (5m)      │  ║
║  └────────────────────────────┘  ║
╠══════════════════════════════════╣
║  📋 Recent Activity              ║
║  ✅ CAI-100: Done (5m, 65k tok) ║
║  ❌ CAI-101: Failed (16m)       ║
╚══════════════════════════════════╝
```

## 🔄 Auto-Refresh

HTML dashboard auto-refreshes every 30 seconds when using `--serve` mode.

For heartbeat monitoring, add to `HEARTBEAT.md`:
```bash
# Generate fresh dashboard
/root/.openclaw/workspace/agent-cockpit-simple.sh
```

## 💡 Usage Examples

### Monitor from CLI
```bash
# Watch active agents in terminal
watch -n 5 './agent-cockpit.sh'
```

### Check for frozen agents
```bash
# Look for ⚠️ FROZEN in output
./agent-cockpit.sh | grep FROZEN
```

### Get JSON data
```bash
# Use subagents tool
openclaw subagents list --json
```

## 📝 Notes

- Dashboard is ephemeral (generates to `/tmp/`)
- No persistent storage needed
- Linear integration optional (works without API key)
- Frozen detection helps prevent stuck agents
- Cost tracking based on Sonnet 4.5 pricing

## 🛠️ Future Enhancements

Potential additions:
- [ ] WebSocket live updates (no refresh needed)
- [ ] Canvas integration (when node support available)
- [ ] Cost accumulation tracking
- [ ] Agent steering/killing from dashboard UI
- [ ] Heartbeat integration (auto-steer frozen agents)
- [ ] Historical trend charts
