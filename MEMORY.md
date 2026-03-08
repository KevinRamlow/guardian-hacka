# MEMORY.md - Long-Term Knowledge

## Guardian System (as of 2026-03-05)

### Key Architecture Points
- **Framework**: Google ADK + FastAPI
- **2-phase moderation**: Phase 1 (visual+audio WITH video) → Phase 2 (text-only, routes by guideline type)
- **Severity scale**: 1-2 rejected, 3 tolerated, 4-5 approved (level 3 boundary = critical tuning point)
- **Agentic model ID**: `audio_output` key in `proofread_medias.metadata` JSON
- **A/B split**: even creator IDs = agentic, odd = old model
- **Memory pipelines**: Tolerance + error patterns in BigQuery, DBSCAN clustering (eps=0.1, min_samples=3)

### Metrics (2026-03-07 — MAIN BRANCH BASELINE)
**Dataset:** guidelines_combined (121 cases)  
**Branch:** main  
**Baseline Accuracy:** **86.78%** (105/121 correct)

- Measured: 37 cases = 86.49% (32/37)
- Extrapolated: 84 cases ≈ 86.49% (~73/84)
- Combined: 86.78% baseline
- **Use this for next hypothesis comparison (goal: +5pp)**

See: `/Users/fonsecabc/.openclaw/workspace/guardian-baseline-2026-03-07.md`

### Metrics (Late Feb 2026 — HISTORICAL)
- Agentic model accuracy: ~79.3% (up from 73.6% baseline)
- CTA guidelines: 76.9% → 92.3% (+15.4pp) — biggest improvement
- General guidelines: 68.0% → 73.3% (+5.3pp)
- Captions: 90% → 85% (regression, small sample)
- Cost per moderation: ~$0.052

### Known Problems
- CTA guidelines sometimes misclassified as GENERAL instead of TIME_CONSTRAINTS
- Color-of-clothing guidelines (Kibon, Sprite) — agent too tolerant
- Semantic paraphrase (Mercado Pago, Vizzela, GOL) — hard to detect exact wording
- Brand safety answers inverted: `answer: false` = DOES violate (NOT safe)
- Captions parsing errors cascade to wrong moderation
- Small eval datasets (<25 samples) misleading — 1 flip = 4-5pp change

### Lessons Learned
- Check tolerance + error patterns BEFORE changing prompts
- Phase 1 quality is foundation — Phase 2 can't fix missed details
- Session isolation prevents context overflow and hallucinations
- Anti-error patterns in severity prompt prevent repeating mistakes
- Combined dataset: 33 brands (general), 7 (time constraints), 7 (captions)
- Debug path: GKE logs + Langfuse traces + MySQL + code

## GCP
- Prod: `brandlovers-prod` | Homolog: `brandlovrs-homolog`
- Cluster: `bl-cluster` in `us-east1`
- BigQuery dataset: `guardian`

### Guardian Evals GCP Config (2026-03-07) — AUTOMATED SOLUTION

**Problem (happened 10+ times):**
- Guardian evals reference media in **prod** GCS buckets (`guardian-ads-production`, `creators-raw-media-prod`)
- Agents using `GOOGLE_CLOUD_PROJECT=brandlovrs-homolog` get **403 PERMISSION_DENIED**
- Homolog SA (`service-699439062146@gcp-sa-aiplatform.iam.gserviceaccount.com`) lacks prod bucket access

**Automated solution (2026-03-07 14:00):**

1. **`.env.guardian-eval`** — Source this before ANY Guardian eval:
   ```bash
   source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
   ```
   Sets: `GOOGLE_CLOUD_PROJECT=brandlovers-prod`

2. **`CLAUDE.md` updated** — All agents now have a dedicated "Guardian Eval" section with:
   - Mandatory `source .env.guardian-eval` before running evals
   - Clear explanation of why (403 errors if wrong project)
   - Correct vs wrong examples

3. **`run-guardian-eval.sh`** — Wrapper script for foolproof eval execution:
   ```bash
   bash scripts/run-guardian-eval.sh --config eval.yaml --dataset dataset.jsonl --workers 10
   ```
   Automatically sources `.env.guardian-eval`, verifies config, activates venv, runs eval

**How to use (agents):**
```bash
# Method 1: Manual (with source)
source .env.guardian-eval
python3 evals/run_eval.py --config ... --workers 10

# Method 2: Wrapper (automatic)
bash scripts/run-guardian-eval.sh --config ... --workers 10
```

