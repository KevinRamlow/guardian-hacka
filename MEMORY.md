# MEMORY.md - Long-Term Knowledge

## Guardian System (as of 2026-03-05)

### Key Architecture Points
- **Framework**: Google ADK + FastAPI
- **2-phase moderation**: Phase 1 (visual+audio WITH video) → Phase 2 (text-only, routes by guideline type)
- **Severity scale**: 1-2 rejected, 3 tolerated, 4-5 approved (level 3 boundary = critical tuning point)
- **Agentic model ID**: `audio_output` key in `proofread_medias.metadata` JSON
- **A/B split**: even creator IDs = agentic, odd = old model
- **Memory pipelines**: Tolerance + error patterns in BigQuery, DBSCAN clustering (eps=0.1, min_samples=3)

### Metrics (2026-03-07/08 — CORRECTED BASELINES)
**Dataset:** guidelines_combined (121 cases)

| Branch/Run | Accuracy | Correct | Notes |
|---|---|---|---|
| main (extrapolated) | **86.78%** | 105/121 | ⚠️ UNRELIABLE — only 37 cases measured, rest extrapolated |
| feat/GUA-1101 (run_182248) | 76.03% | 92/121 | First real full run |
| feat/GUA-1101 (run_194401) | 79.34% | 96/121 | Pre-archetype injection |
| feat/GUA-1101 (run_003327) | 78.51% | 95/121 | Post-archetype injection (GUA-1101) |

**Real baseline on combined dataset: ~79%** (feature branch). Main branch likely similar.
- The 86.78% extrapolation is NOT reliable — real main branch likely 76-80%
- GUA-1101 archetype injection: neutral (-0.83pp, 20 improvements / 21 regressions = noise)

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
- guardian-agents-api: `/Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real/`
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
- API Key: stored in `.env.secrets` (GEMINI_API_KEY)
- Tools: generate_image, edit_image, analyze_image

## Task Management v3 (2026-03-09 — Unified State Machine)

**Single source of truth:** `state.json` (`/Users/fonsecabc/.openclaw/tasks/state.json`)

### State Machine
```
todo → agent_running → [done | failed | blocked | eval_running]
eval_running → callback_pending → agent_running → ...
```

### Core Scripts (5 scripts replace 50+)
| Script | Purpose |
|---|---|
| `task-manager.sh` | State CRUD + transitions. ALL state goes through this. |
| `dispatcher.sh` | Create Linear task + register state + spawn agent |
| `supervisor.sh` | Unified launchd (30s): PID checks, completions, callbacks, timeouts, orphans |
| `reporter.sh` | Report to Linear + Slack + dashboard |
| `spawn-agent.sh` | Low-level agent spawner (called by dispatcher/supervisor) |

### Commands
```bash
# Dispatch work
bash scripts/dispatcher.sh --title "Fix X" --desc "Details" --label Bug --timeout 25

# Check state
bash scripts/task-manager.sh list              # all tasks
bash scripts/task-manager.sh list --status agent_running  # running only
bash scripts/task-manager.sh get AUTO-XX       # single task detail
bash scripts/task-manager.sh slots             # available spawn slots

# Monitor
bash scripts/reporter.sh peek                  # overview
bash scripts/reporter.sh peek AUTO-XX          # detail
bash scripts/reporter.sh peek AUTO-XX follow   # live tail

# Feedback loop
bash scripts/task-manager.sh add-history AUTO-XX '{"cycle":1,"accuracy":78.5}'
bash scripts/task-manager.sh add-learning AUTO-XX "what worked"
```

### Feedback Loop (first-class citizen)
Each task carries `history[]` and `learnings[]`. When a callback agent spawns, it gets:
1. Full history array (what was tried, accuracy per cycle, deltas)
2. Learnings (extracted patterns from previous cycles)
3. Original context

Callback agents must update these after analyzing results.

### Scheduling (2 launchd jobs)
| Job | Interval | What |
|---|---|---|
| `com.anton.supervisor` | 30s | PID checks, completions, callbacks, timeouts, orphans, health |
| `com.anton.infra` | 15min | Linear sync, GCP tokens, Langfuse, state cleanup |

Old jobs removed: watchdog, process-checker, linear-sync, langfuse-scraper, gcp-token-push

### Backward Compatibility
- `spawn-agent.sh` calls `task-manager.sh register` for state tracking
- `task-manager.sh` supports legacy API: `register`, `count`, `slots`, `has`, `json`

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

## Agent Monitoring (2026-03-09)

