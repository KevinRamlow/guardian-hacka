# GUA-1100: Archetype Standardization — Run Results

**Date:** 2026-03-05  
**Branch:** `experiment/gua-1100-archetype-standardization`  
**Runs used:** 3 of 5 allowed  

## What Changed

### 1. New shared module: `archetype_utils.py`
- **Location:** `pipelines/memory/content_moderation/archetype_utils.py`
- Contains:
  - `ARCHETYPE_SCHEMA` — unified JSON schema with `archetype`, `matched_taxonomy_id`, `is_new_archetype`
  - `load_taxonomy()` — loads the 34-entry master taxonomy from `archetype_taxonomy.json`
  - `generate_archetype_with_taxonomy()` — unified LLM-based archetype generation with taxonomy mapping
  - `_parse_json_response()` — shared JSON response parser

### 2. Modified `build_tolerance_patterns.py`
- Removed inline `ARCHETYPE_SCHEMA` and `generate_archetype()` function
- Now imports from `archetype_utils`
- `generate_archetype()` returns a dict with taxonomy mapping fields
- `aggregate_pattern_from_cluster()` unpacks archetype result and stores taxonomy fields
- Added `matched_taxonomy_id` and `is_new_archetype` to:
  - BigQuery table schema (via `ensure_table_exists`)
  - Temp table schema
  - Row construction in `insert_patterns_into_bigquery`
  - MERGE INSERT/UPDATE queries
- Added deduplication before MERGE to handle identical archetype+category+subcategory keys
- Fixed `ensure_table_exists` schema migration to detect new fields

### 3. Modified `build_error_patterns.py`
- Removed inline `generate_guideline_archetype()` with its poor-quality prompt (no accents, no JSON schema)
- Now imports from `archetype_utils` for taxonomy-aware generation
- Same quality prompt as tolerance patterns (proper PT-BR, professional tone, INSTRUÇÕES CRÍTICAS)
- Returns dict with taxonomy mapping, unpacked in `aggregate_patterns_from_guideline_cluster()`
- Pattern dicts now include `matched_taxonomy_id` and `is_new_archetype`
- **Note:** Error patterns BigQuery schema/insert not yet updated (only tolerance was tested)

## Test Results

### Run 1 (no BQ schema fields for taxonomy)
- **Status:** ✅ Success (patterns generated but taxonomy fields not persisted)
- 996 guidelines → 38 action groups → 54 clusters → 54 patterns → 29 validated
- Duration: ~270s
- Archetype quality: excellent, clean PT-BR

### Run 2 (schema migration + MERGE update)
- **Status:** ❌ MERGE duplicate key error
- `ensure_table_exists` successfully added new columns
- But MERGE failed: multiple source rows matched same target row

### Run 3 (with deduplication)
- **Status:** ✅ Full success
- 996 guidelines → 54 clusters → 26 patterns generated → 25 after dedup → 25 validated
- Duration: ~264s
- **Taxonomy mapping: 100% (25/25 mapped to existing taxonomy entries, 0 new)**

## Archetype Quality Assessment

### Taxonomy Mapping Distribution (25 patterns)
| Taxonomy ID | Count | Sample |
|---|---|---|
| VERBAL_PHRASE_PRECISION | 3 | "Garantir a precisão da mensagem chave {frase}..." |
| VERBAL_TERMINOLOGY_PROTECTION | 2 | "Assegurar a voz e terminologia proprietária de {marca}..." |
| VERBAL_CTA_DIRECTION | 3 | "Garantir CTAs verbais claros que direcionem..." |
| VERBAL_IDENTITY_PROTECTION | 3 | "Garantir a identificação de {marca} como {termo_correto}..." |
| VERBAL_BENEFIT_COMMUNICATION | 4 | "Reforçar a mensagem chave sobre o lançamento..." |
| CONTENT_MANDATORY_PHRASES | 2 | "Garantir a menção verbal exata das {frases}..." |
| Others (1 each) | 8 | Various |

### Quality Highlights
- ✅ All archetypes in proper PT-BR with accents (fixed from error patterns' "Voce e" → "Você é")
- ✅ Professional Brand Guardian tone consistently applied
- ✅ Proper placeholder usage: {marca}, {frase}, {objeto}, {canal}, {termo_correto}
- ✅ Concise (15-20 word range maintained)
- ✅ 100% taxonomy match rate suggests the 34-entry taxonomy covers the space well
- ✅ No hallucinated taxonomy IDs (validation catches invalid IDs)

### Concerns / Next Steps
1. **Error patterns BQ schema:** `build_error_patterns.py` code is updated but BigQuery schema for `error_patterns` table doesn't have the new fields yet — need same treatment as tolerance
2. **0 new archetypes:** Could indicate the taxonomy is comprehensive OR the LLM is being overly eager to match. Worth monitoring with more data.
3. **Deduplication:** 1 duplicate in 26 patterns (3.8%) — taxonomy mapping increases collision probability when different clusters map to same archetype
4. **Error patterns untested:** Only tolerance pipeline was run. Error patterns need a separate test run.

## Commits
1. `2d35906` — feat: add shared archetype_utils with taxonomy-aware generation
2. `1cf2720` — feat: add taxonomy fields to BigQuery schema and MERGE queries
3. `db472c5` — fix: fix schema migration and add MERGE deduplication