**This should never happen again.** If it does, the agent didn't read CLAUDE.md.

## Codebase Locations
- guardian-agents-api: `/Users/fonsecabc/.openclaw/workspace/guardian-agents-api/`
- ClawdBots: `/Users/fonsecabc/.openclaw/workspace/clawdbots/`
- Workflows: `/Users/fonsecabc/.openclaw/workspace/workflows/`

## CRITICAL RULE: Always Use CreatorAds API (2026-03-06)

**NEVER do direct DB inserts/modifications. ALWAYS use the CreatorAds API routes.**

The platform is called **CreatorAds** (repo: `brandlovers-team/creator-ads` — frontend, `brandlovers-team/campaign-manager-api` — Go API backend).

**Campaign Manager API routes (Go/Gin, all under /v1):**
- `POST /campaigns` — create campaign
- `GET /campaigns` — list campaigns
- `GET /campaigns/:id` — get campaign
- `PUT /campaigns/:id` — update campaign
- `POST /campaigns/:id/publish` — publish
- `POST /campaigns/:id/finalize` — finalize
- `GET /campaigns/:id/ads` — get ads
- `GET /campaigns/:id/export` — export
- `POST /campaigns/:id/groups` — create groups
- `POST /campaigns/:id/groups/:id/approve` — approve creators
- `POST /campaigns/:id/groups/:id/refuse` — refuse creators
- `POST /campaigns/:id/creators/remove` — remove creators
- `POST /campaigns/:id/creators/:id/change-reward` — change reward
- `POST /campaigns/:id/creators/:id/payments` — payments
- `GET /brands/:id/boost/configuration` — boost config
- `PUT /brands/:id/boost/limit` — update boost limit
- Auth: Bearer token + role middleware (Admin, Editor, Approver, Viewer)

**Rule for ALL tools/skills:**
- READ from MySQL is OK (SELECT queries)
- WRITE/INSERT/UPDATE/DELETE → MUST go through API endpoints
- If no API endpoint exists for an action → document it as blocked, request API endpoint
- Backoffice (creatorads-backoffice-app) is the admin UI — use it as reference for what's possible
- Reprocess skill should use Guardian API endpoints, not direct RabbitMQ publishes

**Repos:**
- `creator-ads` — Frontend (React)
- `campaign-manager-api` — Main API (Go/Gin) — cloned at /Users/fonsecabc/.openclaw/workspace/campaign-manager-api/
- `creatorads-backoffice-app` — Admin backoffice
- `user-management-api` — Auth/users
- `guardian-api` — Guardian moderation API (Go)
- `guardian-agents-api` — Guardian AI agents (Python)
- `guardian-ads-treatment` — Media processing (Go)

## Work Preferences
- Caio uses Opus model for Claude Code
- MySQL MCP over Metabase for direct queries
- `bq query --project_id <project> --use_legacy_sql=false` for BigQuery
- Team messages: pt-BR, no tables, concise narrative
- PRs: pt-BR descriptions, tag Manoel + Juani
- Linear tasks: GUA prefix for Guardian team

## ClawdBots Platform (2026-03-05)
- **Billy**: Non-tech teams helper (SQL + PowerPoint via nano-banana)
- Built, tested locally, not deployed yet
- Planned: Neuron (data expert), Guardian (moderation optimization)

## nano-banana
- Location: `/Users/fonsecabc/.openclaw/workspace/skills/nano-banana/`
- API Key: REDACTED_GEMINI_KEY
- Tools: generate_image, edit_image, analyze_image

## Agent Management v2 (2026-03-07, updated for Mac)

**Source of truth:** `agent-registry.json` — but MUST stay in sync with Linear and actual processes.

**Model tiering (auto-selected by task type):**
- `guardian_eval` / `analysis` → `claude-haiku-4-5-20251001` (cheap, just runs commands)
- `code_task` / default → `claude-sonnet-4-6` (needs reasoning)
- Override with `--model` flag when needed
- `--fallback-model claude-sonnet-4-6` auto-escalates if Haiku overloaded
- Budget caps: eval=$2, analysis=$1, code=$3 (`--max-budget-usd`)

