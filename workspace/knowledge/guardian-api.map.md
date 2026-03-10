# guardian-api — Compact Codemap

This is the FastAPI wrapper around guardian-agents-api. Key entry points:

## API Structure

- `main.py` — uvicorn entry point, calls `src/app.py`
- `src/app.py` — FastAPI app with routes for content moderation and guideline critique
- `src/wire.py` — DI container: `wire()` returns Dependencies dataclass
- `src/health.py` — `/health` endpoint

## Key Services (via wire.py)

| Service | Method | Purpose |
|---------|--------|---------|
| ContentModerationService | `.moderate()` | Full 2-phase video moderation |
| CritiqueGuidelinesService | `.critique()` | Guideline quality feedback |
| AgentService | `.run()` | Base agent execution via ADK Runner |

## Dependencies Initialized by wire()

- GCP credentials (from base64 env var or ADC)
- BigQuery client (for Memory/tolerance patterns)
- Gemini LLM (Phase 1 + default Phase 2)
- Optional LiteLLM (Phase 2 alternative model)
- Langfuse client (telemetry, optional)
- OpenInference instrumentation (tracing, optional)
- TextEmbeddingModel (semantic CTA comparison)

## Deployment

- Dockerfile present; deployed to GCP (Cloud Run implied)
- `terraform.tfvars` for infra config
- `Makefile` for common commands
- `pyproject.toml` + `uv.lock` for dependency management (uses uv)
