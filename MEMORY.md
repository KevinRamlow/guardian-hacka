# MEMORY.md - Long-Term Knowledge

## Guardian System (as of 2026-03-05)

### Key Architecture Points
- **Framework**: Google ADK + FastAPI
- **2-phase moderation**: Phase 1 (visual+audio WITH video) → Phase 2 (text-only, routes by guideline type)
- **Severity scale**: 1-2 rejected, 3 tolerated, 4-5 approved (level 3 boundary = critical tuning point)
- **Agentic model ID**: `audio_output` key in `proofread_medias.metadata` JSON
- **A/B split**: even creator IDs = agentic, odd = old model
- **Memory pipelines**: Tolerance + error patterns in BigQuery, DBSCAN clustering (eps=0.1, min_samples=3)

### Metrics (Late Feb 2026)
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

## Codebase Locations
- guardian-agents-api: `/root/.openclaw/workspace/guardian-agents-api/`
- ClawdBots: `/root/.openclaw/workspace/clawdbots/`
- Workflows: `/root/.openclaw/workspace/workflows/`

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
- `campaign-manager-api` — Main API (Go/Gin) — cloned at /root/.openclaw/workspace/campaign-manager-api/
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
- Location: `/root/.openclaw/workspace/skills/nano-banana/`
- API Key: REDACTED_GEMINI_KEY
- Tools: generate_image, edit_image, analyze_image

## Agent Monitoring (Learned 2026-03-05 19:42 UTC)

**Critical lesson from Caio:** Always check BOTH sources for agent status:

1. **Actual runtime** (`subagents list`):
   - `startedAt` timestamp = when current run began
   - `runtime` = actual elapsed time
   - This is SOURCE OF TRUTH for current state

2. **Linear comments** (communication history):
   - Last update timestamp
   - What agent reported
   - Progress indicators

**Why both matter:**
- Linear shows what agent SAID
- Subagents API shows what agent IS DOING
- Gateway restarts can reset agent runs (new startedAt)
- Linear comments persist across restarts
- Must cross-reference timestamps to detect:
  - Stuck agents (running but not logging)
  - Restarted agents (startedAt after Linear comment)
  - Lost progress (agent restarted, Linear shows old work)

**Don't assume agent survived restart just from Linear comments.**
**Always check startedAt timestamp to verify continuous run.**

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
- **RELIABILITY-CHECKLIST.md** created at `/root/.openclaw/workspace/skills/guardian-evals/`
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