**Supervisor runs every 30s** — handles PID checks, completions, callbacks, timeouts automatically.

```bash
bash scripts/task-manager.sh list              # all tasks + states
bash scripts/task-manager.sh get AUTO-XX       # single task detail
bash scripts/reporter.sh peek                  # overview
bash scripts/reporter.sh peek AUTO-XX          # detail
bash scripts/reporter.sh peek AUTO-XX follow   # live tail
```

**When to intervene:**
- Same task failing 3+ times → investigate root cause
- Agent running >15min with 0 tool calls → check session transcript
- Systemic failures → pause auto-queue, fix pipeline

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

## Billy (STOPPED — 2026-03-07)

Billy VM (89.167.64.183) is currently stopped. Anton migrated to Caio's Mac.
If reactivated: needs rsync of workspace, chmod +x scripts, shared GCP creds.

## Presentation Generation (Updated 2026-03-08)

**Full pipeline now working:**
1. Generate slide images with nano-banana (Gemini `gemini-3-pro-image-preview`, 16:9, temp 0.5, 4K)
2. Build .pptx with `python3 skills/presentations/scripts/build_deck.py`
3. Upload to Google Slides via `--upload --account caio.fonseca@brandlovers.ai`
4. Return shareable Google Slides URL

**Templates available** (in `skills/presentations/TEMPLATES.md`):
1. Circular Process Diagram — cycles, feedback loops
2. Metrics Dashboard — KPIs, key numbers
3. Architecture / Flow Diagram — system design, data flows
4. Title / Cover Slide — presentation covers, section dividers
5. Comparison / VS — before/after, A vs B
6. Feature Grid — capabilities, benefits, deliverables
7. Timeline / Roadmap — milestones, phases, evolution
8. Linear Process / Pipeline — sequential workflows, funnels

**Rules:**
- Always enhance prompts before generating (better prompt = better slide)
- Always use 16:9, always use gemini-3-pro-image-preview
- Portuguese text is fine — Gemini handles pt-BR well
- Keep text short — slides should be visual
- If Drive auth fails: `gog auth add <email> --services gmail,calendar,drive`

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

## Guardian Eval Management (2026-03-09 — Unified State Machine)

### Agent workflow for evals:
```bash
# 1. Make changes, commit
# 2. Launch eval
bash scripts/run-guardian-eval.sh --config ... --workers 10
EVAL_PID=$(cat /tmp/guardian-eval.pid)

# 3. Transition to eval_running (supervisor handles completion + callback)
bash scripts/task-manager.sh transition AUTO-XX eval_running \
  --process-pid $EVAL_PID --process-type eval --context "what changed"

# 4. Exit cleanly — supervisor takes over
```

### How it works:
- `supervisor.sh` runs every 30s (launchd: `com.anton.supervisor`)
- Detects when eval PID dies → reads metrics.json → transitions to `callback_pending`
- Spawns callback agent with full results + history + learnings
- Callback agent reviews and continues the cycle

