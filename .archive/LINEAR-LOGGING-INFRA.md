# Linear Logging Infrastructure - DEPLOYED

## Status: ✅ WORKING

Tested: 2026-03-05 15:15 UTC
Test task: CAI-40
Test results: Comments successfully posted, status updated to Done

## Components

### 1. linear-log.sh - Agent Logging Script
**Location:** `/root/.openclaw/workspace/skills/task-manager/scripts/linear-log.sh`

**Usage:**
```bash
# Add progress comment
linear-log.sh <task-id> "<message>"

# Add comment + update status
linear-log.sh <task-id> "<message>" <status>
```

**Status values:** `todo`, `progress`, `review`, `done`, `blocked`

**Examples:**
```bash
# Log start
linear-log.sh CAI-42 "🚀 Starting analysis of disagreement patterns"

# Log progress
linear-log.sh CAI-42 "📊 Found 156 cases with severity=3, analyzing..."

# Log completion with full report
linear-log.sh CAI-42 "✅ Complete: Analysis shows 23% of disagreements are Phase 1 quality issues. Full report: [detailed findings...]" done
```

### 2. Claude Code Agent Instructions (CLAUDE.md)
**Location:** `/root/.claude/CLAUDE.md`

Claude Code agents (runtime="acp") have instructions to:
1. Extract task ID from spawn message (e.g., "CAI-42")
2. Log progress at key milestones using linear-log.sh
3. Add FULL DETAILED REPORT on completion (not summaries)
4. Update status to done when complete

### 3. OpenClaw Subagent Hook (linear-logger.js)
**Location:** `/root/.openclaw/hooks/linear-logger.js`
**Status:** Implemented but NOT TESTED (hook system integration unclear)

**Triggers:**
- `subagent:spawn` → Log "🚀 Sub-agent spawned"
- `subagent:complete` → Log completion message + update to done
- `subagent:error` → Log error + update to blocked

**Note:** Hook may need OpenClaw restart or different event names. If hooks don't work, agents can manually log using linear-log.sh.

### 4. Configuration
**OpenClaw config:** `/root/.openclaw/openclaw.json`
```json
"hooks": {
  "internal": {
    "entries": {
      "linear-logger": {
        "enabled": true,
        "path": "/root/.openclaw/hooks/linear-logger.js"
      }
    }
  }
}
```

**Linear env:** `/root/.openclaw/workspace/.env.linear`
- API Key: $LINEAR_API_KEY (see .env.secrets)
- Default team: CAI (caio-tests workspace)

## Agent Responsibilities

**When spawned for a Linear task:**
1. Extract task ID from spawn message (pattern: [A-Z]{2,4}-\d+)
2. Log start: `linear-log.sh <id> "🚀 Starting [task description]" progress`
3. Log key milestones during work
4. Log completion with FULL DETAILED REPORT
5. Update status: `linear-log.sh <id> "[report]" done`

**Critical:** Linear is the source of truth. Workspace files are backup only.

## Testing & Verification

**Test command:**
```bash
source /root/.openclaw/workspace/.env.linear
linear-log.sh CAI-40 "Test message" done
```

**Verify via Linear CLI:**
```bash
source /root/.openclaw/workspace/.env.linear
/root/.openclaw/workspace/skills/linear/scripts/linear.sh issue CAI-40
```

**Or verify in Linear web UI:**
https://linear.app/caio-tests/issue/CAI-40

## Deployment Checklist
- [x] linear-log.sh script created and tested
- [x] CLAUDE.md updated with logging instructions
- [x] linear-logger.js hook created
- [x] openclaw.json hook registration added
- [x] SOUL.md updated with infrastructure details
- [x] Test execution successful (CAI-40)
- [ ] Hook system verification (requires subagent spawn test)
- [ ] Backfill old task reports (deferred - not urgent)

## Next Steps
1. Spawn real subagent with task ID → verify hook triggers
2. If hooks don't work: agents manually log (already working)
3. Monitor CAI tasks for automatic comment population
4. Backfill historical reports when time permits
