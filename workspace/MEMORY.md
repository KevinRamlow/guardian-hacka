# MEMORY.md - Long-Term Knowledge

## Current Infrastructure State (2026-03-14)

**Pod:** GKE `bl-cluster` us-east1, OpenClaw 2026.3.8 (updates to 2026.3.12 never landed)
**Workspace:** Files restored but NOT connected to `replicants-anton` repo (no git remote)
**Missing:** `gog` CLI, `mcporter` CLI
**Restored:** guardian-agents-api cloned, gcloud SDK installed, SA credentials decoded, eval .env configured
**OPENCLAW_HOME:** Set to `/home/node` — correct per AGENTS.md (`$OPENCLAW_HOME/.openclaw/workspace/`)
**Pipeline:** 0 tasks, 3/3 slots free, idle since Mar 12

## Guardian System

### Architecture
- **Framework**: Google ADK + FastAPI
- **2-phase moderation**: Phase 1 (visual+audio WITH video) → Phase 2 (text-only, routes by guideline type)
- **Severity scale**: 1-2 rejected, 3 tolerated, 4-5 approved (level 3 boundary = critical tuning point)
- **Agentic model ID**: `audio_output` key in `proofread_medias.metadata` JSON
- **A/B split**: even creator IDs = agentic, odd = old model
- **Memory pipelines**: Tolerance + error patterns in BigQuery, DBSCAN clustering

### Eval Infrastructure (default config)
- **Repo**: `guardian-agents-api` cloned to `$OC_HOME/workspace/guardian-agents-api-real/`
- **Venv**: `.venv/` inside repo, install via `pip install -e .`
- **GCP credentials**: SA at `$OC_HOME/gcp-credentials.json` (must be decoded JSON, NOT base64)
- **CRITICAL**: `GOOGLE_GENAI_USE_VERTEXAI=1` required — without it, Gemini API mode fails (audio_timestamp error)
- **gcloud SDK**: `$HOME/google-cloud-sdk/bin/` — activate SA with `gcloud auth activate-service-account --key-file=...`
- **Eval .env** at `guardian-agents-api-real/.env`:
  ```
  MAIN_PATH=/guardian-agents-api
  GOOGLE_GENAI_USE_VERTEXAI=1
  GOOGLE_CLOUD_PROJECT=brandlovers-prod
  GOOGLE_CLOUD_LOCATION=us-east1
  GOOGLE_ACCOUNT_CREDENTIALS=<base64 of SA JSON>
  GOOGLE_APPLICATION_CREDENTIALS=/home/node/.openclaw/gcp-credentials.json
  LANGFUSE_TRACING_ENVIRONMENT=eval
  PIPELINE_ENABLED=false
  MAX_PARALLEL_AGENTS=5
  ```
- **Eval command**: `.venv/bin/python3 evals/run_eval.py --config evals/content_moderation/eval.yaml --dataset <path> --workers 15`
- **Datasets**:
  - `evals/content_moderation/all/human_evals_combined_dataset.jsonl` — 650 cases (full human evals)
  - `evals/content_moderation/all/guidelines_combined_dataset.jsonl` — 121 cases
  - Per-classification: `general/`, `time_constraints/`, `captions/`, `brand_safety/`, `video_duration/`
- **Performance**: ~38s/case, 15 workers ≈ 45-60min for 650 cases
- **Runs saved to**: `evals/.runs/content_moderation/run_YYYYMMDD_HHMMSS/`

### Metrics (2026-03-07/08)
- **Real baseline: ~79%** on combined dataset (121 cases). Main branch likely 76-80%.
- 86.78% extrapolation is NOT reliable (only 37 cases measured)
- GUA-1101 archetype injection: neutral (-0.83pp)
- CTA guidelines: 76.9% → 92.3% (+15.4pp) — biggest improvement area
- Cost per moderation: ~$0.052

### Known Problems
- CTA guidelines sometimes misclassified as GENERAL instead of TIME_CONSTRAINTS
- Color-of-clothing guidelines (Kibon, Sprite) — agent too tolerant
- Semantic paraphrase (Mercado Pago, Vizzela, GOL) — hard to detect exact wording
- Brand safety answers inverted: `answer: false` = DOES violate (NOT safe)
- Small eval datasets (<25 samples) misleading — 1 flip = 4-5pp change

### Lessons Learned
- Check tolerance + error patterns BEFORE changing prompts
- Phase 1 quality is foundation — Phase 2 can't fix missed details
- Anti-error patterns in severity prompt prevent repeating mistakes
- Debug path: GKE logs + Langfuse traces + MySQL + code

