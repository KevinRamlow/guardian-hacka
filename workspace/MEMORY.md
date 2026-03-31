# MEMORY.md — Sentinel Long-Term Knowledge

## Guardian System (as of 2026-03-17)

### Architecture
- 2-phase content moderation:
  - Phase 1: Visual + audio analysis WITH full video context
  - Phase 2: Text-only analysis (guidelines, captions)
- Severity scale: 1-2 rejected, 3 tolerated (CRITICAL boundary), 4-5 approved
- Brand safety inverted logic: `answer: false` = DOES violate (NOT safe)

### Baseline Metrics
- Combined dataset (121 cases): ~79% accuracy (real measured)
- Historical: Agentic model 79.3% (up from 73.6%)
- Per-classification improvements: CTA +15.4pp, General +5.3pp

### Known Problems
- CTA guidelines misclassified as GENERAL instead of TIME_CONSTRAINTS
- Color-of-clothing guidelines — agent too tolerant
- Semantic paraphrase — hard to detect exact wording match
- Brand safety: `answer: false` = DOES violate — inverted logic trap
- Small datasets (<25 samples) are misleading — 1 flip = 4-5pp swing

### Eval Infrastructure
- Repo: `guardian-agents-api-real/` (cloned to workspace)
- Datasets:
  - Full: `evals/content_moderation/all/human_evals_combined_dataset.jsonl` (650 cases)
  - Combined: `evals/content_moderation/all/guidelines_combined_dataset.jsonl` (121 cases)
  - Per-classification: `general/`, `time_constraints/`, `captions/`, `brand_safety/`, `video_duration/`
- Performance: ~38s/case with 15 workers, 45-60min for 650 cases
- Results: `evals/.runs/content_moderation/run_YYYYMMDD_HHMMSS/`
- Output files: predictions.json, metrics.json, progress.jsonl, progress_meta.json

### GCP Config
- Production: `brandlovers-prod` (Vertex AI for inference — evals MUST use this)
- Homolog: `brandlovrs-homolog` (eval datasets)
- Cluster: `bl-cluster` in `us-east1`
- CRITICAL: `GOOGLE_GENAI_USE_VERTEXAI=1` required, SA credentials must be decoded JSON (not base64)
- CRITICAL: `AGENTS_RETRY_MAX_ATTEMPTS=3` is the sweet spot

### Task Management
- Single source of truth: `state.json`
- State machine: todo → agent_running → done/failed/blocked/eval_running → callback_pending → agent_running → ...
- 4 scripts + HEARTBEAT.md architecture
- dispatcher.sh is THE ONLY way to spawn agents

### Few-Shot Database
- Location: `~/.openclaw/tasks/few-shot.db`
- Engine: sqlite-vec (vector similarity search)
- Embeddings: Gemini (gemini-embedding-001)
- Stores: eval cases with classification, guideline text, answers, agreement status, error type
- Query: `bash scripts/few-shot-db.sh query --classification <type> --type success/failure --limit N`

### Error Taxonomy
- **False Positive (FP):** Guardian rejected, human approved → Guardian too strict
- **False Negative (FN):** Guardian approved, human rejected → Guardian too lenient
- **Guideline Ambiguity:** Guideline text is vague/interpretable both ways
- **Media Edge Case:** Visual/audio content hard to parse correctly
- **Prompt Interpretation Error:** Guardian misunderstood what the guideline asks
