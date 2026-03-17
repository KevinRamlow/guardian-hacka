# MEMORY.md - Long-Term Knowledge

## Git Self-Modification Workflow

Para commitar e fazer push de mudanças no meu próprio código, usar SEMPRE o script `scripts/git-self.sh`:

```bash
# Ver o que mudou vs origin/main
bash scripts/git-self.sh status

# Commitar e fazer push direto pra main
bash scripts/git-self.sh commit "fix: description of change"

# Sincronizar workspace com origin/main
bash scripts/git-self.sh sync
```

**⚠️ ATENÇÃO: cada push pra main dispara um rebuild Docker e reinicia o gateway.**
Não fazer push após cada pequena mudança. Acumular todas as alterações de uma sessão de trabalho e fazer **um único commit** quando o conjunto de mudanças estiver completo e testado.

**NUNCA** fazer `git init` manualmente no workspace. O repo root é um nível acima de `workspace/` — o script `git-self.sh` lida com esse mapeamento automaticamente (clona em /tmp/replicants-self-clone, copia os arquivos, commita do root correto).

Se o clone em /tmp ficar corrompido: `bash scripts/git-self.sh status --force-reclone`

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

### Guardian Evals GCP Config (2026-03-07)
- **Problem:** Evals use prod GCS buckets → 403 if project set to homolog
- **Solution:** Always `source .env.guardian-eval` or use `bash scripts/run-guardian-eval.sh --config ... --workers 10`
- Both methods set `GOOGLE_CLOUD_PROJECT=brandlovers-prod` automatically.

## Codebase Locations
- guardian-agents-api: `${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/guardian-agents-api-real/`

## Repos — Separated Agent Workspaces (2026-03-09)

Each agent has its own isolated GitHub repo. No cross-contamination of SOUL.md or identity files.

| Repo | Agent | URL |
|------|-------|-----|
| `replicants-anton` | Me (Anton) | github.com/fonsecabc/replicants-anton |
| `replicants-billy` | Billy | github.com/fonsecabc/replicants-billy |

Billy repo is cloned inside my workspace but gitignored — it pushes/pulls independently.

### Security
All secrets centralized in `$OPENCLAW_HOME/.env` (gitignored). Scripts read from env vars:
`$GEMINI_API_KEY`, `$SLACK_USER_TOKEN`, `$METABASE_API_KEY`, `$GITHUB_TOKEN`, `$GOG_KEYRING_PASSWORD`
Git history was scrubbed with `git-filter-repo` — zero secrets in any past commit.

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
- `campaign-manager-api` — Main API (Go/Gin) — cloned at ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/campaign-manager-api/
- `creatorads-backoffice-app` — Admin backoffice
- `user-management-api` — Auth/users
- `guardian-api` — Guardian moderation API (Go)
- `guardian-agents-api` — Guardian AI agents (Python)
- `guardian-ads-treatment` — Media processing (Go)

## CRITICAL: Message Dedup Rules (2026-03-10, 3 incidents today)
- **ONE message per task result. EVER.** Never send the same result in 2+ messages.
- After reporting ANY task/eval result in conversation → IMMEDIATELY `bash scripts/task-manager.sh set-field <ID> reportedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"`
- Heartbeat runs with `lightContext` — can't see what main thread said. `reportedAt` is the ONLY dedup guard.
- When Caio replies "sim"/"continue" → answer ONLY the follow-up. Do NOT re-summarize.
- Each text block = separate Slack message. Consolidate into ONE block.

## Work Preferences
- Caio uses Opus model
- MySQL MCP over Metabase for direct queries
- `bq query --project_id <project> --use_legacy_sql=false` for BigQuery
- Team messages: pt-BR, no tables, concise narrative
- PRs: pt-BR descriptions, tag Manoel + Juani
- Linear tasks: GUA prefix for Guardian team

## ClawdBots / Agent Platform (2026-03-05, updated 2026-03-09)
- **Billy**: Non-tech teams helper (SQL + PowerPoint via nano-banana) — own repo: `replicants-billy`
- **Neuron**: Data expert (BigQuery/MySQL) — included in Billy repo under clawdbots/
- Built, tested locally, not deployed yet

## nano-banana
- Location: `${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/skills/nano-banana/`
- API Key: stored in `$OPENCLAW_HOME/.env` (GEMINI_API_KEY)
- Tools: generate_image, edit_image, analyze_image

## Task Management v4 (2026-03-10 — Atomic Architecture)

**Single source of truth:** `state.json` (`${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json`)

### State Machine
```
todo → agent_running → [done | failed | blocked | eval_running]
todo → eval_running (agentless eval via --eval flag)
eval_running → [callback_pending | done | failed | timeout | blocked]
callback_pending → agent_running → ...
```

