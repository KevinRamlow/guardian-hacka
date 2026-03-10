# guardian-agents-api — Compact Codemap

## File Tree (src/)

```
src/
  app.py                          — FastAPI application entry point
  wire.py                         — Centralized dependency wiring (DI container)
  health.py                       — Health check endpoint
  agents/
    content_moderation/
      base_analysis/
        visual_description_agent.py   — Phase 1: describes video frames visually
        audio_transcription_agent.py  — Phase 1: transcribes audio with timestamps
      general/
        concept_extraction_agent.py   — Phase 2: extracts concepts from text descriptions
        severity_analysis_agent.py    — Phase 2: scores guideline severity (1-5)
      judge/
        borderline_judge_agent.py     — Phase 2: reviews borderline severity 2-4 decisions
        correction_agent.py           — Corrects misclassifications
      specialized/
        brand_safety_agent.py         — Phase 2: brand safety guideline checks
        captions_verification_agent.py — Phase 2: caption/subtitle compliance
        video_duration_agent.py       — Phase 2: video length constraint checks
    critique_guidelines/
      orchestrator_agent.py           — Routes guideline critique workflow
      adjust_content_agent.py         — Adjusts content based on feedback
      reformulate_requirement_agent.py — Rewrites vague requirements
  configs/
    settings.py                    — Pydantic settings (env vars, GCP config)
    logging.py                     — Structured logging setup
  constants/
    brand_safety.py                — Brand safety guideline detail mappings
  context/
    request_context.py             — Per-request context (trace IDs, metadata)
  data/
    memory.py                      — BigQuery-backed memory (tolerance patterns, embeddings)
  errors/
    exceptions.py                  — Custom exception types (ErrorType enum)
    handler.py                     — Global error handler
  middleware/
    logging_context.py             — Request logging middleware
  models/
    content_moderation.py          — Pydantic models (inputs/outputs/guidelines)
    contest_judge.py               — Contest judging models
    guidelines_critiques.py        — Critique workflow models
  services/
    agent_service.py               — Base service for running ADK agents
    content_moderation_service.py  — 2-phase orchestrator (main service)
    contest_judge_service.py       — Contest judging service
    critique_guidelines_service.py — Guideline critique service
  types/
    model_config.py                — ModelConfig dataclass (temp, tokens, logprobs)
  utils/
    template_loader.py             — Loads prompt templates
    xml_tool_call_recovery.py      — Recovers malformed XML tool calls
    before_tool_skip_summarization.py — Skips summarization before tool calls
```

## 2-Phase Moderation Flow

**Phase 1 — Base Analysis (multimodal, always Gemini):**
1. VisualDescriptionAgent analyzes video frames -> text description
2. AudioTranscriptionAgent transcribes audio -> timestamped transcript
3. Combined into BaseAnalysisOutput (text-only from here on)

**Phase 2 — Moderation (text-only, supports Gemini or LiteLLM):**
- Guidelines routed by ClassificationEnum type:
  - `general` -> ConceptExtractionAgent -> SeverityAnalysisAgent -> BorderlineJudgeAgent (if severity 2-4)
  - `captions` -> CaptionsVerificationAgent
  - `brand_safety` -> BrandSafetyAgent
  - `video_duration` -> VideoDurationAgent
- All Phase 2 agents work on text descriptions only (no video re-processing)

## Eval System

- **Entry:** `python -m evals.run_eval --config <yaml> --dataset <jsonl> --workers N`
- **Config (eval.yaml):** specifies runner name, runner_method, input_model, output_fields, metrics
- **Dataset (.jsonl):** one JSON object per line with inputs + expected outputs
- **Output:** `evals/.runs/<runner>/run_YYYYMMDD_HHMMSS/` containing predictions.json, metrics.json, progress.jsonl, progress_meta.json
- **Wiring:** uses `wire(enable_langfuse=False)` for eval runs
- **Resume:** `--resume` flag loads progress.jsonl and skips completed test_idx

## Environment Requirements

- `GOOGLE_CLOUD_PROJECT` — GCP project (set via `.env.guardian-eval`)
- `GOOGLE_GENAI_USE_VERTEXAI=1` — enables Vertex AI
- `.env.guardian-eval` — sources all required env vars for eval runs
- `.gcp-credentials.json` — service account key (if not using ADC)

## Common Pitfalls

- **Auth:** GCP RAPT requires re-auth; `gcloud auth print-access-token` to verify
- **MAX_TOKENS:** severity_analysis can hit token limits on long content -> skip item
- **Workers:** max 10 on Mac (async semaphore); default 4
- **Phase 2 model:** configurable via `settings.phase2_model`; non-Gemini uses LiteLLM
