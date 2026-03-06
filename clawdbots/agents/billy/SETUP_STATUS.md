# Billy Bot Setup Status
**Date:** 2026-03-05 15:59 UTC
**Status:** ⚠️ Partially Complete - Missing Slack App Token

---

## ✅ Completed

### 1. Audio Transcription Skill Added
- **Source:** `/root/.openclaw/workspace/skills/audio-transcription/`
- **Destination:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/audio-transcription/`
- **Status:** Copied successfully
- **Files:**
  - `SKILL.md` — Skill documentation
  - `transcribe.sh` — Bash wrapper script
  - `scripts/transcribe.py` — Python transcription script
  - `README.md` — Quick reference

### 2. TOOLS.md Updated
- **File:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/TOOLS.md`
- **Added:** Audio Transcription section with:
  - Engine: Google Gemini 2.5 Flash
  - Supported formats: M4A, MP3, WAV, FLAC, OGG, AAC
  - Usage examples
  - API key configuration (already in .env)

### 3. Slack Tokens Configured
- **File:** `/root/.openclaw/workspace/clawdbots/agents/billy/.env`
- **Tokens added:**
  - `SLACK_USER_TOKEN=REDACTED_SLACK_USER_TOKEN_OLD`
  - `SLACK_BOT_TOKEN=[REDACTED_SLACK_BOT]`
- **Other keys present:**
  - ANTHROPIC_API_KEY (Claude)
  - GEMINI_API_KEY (for presentations + audio transcription)
  - LINEAR_API_KEY (task tracking)
  - MySQL credentials

### 4. Billy Registered as OpenClaw Agent
- **Command run:** `openclaw agents add billy --workspace /root/.openclaw/workspace/clawdbots/agents/billy/workspace --model anthropic/claude-sonnet-4-5`
- **Result:** Agent created successfully
- **Location:**
  - Workspace: `~/.openclaw/workspace/clawdbots/agents/billy/workspace`
  - Agent dir: `~/.openclaw/agents/billy/agent`
  - Sessions: `~/.openclaw/agents/billy/sessions`

---

## ❌ Blocked: Missing Slack App Token

Billy cannot connect to Slack without a **Slack App Token** (`xapp-...`).

### Why App Token is Needed
OpenClaw uses **Socket Mode** for Slack integration, which requires both:
1. **Bot Token** (`xoxb-...`) ✅ — Already configured
2. **App-Level Token** (`xapp-...`) ❌ — NOT YET CREATED

### How to Create App Token (Manual Steps)

1. Go to https://api.slack.com/apps
2. Find **Billy** app (or create new app if doesn't exist)
3. Go to **Basic Information** → **App-Level Tokens**
4. Click **"Generate Token and Scopes"**
5. **Token Name:** `billy-socket`
6. **Scopes:** `connections:write`
7. Click **"Generate"**
8. Copy the token (starts with `xapp-`)
9. Update `/root/.openclaw/workspace/clawdbots/agents/billy/.env`:
   ```bash
   SLACK_APP_TOKEN=xapp-1-...
   ```

### Alternative: Use Existing Billy App
If Billy app already exists in BrandLovers Slack workspace:
- Check if app token was already created
- Retrieve it from Slack API console
- Add to .env file

---

## 🚫 Not Started

### 5. Slack Channel Registration
Once app token is added:
```bash
openclaw channels add \
  --channel slack \
  --account billy \
  --bot-token [REDACTED_SLACK_BOT] \
  --app-token xapp-YOUR-TOKEN-HERE \
  --name "Billy Bot"
```

### 6. Billy Routing Binding
Route Billy's Slack account to his agent:
```bash
openclaw agents bind \
  --agent billy \
  --bind slack:billy
```

### 7. Start Billy
Option A: Via OpenClaw Gateway (recommended)
```bash
# Gateway should auto-start Billy when bound
openclaw gateway status
openclaw gateway restart  # if needed
```

Option B: Via Docker (standalone)
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy
bash quick-start.sh
```

### 8. Test Billy
Send test DM to Billy in Slack:
- Message: "Oi Billy! Tudo bem?"
- Expected: Billy responds with greeting
- Test audio: Send voice message, expect transcription + response

---

## Next Steps

**Immediate action required:**
1. **Caio** creates Slack App Token (`xapp-...`) for Billy
2. Update `.env` with app token
3. Run channel add command
4. Bind Billy to Slack
5. Start gateway
6. Test DM

**Files ready for testing:**
- Billy's workspace is fully configured
- Skills are loaded (audio-transcription, data-query, campaign-lookup, etc.)
- Tokens are set (except app token)
- Agent is registered in OpenClaw

---

## File Locations

- **Billy's root:** `/root/.openclaw/workspace/clawdbots/agents/billy/`
- **Billy's workspace:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/`
- **Config file:** `/root/.openclaw/workspace/clawdbots/agents/billy/.env`
- **Audio transcription:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/audio-transcription/`
- **Quick start:** `/root/.openclaw/workspace/clawdbots/agents/billy/quick-start.sh`

---

## Billy Identity

From SOUL.md:
- **Name:** Billy
- **Role:** Non-tech team helper
- **Specialties:**
  - Data queries (SQL → business answers)
  - Campaign lookups and comparisons
  - Creator analytics and payment insights
  - PowerPoint generation (branded presentations)
  - Audio transcription (voice messages)
- **Model:** Claude Sonnet 4.5
- **Language:** pt-BR (Portuguese, informal/friendly)