### Architecture (4 scripts + 1 brain)
| Component | Sole Responsibility |
|---|---|
| `task-manager.sh` | State CRUD + transitions (flock-protected) |
| `dispatcher.sh` | THE only spawn path: Linear + state + spawn + exit-code watcher |
| `kill-agent-tree.sh` | Kill PID tree (utility) |
| `guardrails.sh` | Invariant checks |
| **HEARTBEAT.md** | The brain: Slack reporting, timeouts, orphans, callbacks |

**Deprecated (2026-03-10):** supervisor.sh, spawn-agent.sh, reporter.sh, agent-report.sh, link-logs-to-linear.sh, alert-dedup.sh, agent-logger.sh

### Commands (Story-Based Task Management)
```bash
# Create NEW story (creates Linear task — outcome-oriented title)
bash scripts/dispatcher.sh --title "Improve TC accuracy from 51% to 70%" --desc "Details" --role developer

# Iteration on existing story (NO new Linear task — logs as comment on parent)
bash scripts/dispatcher.sh --parent AUTO-XX --title "Fix a_partir_de" --role developer "details"

# Eval as sub-task of story (NO new Linear task — logs as comment on parent)
bash scripts/dispatcher.sh --eval --parent AUTO-XX --title "Eval post-fix"

# Reopen a done story for more work (clears completedAt/reportedAt, keeps history)
bash scripts/task-manager.sh reopen AUTO-XX

# Spawn for existing task (callbacks, re-runs)
bash scripts/dispatcher.sh --task AUTO-XX --role developer "prompt text"

# Check state
bash scripts/task-manager.sh list
bash scripts/task-manager.sh get AUTO-XX
bash scripts/task-manager.sh slots
bash scripts/task-manager.sh next-local-id

# NEVER create Linear task for: evals, fix iterations, reviews, re-attempts
```

### How Completions Work
1. dispatcher.sh spawns agent + launches exit-code watcher (background process)
2. When agent dies, watcher: checks output quality → transitions state → logs to Linear
3. Heartbeat (5min) reads state.json → reports to Slack → handles timeouts/orphans/callbacks

## BMAD-Inspired Role Architecture (2026-03-09)

All agents are **OpenClaw native sub-agents** (`openclaw agent --agent <role>`). Each role has a dedicated workspace.

### Registered Agents (`openclaw agents list`)
| Agent | Workspace | Purpose |
|---|---|---|
| `developer` | `workspace-developer/` | Code implementation, bug fixes |
| `reviewer` | `workspace-reviewer/` | Adversarial code review (auto-spawned post-completion) |
| `architect` | `workspace-architect/` | System design, ADRs |
| `guardian-tuner` | `workspace-guardian-tuner/` | Guardian accuracy optimization |
| `debugger` | `workspace-debugger/` | Root cause analysis |

### How It Works
- `openclaw agent --agent <role>` — gateway manages lifecycle, SOUL.md loaded from workspace
- Each workspace has SOUL.md + AGENTS.md + symlinks to shared resources (scripts, skills, knowledge, config, env)
- Completion detected via exit-code file written when agent finishes
- PID tracked for timeout kills

### Spawn Examples
```bash
bash scripts/dispatcher.sh --title "Fix X" --role developer --timeout 15
bash scripts/dispatcher.sh --title "Tune Guardian" --role guardian-tuner --timeout 60
bash scripts/dispatcher.sh --title "Big refactor" --role developer --mode interactive
```

### Review Hook
- `review-hook.sh` auto-fires after every task completion via dispatcher.sh exit-code watcher
- Config: `config/review-config.json` (enabled, min_output_bytes, require_git_changes)
- Loop prevention: skips REVIEW-* IDs, review sources, review labels

## Token Efficiency Architecture (2026-03-09)

**Context comes from each agent's workspace SOUL.md** — loaded natively by OpenClaw gateway. No template injection needed.

**Knowledge base** (`knowledge/`): Pre-digested codebase maps + patterns. Symlinked into each workspace.
- `guardian-agents-api.map.md` — codemap (2K tokens replaces 8K of exploration)
- `eval-patterns.md`, `auth-patterns.md`, `common-errors.md` — known fixes
- Agents read these from their workspace symlinks as needed

**Codemap generator**: `bash scripts/generate-codemap.sh /path/to/repo > knowledge/repo.map.md`
Regenerate when repo changes significantly.

## Agent Monitoring (2026-03-10)

**Heartbeat (HEARTBEAT.md) is the sole monitor.** No supervisor script.

```bash
bash scripts/task-manager.sh list              # all tasks + states
bash scripts/task-manager.sh get AUTO-XX       # single task detail
```

**When to intervene:**
- Same task failing 3+ times → investigate root cause
- Agent running >15min with 0 tool calls → check session transcript
- Systemic failures → fix pipeline, reduce maxConcurrent if needed

