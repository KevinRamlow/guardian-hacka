# Eval Patterns — Configuration and Pitfalls

## Running Evals

```bash
cd ~/.openclaw/workspace/guardian-agents-api-real
source ~/.openclaw/workspace/.env.guardian-eval   # MUST do first
python -m evals.run_eval \
  --config evals/content_moderation/eval.yaml \
  --dataset evals/content_moderation/guidelines_combined_dataset.jsonl \
  --workers 4 \
  --limit 10
```

## CLI Arguments

| Flag | Required | Default | Notes |
|------|----------|---------|-------|
| `--config` / `-c` | Yes | — | Path to eval.yaml |
| `--dataset` / `-d` | No | from yaml | Override dataset path |
| `--workers` / `-w` | No | 4 | Max 10 on Mac |
| `--limit` / `-l` | No | all | Limit test cases |
| `--resume` / `-r` | No | false | Skip completed test_idx from progress.jsonl |

## Config Format (eval.yaml)

```yaml
runner: content_moderation          # maps to service in wire.py
runner_method: moderate             # method to call on service
input_model: ContentModerationInput # pydantic model for input
dataset: ./general_guidelines_sample_dataset.jsonl
output_fields: [guideline, answer, time, justification, reasoning, metadata]
metrics:
  per_field:
    answer: [{ type: "exact" }]
  aggregate:
    strategy: "weighted_mean"
    weights: { answer: 1.0 }
```

## Dataset Format (.jsonl)

One JSON per line with `inputs` (content, context, guidelines) and `expected` (answer, guideline, etc).

## Output Structure

```
evals/.runs/content_moderation/run_YYYYMMDD_HHMMSS/
  predictions.json    — full predictions with expected vs actual
  metrics.json        — aggregated accuracy metrics
  progress.jsonl      — incremental results (one per line, for resume)
  progress_meta.json  — { completed, total, errors }
  partial_results.json — intermediate results (if interrupted)
```

## Available Datasets

- `guidelines_combined_dataset.jsonl` — all guideline types combined
- `general_guidelines_dataset.jsonl` — general guidelines only
- `general_guidelines_sample_dataset.jsonl` — small sample for quick tests
- `brand_safety_dataset.jsonl` — brand safety checks
- `captions_guidelines_dataset.jsonl` — caption compliance
- `video_duration_dataset.jsonl` — duration constraints
- `time_constraint_dataset.jsonl` — time-related guidelines

## Common Pitfalls

- **"transient: Agent execution failed unexpectedly"** = usually auth issue, not code bug
- **No `--resume` native support for new runs** — resume only works within same run directory
- **Workers > 10 on Mac** causes resource exhaustion; keep at 4-8
- **Forgot to source .env.guardian-eval** = most common eval failure cause
- **MAX_TOKENS** errors on long content = skip that item, it continues
