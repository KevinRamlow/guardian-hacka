# Few-Shot Mining Skill

## Purpose
Retrieve relevant examples from the sqlite-vec database for prompt injection.

## Database Location
`~/.openclaw/tasks/few-shot.db`

## Commands

### Initialize
```bash
bash scripts/few-shot-db.sh init
```

### Ingest eval results
```bash
bash scripts/few-shot-db.sh ingest --run-dir /path/to/run_YYYYMMDD_HHMMSS
```

### Query examples
```bash
# By classification + outcome
bash scripts/few-shot-db.sh query --classification brand_safety --type success --limit 5
bash scripts/few-shot-db.sh query --classification brand_safety --type failure --limit 5

# By error type
bash scripts/few-shot-db.sh query --error-type false_positive --limit 10

# Semantic search
bash scripts/few-shot-db.sh query --text "informal language brand safety" --limit 10

# Combined filters
bash scripts/few-shot-db.sh query --classification general --type failure --limit 5
```

### Stats
```bash
bash scripts/few-shot-db.sh stats
```

## Usage Pattern for Developers

1. **Before modifying a prompt**, query for examples:
   ```bash
   SUCCESS=$(bash scripts/few-shot-db.sh query --classification <type> --type success --limit 5)
   FAILURES=$(bash scripts/few-shot-db.sh query --classification <type> --type failure --limit 5)
   ```

2. **Format as few-shot examples** in the prompt (see error-forensics/SKILL.md for XML format)

3. **After eval completes**, ingest new results:
   ```bash
   bash scripts/few-shot-db.sh ingest --run-dir <latest_run_dir>
   ```

## Schema

| Column | Type | Description |
|--------|------|-------------|
| classification | TEXT | Guideline classification (general, brand_safety, etc.) |
| guideline_text | TEXT | Full guideline text |
| media_description | TEXT | Description of the media content |
| guardian_answer | TEXT | What Guardian decided |
| human_answer | TEXT | What the human decided |
| agreed | INTEGER | 1=agreed, 0=disagreed |
| error_type | TEXT | false_positive, false_negative, interpretation_error |
| reasoning | TEXT | Guardian's reasoning |

## Dependencies
- Python 3.x
- sqlite-vec (`pip install sqlite-vec`)
- google-generativeai (`pip install google-generativeai`) — for embeddings
- GEMINI_API_KEY environment variable — for embedding generation