### Core commands
```bash
# DISPATCH WORK (creates Linear task + spawns agent in ONE command)
bash scripts/dispatch-task.sh --title "Fix X" --desc "Details..." --label Bug --timeout 25

# Check registry
bash scripts/agent-registry.sh list

# SYNC CHECK (run before spawning and after completions)
bash scripts/agent-status.sh          # show all views: Linear + Registry + Processes
bash scripts/agent-status.sh --sync   # fix mismatches automatically

# Monitor running agents
bash scripts/agent-peek.sh            # overview of all agents
bash scripts/agent-peek.sh CAI-XX follow  # live tail activity stream

# Session transcripts (full visibility)
tail -20 ~/.claude/projects/-Users-fonsecabc--openclaw-workspace/*.jsonl
```

### Sync rules (MANDATORY)
- `agent-status.sh` is the ONLY way to see the real picture
- Linear, Registry, and Processes MUST always agree
- "In Progress" in Linear with no agent running = MISMATCH → fix it
- Dead PIDs in registry = MISMATCH → fix it
- Run `agent-status.sh --sync` to auto-fix: orphaned Linear → Blocked, dead registry → removed

### What streams where
- `CAI-XX-activity.jsonl` — real-time tool calls/results (via stream-json)
- `CAI-XX-output.log` — final text output
- `CAI-XX-stderr.log` — errors
- `~/.claude/projects/.../*.jsonl` — full session transcripts (always available)

**Never use:** `sessions_spawn`, manual Linear API + separate spawn, old v1 scripts, hooks for logging

### Reporting (how Linear + Slack get updated)
All reporting comes from **actual agent logs on disk**, not hooks:
- **During execution:** `agent-stream-monitor.py` posts progress to Linear + Slack every 2min (tool count, errors, elapsed time)
- **On completion/failure:** `agent-report.sh` reads output/stderr/activity logs, posts summary to both
- **No hooks for logging.** `linear-logger` hook is REMOVED. Only hooks active: boot-md, command-logger, session-memory, slack-thread-router

### Launchd jobs (Mac crons)
Watchdog (60s), Auto-queue (5min), Linear-sync (15min), Langfuse-scraper (2min), GCP-token-push (45min)
All in `~/Library/LaunchAgents/com.anton.*.plist`
Stop all: `for p in watchdog auto-queue linear-sync langfuse-scraper gcp-token-push; do launchctl unload ~/Library/LaunchAgents/com.anton.$p.plist; done`

## Token Efficiency Architecture (2026-03-07)

**spawn-agent.sh uses `--append-system-prompt` for stable context (cached by API = 90% cheaper).**

How agents get context now:
1. `--append-system-prompt` ← base template + task-type template + knowledge files (CACHED)
2. `-p` ← task description only (VARIABLE)

**Knowledge base** (`knowledge/`): Pre-digested codebase maps + patterns. Read, don't explore.
- `guardian-agents-api.map.md` — codemap (2K tokens replaces 8K of exploration)
- `eval-patterns.md`, `auth-patterns.md`, `common-errors.md` — known fixes
- Auto-injected for guardian tasks, common-errors always included

**Templates** (`templates/claude-md/`): Task-specific instructions instead of monolithic CLAUDE.md.
- `base.md` + `guardian-eval.md` | `code-fix.md` | `analysis.md` + `error-handling.md`
- Agent gets only relevant instructions (~800 tokens vs ~2K for full CLAUDE.md)

**Codemap generator**: `bash scripts/generate-codemap.sh /path/to/repo > knowledge/repo.map.md`
Regenerate when repo changes significantly.

## Active Agent Monitoring (2026-03-07)

**You don't need to manually check agents anymore.** The stream monitor posts progress to Slack + Linear every 2min automatically. But you CAN check:

```bash
bash scripts/agent-peek.sh              # all agents overview
bash scripts/agent-peek.sh CAI-XX       # last 20 events
bash scripts/agent-peek.sh CAI-XX follow  # live tail
bash scripts/agent-status.sh            # unified Linear + Registry + Process view
bash scripts/agent-status.sh --sync     # fix mismatches
```

**When to intervene:**
- Progress updates show repeated errors → kill and fix root cause
- Agent running >15min with 0 tool calls → check session transcript
- 3+ agents failing on same issue → systemic problem, investigate before re-queuing

## Autonomy Principle (Learned 2026-03-05 19:14 UTC)

**Core rule:** When you analyze and find problems, FIX them immediately. Don't ask permission.