### Feedback loop:
- Callback agent gets `history[]` (all previous cycles) + `learnings[]` (what worked/didn't)
- Must update both after analyzing: `task-manager.sh add-history` + `add-learning`
- Each cycle builds on previous knowledge — no more starting from scratch


## Guardian Continuous Improvement Loop (2026-03-09 — Unified)

**Cycle: Agent → eval_running → callback_pending → Agent → ...**

1. Agent implements changes → launches eval → `task-manager.sh transition eval_running`
2. Supervisor detects completion → `callback_pending`
3. Callback agent spawned with history + learnings + results
4. If improvement: commit, done. If regression: refine, launch another eval
5. Each cycle accumulates knowledge in history[] and learnings[]


## Guardian Eval Dashboard (2026-03-08)

**Live dashboard at:** http://localhost:8765/guardian-eval-dashboard.html

**Features:**
- Target accuracy tracking (87% = 79% baseline + 8pp)
- Current eval progress (if running)
- Recent runs with accuracy + delta
- Auto-refresh every 30s

**Scripts:**
- `scripts/cockpit-eval-data.sh` — JSON data provider
- `scripts/generate-eval-dashboard.py` — HTML generator
- Regenerate: `python3 scripts/generate-eval-dashboard.py /tmp/guardian-eval-dashboard.html`

**Integration with cockpit server:** Dashboard auto-served at port 8765 alongside agent cockpit.


## Anton Auto-Loop Integration (2026-03-08)

### Two-Level Self-Training System

**Inspired by Karpathy's autoresearch** - agent improves product AND itself.

**Guardian Loop (every 4h):**
- Target: 87% accuracy (current: 79.3%)
- Spawns 3 agents, fast eval (5 min), full validation (35 min)
- Auto-commits if +1pp improvement
- Launchd: `com.anton.auto-loop`

**Meta Loop (every 24h):**
- Target: 85% agent success rate (current: 60%)
- Spawns 2 meta-agents improving templates, spawn scripts, codemaps
- Auto-commits if +5% success rate improvement
- Launchd: `com.anton.meta-loop`

**Key Files:**
- `OBJECTIVES.md` - Control panel (Guardian + Meta targets)
- `scripts/anton-auto-loop.sh` - Guardian improvement
- `scripts/anton-meta-loop.sh` - Meta self-improvement
- `scripts/fast-eval.sh` - 5-min eval (10% dataset)
- `.shortcuts/auto-loop-status` - Quick status check
- `docs/ANTON-ARCHITECTURE.md` - System design
- `docs/SON-OF-ANTON-SETUP.md` - Son of Anton monitoring setup

**Status Check:**
```bash
bash ~/.openclaw/workspace/.shortcuts/auto-loop-status
```

### Son of Anton Integration

Son of Anton (ClawdBot on 89.167.23.2) monitors Anton's auto-loops:

**Every 4h:**
- SSH to Mac, check `.anton-auto-state.json` and `.anton-meta-state.json`
- Post status to #replicants if cycle completed
- Alert if loops offline or stagnant (no improvement in 3 cycles)
- Run backlog generator if Linear queue empty

**Daily (09:00 BRT):**
- Post summary (Guardian progress, Meta improvements, commits, ETA)

**Setup files:**
- `docs/SON-OF-ANTON-SETUP.md` - Complete monitoring setup
- `docs/SON-OF-ANTON-HEARTBEAT.md` - ClawdBot HEARTBEAT.md content

**SSH Setup Required:**
1. Son of Anton generates SSH key
2. Add public key to Mac's `~/.ssh/authorized_keys`
3. Test: `ssh caio@<mac-ip> "bash ~/.openclaw/workspace/.shortcuts/auto-loop-status"`

**Environment Variables for Son of Anton:**
- `ANTON_MAC_IP` - Caio's Mac IP
- `LINEAR_API_KEY` - For backlog checks

### Expected Results

**Week 1:** Guardian +1-2pp, Meta templates simplified
**Month 1:** Guardian 87% target, Meta 85% success rate
**Compounding:** Better platform → better agents → faster improvements

### How It's Different from Today

**Before:** Caio defines goal → Anton spawns agents → Caio reviews → repeat
**After:** Caio edits OBJECTIVES.md → Anton auto-improves 24/7 → Son of Anton monitors

**Key insight from Karpathy:** Agent should improve BOTH the product AND the platform (itself).

## SSH Auto-Connect Configuration (2026-03-08)

### VMs Conectados

**Son of Anton (ClawdBot):**
- Host: caio@89.167.23.2
- Workspace: /home/caio/workspace
- Role: Monitoring Anton's auto-loops, posting to #replicants

**Billy (OpenClaw):**
- Host: root@89.167.64.183
- Workspace: /root/.openclaw/workspace
- Role: Data helper bot for non-tech teams

**SSH Keys:** Caio added Anton's public key to both VMs → passwordless connection

### Auto-Sync System

**Script:** `scripts/sync-replicants.sh`
**Schedule:** Every 4 hours via launchd (`com.anton.sync-replicants`)
**Direction:** Bidirectional (Anton ↔ Son of Anton)

**What syncs:**
- Docs (architecture, setup)
- OBJECTIVES.md
- State files (.anton-auto-state.json, .anton-meta-state.json)
- Scripts + skills

**What does NOT sync:**
- memory/ files (each entity keeps own memories)
- SOUL.md (separate identities)

**Philosophy:** Entities share objective knowledge, keep subjective experiences separate.

### Verification Commands

```bash
# Check auto-loops status
bash ~/.openclaw/workspace/.shortcuts/auto-loop-status

# Check sync status
bash ~/.openclaw/workspace/.shortcuts/sync-status

# Test SSH
ssh caio@89.167.23.2 "hostname"  # → clawdbot-caio
ssh root@89.167.64.183 "hostname"  # → ubuntu-4gb-hel1-1
```

### Integration

**Guardian Loop:** Syncs after each cycle completion
**Meta Loop:** Syncs after improvements
**Sync Loop:** Runs independently every 4h

**Result:** Anton works autonomously, Son monitors, both stay synchronized.