## Autonomy Principle
- Fix problems immediately, report what you fixed. Exception: destructive prod ops need approval. Full details in SOUL.md.

## Speed Optimization (2026-03-05)
- Context trimming (-42%) + instant ack ("on it" before spawning) + batch tool calls (`&&` chains) = 30-40% faster responses

## Guardian Evals Reliability (2026-03-05)
- Always run preflight validation before evals (auth, config, GCP project)
- Long runs (>30 min): use service account JSON, not OAuth (tokens expire ~1h)
- Classify errors: permanent (skip) vs transient (retry 3x) vs fatal (abort)
- Save progress incrementally to `/tmp/eval-progress.json`
- RELIABILITY-CHECKLIST.md at `skills/guardian-evals/` has full details

## Billy (STOPPED — 2026-03-07, separated 2026-03-09)

Billy VM (89.167.64.183) is currently stopped. Own repo: `replicants-billy`.
If reactivated: clone repo, configure .env, chmod +x scripts, shared GCP creds.

## Presentation Generation (Updated 2026-03-08)

**Full pipeline now working:**
1. Generate slide images with nano-banana (Gemini `gemini-3-pro-image-preview`, 16:9, temp 0.5, 4K)
2. Build .pptx with `python3 skills/presentations/scripts/build_deck.py`
3. Upload to Google Slides via `--upload --account caio.fonseca@brandlovers.ai`
4. Return shareable Google Slides URL

**8 templates available** in `skills/presentations/TEMPLATES.md`.

**Rules:**
- Always enhance prompts before generating (better prompt = better slide)
- Always use 16:9, always use gemini-3-pro-image-preview
- Portuguese text is fine — Gemini handles pt-BR well
- Keep text short — slides should be visual
- If Drive auth fails: `gog auth add <email> --services gmail,calendar,drive`

## Max Tokens Error Handling (2026-03-05)
- Max tokens = permanent error (skip item, don't retry). Network errors = transient (retry up to 3x).
- `AGENTS_RETRY_MAX_ATTEMPTS=3` — sweet spot for balancing retries vs infinite loops.

## Nano-banana Prompting (2026-03-05)
- **Always:** temp 0.5, resolution 4K, enhance prompts before generating (never pass raw user input)
- Use templates for consistency (8 categories in `skills/nano-banana/`)
- Iterate with flash model, finalize with pro

## Slack Messaging (2026-03-05)
- `allowFrom` = who can use bot (inbound). Does NOT affect outbound messaging.
- If message tool fails with user ID: use `conversations.open` to get channel ID first. Always check `conversations.history` before resending to avoid spam.

## Multi-Hypothesis Orchestration (2026-03-06)
- For every task: spawn parallel agents testing different hypotheses, measure, double down on winners
- Full framework in SOUL.md under orchestration principles

## Guardian Eval Cycle (2026-03-10 — Updated: Agentless Evals)

**Two eval launch modes:**

### 1. Agentless Eval (PREFERRED — saves tokens, no separate Linear task)
```bash
# Launch eval as sub-task of story (creates LOCAL-N, logs as comment on parent)
bash scripts/dispatcher.sh --eval --parent AUTO-XX --title "Eval: post fix"
bash scripts/dispatcher.sh --eval --parent AUTO-XX --title "Eval: custom" --eval-config path/to/eval.yaml --eval-workers 10
```
**Flow:** `dispatcher.sh --eval --parent` → creates LOCAL-N in state.json (no Linear task) → launches eval process → `eval_running` → watcher detects death → auto-extracts accuracy → logs to parent's Linear task as comment → `callback_pending` → heartbeat spawns callback

### 2. Agent-Launched Eval (legacy, when agent needs to make changes first)
**Flow:** Agent changes → `eval_running` → heartbeat detects process death → `callback_pending` → heartbeat spawns callback agent

### State machine (updated)
```
todo → eval_running (agentless, via --eval)
todo → agent_running → eval_running (agent-launched)
eval_running → callback_pending → agent_running → ...
```

### Key features
- `--parent AUTO-XX` links eval to the improvement task that triggered it
- Eval watcher auto-extracts accuracy from metrics.json → stores in history[]
- Dashboard shows eval_running + callback_pending tasks with parent linkage
- Default timeout: 90min (evals take time)


## Guardian Eval Dashboard (2026-03-08)
- **URL:** http://localhost:8765/guardian-eval-dashboard.html (auto-refresh 30s)
- Tracks target accuracy (87%), current eval progress, recent runs with delta
- Part of dashboard server on port 8765


## SSH & VMs (2026-03-09)
- **Billy VM** (`89.167.64.183`) — STOPPED. Own repo: `replicants-billy`.
- **Son of Anton VM** (`89.167.23.2`) — Own repo: `replicants-son-of-anton`. Uses ClawdBot, not OpenClaw.