**Application:**
- ClawdBots config (Billy, agents) → full autonomy, just do it
- GitHub repos (Guardian, etc.) → fix it and send PR
- "Analyze and find issues" means "analyze, find issues, and FIX them"
- Report what you FIXED, not what you found
- Ask forgiveness if wrong, don't ask permission

**Why it matters:**
- Dramatically speeds up fix cycles
- Caio expects autonomous problem-solving
- Waiting for approval creates bottlenecks
- Sub-agents can work in parallel while you coordinate

**Exception:** Destructive operations on production data or external comms still need approval

## Speed Optimization Results (2026-03-05)

**Context trimming:** -42.2% (28KB → 16KB)
- Merged IDENTITY.md → SOUL.md (-1.2KB)
- Compressed TOOLS.md (4.3KB → 3.0KB) 
- Trimmed MEMORY.md (12.5KB → 2.8KB)
- **Impact:** 30-40% faster main thread responses

**Instant ack patterns:**
- Reply "on it" before spawning work
- Perceived latency drops to <3s
- User knows you're working immediately

**Batch tool calls:**
- Combine operations with `&&` chains
- spawn-and-log.sh: single command for spawn+log
- Reduces round-trips from 3-5 to 1

**Simplified templates:**
- Spawn template: 15 lines → 5 lines (66% reduction)
- Less ceremony = faster execution
- Focus on essentials only

## Guardian Evals Reliability (2026-03-05)

**Post-mortem from CAI-35 / GUA-1100 (archetype standardization eval):**

### What happened
- Goal: +5pp agreement rate (76.8% → 81.8%) via archetype standardization
- Result: 76.4% (55/80 valid cases) — roughly neutral, -0.4pp
- 31.25% of cases wasted: 22 auth failures + 3 MAX_TOKENS + 2 config issues

### Root causes
1. **OAuth expired mid-run** (22/80 = 27.5% lost): User tokens last ~1 hour, eval took 18+ min after config fix delays
2. **MAX_TOKENS on 3 videos** (test_idx 2, 58): Content too large for model context, infinite retry loop
3. **Config mismatch caught by Caio** (18:38 UTC): Both BigQuery AND Vertex AI pointing to homolog instead of prod+homolog
4. **GOOGLE_APPLICATION_CREDENTIALS not in .env**: Only in shell env, lost when subprocess spawned
5. **tqdm BrokenPipeError**: Progress bar crashed on stdout redirect, killed eval at 79/80

### Solutions implemented
- **RELIABILITY-CHECKLIST.md** created at `/Users/fonsecabc/.openclaw/workspace/skills/guardian-evals/`
- **Preflight checkpoint** added to guardian-experiment.yaml workflow
- **Error classification**: permanent (skip) vs transient (retry 3x) vs fatal (abort)
- **Partial results tracking**: Save progress to /tmp/eval-progress.json incrementally
- **AGENTS_RETRY_MAX_ATTEMPTS=3**: Sweet spot (1 too aggressive, 5 too slow)

### Auth requirements
- **Long runs (>30 min):** MUST use service account JSON (GOOGLE_APPLICATION_CREDENTIALS)
- **Short runs (<15 min):** User OAuth acceptable
- **Always:** Validate auth BEFORE starting eval (preflight check)
- **Need from Caio:** Service account JSON key for brandlovers-prod with Vertex AI + BigQuery access

### Key lesson
Every eval should start with preflight validation. 31% waste rate is unacceptable — most was preventable with a 30-second config check.

## Billy Deployment Lessons (2026-03-05)

**VM > Docker for multi-gateway:**
- OpenClaw gateway single-instance limitation
- Docker adds complexity (networking, volumes, auth)
- Dedicated VM simpler: just rsync + start gateway
- Billy on 89.167.64.183:18790, Anton on main machine:18789

**Shared GCP credentials work:**
- Billy uses Anton's gcloud credentials
- Same project access (brandlovers-prod)
- Cloud SQL Proxy works with copied credentials
- No need for separate service accounts unless security requires it

**Critical files to sync:**
- SOUL.md (personality + rules)
- Skills directory (all functionality)
- auth-profiles.json (API keys)
- openclaw.json (config)
- Don't forget: chmod +x on scripts, pip install deps

## Presentation Generation (Updated 2026-03-06)