## GCP
- Prod: `brandlovers-prod` | Homolog: `brandlovrs-homolog`
- Cluster: `bl-cluster` in `us-east1` | BigQuery dataset: `guardian`
- Evals use prod GCS buckets → always `source .env.guardian-eval` or `bash scripts/run-guardian-eval.sh`

## Repos
- `replicants-anton` — My workspace (github.com/fonsecabc/replicants-anton) — NOT connected yet
- `replicants-billy` — Billy agent (github.com/fonsecabc/replicants-billy) — STOPPED
- `guardian-agents-api` — Python multi-agent system — cloned at `guardian-agents-api-real/`
- `campaign-manager-api` — Go API backend
- `guardian-api` — Go content moderation API
- `guardian-ads-treatment` — Ads processing (Go)
- `creator-ads` — Frontend (React)

## CRITICAL RULES

### Eval Flow: ALWAYS Use Dispatcher --eval, NEVER Agent
- **Evals MUST be launched via `dispatcher.sh --eval`** (agentless). Agents waste tokens running evals.
- **Correct flow for improvement cycle:**
  1. Create the task (Linear story)
  2. Launch eval via `dispatcher.sh --eval --parent <TASK_ID>` — this runs the eval process directly, no agent
  3. When eval completes (callback_pending), spawn an agent for the SAME task to analyze results + create backlog/implement fixes
- **Agent = analysis + code changes. Eval = just run the eval process.**
- Never let an agent run `run-guardian-eval.sh` — it burns tokens waiting for a long process

### Always Use CreatorAds API
- READ from MySQL: OK (SELECT queries)
- WRITE/INSERT/UPDATE/DELETE → MUST go through Campaign Manager API (`/v1/*`)
- No direct DB modifications. No direct RabbitMQ publishes.

### Message Dedup (3 incidents 2026-03-10)
- ONE message per task result. EVER.
- After reporting → IMMEDIATELY set `reportedAt` in state.json
- Heartbeat uses `lightContext` — `reportedAt` is the ONLY dedup guard

## Work Preferences
- Opus model for development
- MySQL MCP over Metabase for direct queries
- `bq query --project_id <project> --use_legacy_sql=false` for BigQuery
- Team messages: pt-BR, no tables, concise narrative
- PRs: pt-BR descriptions, tag Manoel + Juani
- Linear: GUA prefix for Guardian, AUTO for orchestration

## Task Management v4

**State:** `${OPENCLAW_HOME:-$HOME}/.openclaw/tasks/state.json`
**Architecture:** task-manager.sh (CRUD) + dispatcher.sh (spawn) + kill-agent-tree.sh + guardrails.sh + HEARTBEAT.md (brain)

```bash
# Quick ref
bash scripts/dispatcher.sh --title "Title" --role developer          # New story
bash scripts/dispatcher.sh --parent AUTO-XX --title "Sub" --role dev  # Iteration
bash scripts/dispatcher.sh --eval --parent AUTO-XX --title "Eval"     # Agentless eval
bash scripts/task-manager.sh list|get|slots|reopen                    # State ops
```

**Roles:** developer, reviewer, architect, guardian-tuner, debugger
**Timeouts:** guardian_eval: 60m | code_task: 30m | analysis: 20m | reviewer: 15m | default: 25m

## Agent Knowledge Base
- `knowledge/guardian-agents-api.map.md` — codemap (2K tokens replaces 8K exploration)
- `knowledge/eval-patterns.md`, `auth-patterns.md`, `common-errors.md`
- Regenerate: `bash scripts/generate-codemap.sh /path/to/repo > knowledge/repo.map.md`

## Eval Reliability
- Preflight validation before evals (auth, config, GCP project)
- Long runs (>30 min): use service account JSON, not OAuth
- Errors: permanent (skip) vs transient (retry 3x) vs fatal (abort)
- Max tokens = permanent error (skip, don't retry)

## Slack
- `allowFrom` = inbound only. Use `conversations.open` for DM channel IDs.
- Check `conversations.history` before resending to avoid spam.

## VMs (all inactive)
- Billy VM (`89.167.64.183`) — STOPPED
- Son of Anton VM (`89.167.23.2`) — Uses ClawdBot, not OpenClaw

## Behavioral Lessons (2026-03-14 infer)
- **NEVER ask Caio to choose or for permission.** 3 violations caught Mar 12-13. Just do it.
- **Be thorough on first check.** Caio had to say "check everything again" — wasted his time.
- **Don't present options.** Pick the best, execute, report what you did.
