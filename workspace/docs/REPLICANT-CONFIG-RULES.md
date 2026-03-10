# REPLICANT-CONFIG-RULES.md

## CRITICAL: Each Replicant Has Independent Config

**NEVER sync these files between replicants:**
- `openclaw.json` — each replicant's gateway config (unique bot tokens, reply policies)
- `SOUL.md` — each replicant's identity/persona
- `HEARTBEAT.md` — each replicant's behavior (uses their own template from docs/)
- `memory/*.md` — each replicant's subjective memories
- `MEMORY.md` — long-term personal memory

**Why:** Each replicant has different:
- Slack tokens (different bots)
- Reply policies (Anton: reply all in #replicants | Son: require mention)
- Identities (Anton: orchestrator | Son: monitor)
- Memories (experiences are separate)

## Reply Config Per Replicant

### Anton (Mac, localhost:18789)
```json
"C0AJTTFLN4X": {
  "allow": true,
  "requireMention": false,  // Replies to ALL messages
  "allowBots": true
}
```

### Son of Anton (89.167.23.2)
```json
"C0AJTTFLN4X": {
  "allow": true,
  "requireMention": true,   // Only when MENTIONED
  "allowBots": false
}
```

### Billy (89.167.64.183)
- Not in #replicants
- Only DMs for data queries

## What sync-replicants.sh CAN Sync

**Architecture/objectives (shared knowledge):**
- `docs/ANTON-ARCHITECTURE.md`
- `docs/SON-OF-ANTON-SETUP.md`
- `OBJECTIVES.md`
- State files (`.anton-auto-state.json`, `.anton-meta-state.json`)

**Skills (tools both use):**
- `skills/sync-replicants/`

**NOT memories, NOT configs, NOT identities.**

## If Reply Config Gets Overwritten

**Fix for Son of Anton:**
```bash
ssh caio@89.167.23.2
nano ~/.openclaw/openclaw.json
# Find C0AJTTFLN4X section
# Set "requireMention": true
openclaw gateway restart
```

**Prevention:**
Sync script already excludes openclaw.json. If it ever gets synced by accident, each replicant must restore their own config from backup.