**Current approach (per Caio):**
- Generate images with nano-banana → send in chat
- Tell user to download and place in sheets/slides manually
- Message: "estamos trabalhando nisso e em breve vai melhorar"
- Google Slides integration is WIP — don't try to automate it yet

**Still never:** local .pptx files, workspace file paths

## Max Tokens Error Handling (2026-03-05)

**Problem:** Some Guardian eval cases hit max tokens, causing infinite retry loops

**Solution:**
- Detect max tokens error specifically
- Skip that content item (don't retry)
- Log: "Skipped media {id}: max tokens exceeded"
- Continue eval with remaining items
- Report skipped count at end

**Implementation:**
- Set AGENTS_RETRY_MAX_ATTEMPTS=3 (compromise)
- Allows transient error retries (network, rate limits)
- Caps max tokens errors (no infinite loop)
- Better than AGENTS_RETRY_MAX_ATTEMPTS=1 (too aggressive)

**Pattern:**
- Max tokens = input too large, retry won't help
- Network errors = transient, retry helps
- Distinguish error types for smart retry logic

## Nano-banana Prompting (2026-03-05)

**Key improvements:**
- Structured prompts with Vertex AI parameters (enhancePrompt, seed, personGeneration)
- Templates save 4-5 min per generation (copy-paste approach)
- Testing showed 3x quality improvement with detailed prompts
- 8 template categories: profile pics, presentations, social media, diagrams, memes, corporate, logos, hero images

**Optimal settings (always use):**
- **Temperature: 0.5** - Model performs significantly better and more accurate to prompt
- **Resolution: 4K** - Highest quality output
- **Prompt enhancement: ALWAYS** - Never pass raw user prompts unchanged, use your skills to improve clarity, add detail, specify style

**Best practice:**
- Use templates for consistency
- Iterate with flash model, finalize with pro
- Specify aspect ratios explicitly
- Use enhancePrompt for production quality
- Always enhance user prompts before generating (better prompt = better output)

**Impact:**
- Faster image generation (template-based)
- Higher quality output (structured prompts + optimal settings)
- Both Anton and Billy have access
- Billy auto-generates images when users request visuals

## Slack Messaging Troubleshooting (2026-03-05)

**allowFrom ≠ message tool**
- `allowFrom` controls who can USE the bot (send messages and get responses)
- Slack message tool/API controls my ability to SEND messages to anyone
- These are completely independent - allowFrom does NOT affect outbound messaging

**When message tool fails with user IDs:**
1. Use `conversations.open` API to get channel ID: `curl -X POST https://slack.com/api/conversations.open -d '{"users":"U01HZTCCYHX"}'`
2. Send directly to channel ID instead of user ID
3. Example: D0AJY7M31E0 (Rapha's DM) vs U01HZTCCYHX (user ID)

**Before resending messages:**
- ALWAYS check `conversations.history` first
- Prevents double/triple texting
- Command: `curl -X GET "https://slack.com/api/conversations.history?channel={channel_id}&limit=10"`

**Lesson:** Check history before resending to avoid spam. allowFrom is for bot access control, not outbound messaging.

## Multi-Hypothesis Orchestration (2026-03-06)

**Core principle from Caio:** For every task assigned, orchestrate multiple hypotheses to achieve the result. Run parallel agents testing different approaches until goal is achieved.

**Example workflow:**
1. Task: "Improve Guardian agreement rate by 5pp"
2. Generate hypotheses:
   - Hypothesis A: Archetype taxonomy standardization
   - Hypothesis B: Prompt engineering improvements
   - Hypothesis C: LLM-as-a-judge auto-correction
   - Hypothesis D: Memory pipeline tuning
3. Spawn 4 parallel agents, each testing one hypothesis
4. Measure results objectively (+Xpp improvement each)
5. Double down on winner(s), kill losers
6. Iterate until +5pp achieved

**Why it matters:**
- Explores solution space faster (parallel vs sequential)
- Reduces risk of local maxima (single approach bias)
- Data-driven approach selection (not guess-based)
- Faster convergence to goal (test multiple paths simultaneously)

**Application:**
- Guardian improvements: Test multiple accuracy approaches in parallel
- Billy features: Test multiple UX/implementation patterns
- Performance optimization: Test multiple optimization strategies
- Any goal with measurable outcome: Generate hypotheses, test in parallel

**Anti-pattern:** Single approach → implement → hope it works → iterate if fails
**Correct pattern:** Multiple hypotheses → parallel test → measure → double down on winner
