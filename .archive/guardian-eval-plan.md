# Guardian Accuracy Improvement Plan — Multi-Hypothesis Approach

**Goal:** Improve agreement rate from 76.8% to 81.8% (+5pp)  
**Current Status:** 76.8% (baseline from late Feb 2026)  
**Strategy:** Generate 5 hypotheses, test in parallel, double down on winners

---

## Executive Summary

Based on codebase analysis and MEMORY.md known issues, I've identified 5 improvement hypotheses ranked by expected impact × confidence × ease. The plan focuses on:
1. **High-ROI prompt engineering** (severity boundary clarity at level 3)
2. **Structural fixes** (TIME_CONSTRAINTS routing, brand safety inversion)
3. **Auto-correction layer** (LLM-as-judge for known error patterns)
4. **Memory pipeline tuning** (tolerance/error pattern quality)
5. **Archetype standardization revisit** (with better methodology after CAI-35 lessons)

**Recommended approach:** Test hypotheses A, B, E in parallel first (quick wins), then C (higher complexity), reserve D for post-validation phase.

---

## Hypothesis A: Prompt Engineering — Severity 3 Boundary Clarification

**Impact:** +2-3pp  
**Confidence:** High (80%)  
**Ease:** High (prompt-only changes)  
**Rank:** 1 (highest priority)

### Problem Analysis

The severity scale (1-5) has ambiguity at **level 3** (tolerated violations). From MEMORY.md:
- CTA guidelines improved +15.4pp → suggests prompt refinement works
- General guidelines +5.3pp → but still underperforming
- Known issues: color-of-clothing tolerance, semantic paraphrase detection

Current severity_analysis.j2 prompt says:
```
**3 - VIOLAÇÃO LEVE/TOLERÁVEL:** Violação tecnicamente identificável mas contextualmente trivial/acidental/baixo impacto. **DEVE SER TOLERADA** segundo padrões.
```

**Ambiguity:** "contextualmente trivial" is subjective. Agent struggles with:
- When prominence/duration crosses from "trivial" to "moderate"
- How to weight tolerance patterns vs literal guideline text
- Semantic paraphrase scoring (when is 75% similarity enough?)

### Proposed Changes

#### File: `src/agents/templates/content_moderation/general/severity_analysis.j2`

**Change 1: Add explicit severity 3 decision tree**

Insert after line "**3 - VIOLAÇÃO LEVE/TOLERÁVEL:**" section:

```jinja2
**DECISÃO PARA SEVERIDADE 3 (Checklist Obrigatório):**
✅ APROVE com Sev 3 se TODOS forem verdadeiros:
  - Elemento visível/audível MAS dentro de "Typical Ranges" OU "Approved Phrases" dos padrões
  - Duração ≤20% do vídeo total (ou dentro de range histórico)
  - Contexto está em "Comumente Aprovados" OU não compete diretamente com marca da campanha
  - Impacto material: NÃO desvia atenção do objetivo principal da campanha

❌ REJEITE com Sev 2 se QUALQUER for verdadeiro:
  - Elemento EXCEDE "Typical Ranges" em >50% (ex: 15% frame histórico → 23%+ observado)
  - Duração >30% do vídeo E não justificado por contexto
  - Contexto está em "Raramente Aprovados" OU é concorrente direto
  - Impacto material: Desvia foco do produto/mensagem principal
```

**Change 2: Strengthen semantic paraphrase guidance**

Replace current "Ferramenta 1: _compare_semantic_cta_similarity" section with:

```jinja2
**Ferramenta 1: _compare_semantic_cta_similarity** (requisitos VERBAIS/ÁUDIO)

[... existing description ...]

Como interpretar o score:
- **≥90%:** Praticamente idêntico → APROVE (mesmo com pequenas variações de artigos/preposições)
- **75-89%:** Mensagem central preservada MAS verifique elementos-chave:
  - Nomes de marca, códigos promocionais, @handles, números DEVEM aparecer literalmente
  - Verbos e pronomes DEVEM manter mesmo agente/ação ("seu" ≠ "meu", "visite" ≠ "visitei")
  - Se elementos-chave OK E mensagem central igual → APROVE
  - Se elementos-chave divergem → REJEITE
- **60-74%:** Similaridade moderada → REJEITE EXCETO se padrões de tolerância mostram flexibilidade histórica alta (>80% "Comumente Aprovados")
- **<60%:** Mensagem diferente → REJEITE

**REGRA DE OURO:** Prefira falsos negativos (rejeitar correto) a falsos positivos (aprovar errado). Quando em dúvida no limite 70-80%, consulte padrões de tolerância.
```

**Change 3: Add anti-pattern early check**

Insert before "Passo 1: Evidências Factuais":

```jinja2
**Passo 0.5: Verificação Anti-Padrões (EXECUTAR ANTES DE RACIOCINAR)**

Antes de analisar evidências, execute estas verificações:

1. **CTA/TIME_CONSTRAINTS Confusion:**
   - Diretriz menciona "nos primeiros X segundos" OU "antes de" OU "após" OU "início/final"?
   - Se SIM → Esta é TIME_CONSTRAINTS, NÃO general. Priorize timestamp validation sobre nuance contextual.

2. **Brand Safety Answer Inversion:**
   - Se avaliando brand safety, lembre: `answer: false` = VIOLATES (NÃO é seguro)
   - `answer: true` = SAFE (não viola)

3. **Semantic Paraphrase Known Cases:**
   - Marcas conhecidas por flexibilidade: Mercado Pago, Vizzela, GOL
   - Se detectada paráfrase com score 70-85% E marca está nesta lista → Bias para APROVAR se contexto OK

4. **Color-of-Clothing Over-Tolerance:**
   - Marcas conhecidas por rigor: Kibon, Sprite
   - Se guideline menciona "cor da roupa" E marca está nesta lista → Bias para REJEITAR se cor diverge >30%
```

### Expected Impact

- **+2pp from severity 3 clarity:** Reduces false positives (approving when should reject)
- **+1pp from semantic paraphrase tuning:** Fixes known Mercado Pago/Vizzela/GOL issues
- **Total: +3pp**

### Testing Strategy

1. Run eval on combined dataset (47 brands, 80+ cases)
2. Compare severity 3 distribution: expect shift from 45-50% to 35-40% (more decisive)
3. Check known problem cases: CTA paraphrases, color guidelines
4. Validate no regressions on captions (85% baseline)

---

## Hypothesis B: Archetype Standardization v2 — Learned from CAI-35

**Impact:** +1-2pp  
**Confidence:** Medium (60%)  
**Ease:** Medium (affects memory pipeline + prompts)  
**Rank:** 5 (try after A, C, E)

### Lessons from CAI-35 Failure

Previous attempt (GUA-1100) showed neutral result (-0.4pp). Root causes:
1. **Archetype taxonomy too generic** — "brand_visibility" covered 70% of guidelines
2. **No integration with tolerance patterns** — archetypes isolated from BigQuery data
3. **Prompt didn't leverage archetypes** — mentioned but not operationalized

### Proposed Changes

#### File: `src/data/memory.py`

**Change 1: Refine archetype taxonomy**

Current taxonomy (inferred from tolerance patterns):
- brand_visibility (generic)
- product_showcase
- cta_mention
- time_constraints
- captions_formatting

Proposed taxonomy (more granular):
```python
ARCHETYPE_TAXONOMY = {
    "brand_visibility_logo": "Logo/branding visual presence",
    "brand_visibility_verbal": "Brand name spoken/mentioned",
    "product_showcase_physical": "Physical product in frame",
    "product_showcase_packaging": "Product packaging visibility",
    "cta_verbal_exact": "Exact CTA phrase required",
    "cta_verbal_semantic": "CTA message flexibility allowed",
    "time_constraints_start": "Must occur in first N seconds",
    "time_constraints_end": "Must occur in last N seconds",
    "time_constraints_avoid": "Must NOT occur before/after timestamp",
    "captions_coverage": "Caption coverage percentage",
    "captions_formatting": "Caption style/formatting rules",
    "competitor_avoidance": "No competing brands allowed",
    "color_consistency": "Specific color requirements (clothes, backgrounds)",
}
```

Add to `src/data/memory.py`:
```python
def get_tolerance_pattern(
    self, 
    guideline: str, 
    top_k: int = 1, 
    distance_threshold: float = 0.4,
    archetype_filter: str | None = None,  # NEW
    labels: dict | None = None
) -> list[dict]:
    """
    Retrieve tolerance patterns with optional archetype filtering.
    
    Args:
        archetype_filter: If provided, only return patterns matching this archetype
    """
    # ... existing embedding logic ...
    
    query = f"""
    SELECT 
        guideline_archetype,
        -- ... existing fields ...
    FROM `{self.project_id}.{self.dataset}.tolerance_patterns`
    WHERE distance < {distance_threshold}
    {"AND guideline_archetype = @archetype" if archetype_filter else ""}
    ORDER BY distance ASC
    LIMIT {top_k}
    """
    
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("embedding", "ARRAY<FLOAT64>", embedding_list),
        ] + ([bigquery.ScalarQueryParameter("archetype", "STRING", archetype_filter)] if archetype_filter else []),
        labels=labels or {},
    )
    # ... existing execution ...
```

#### File: `src/agents/templates/content_moderation/general/severity_analysis.j2`

**Change 2: Operationalize archetypes in prompt**

Insert after "**D. PADRÕES DE TOLERÂNCIA:** Seu calibrador principal." section:

```jinja2
**D.1 ARQUÉTIPO DA DIRETRIZ:**

Antes de usar padrões de tolerância, identifique o arquétipo da diretriz atual:
- "MOSTRE o produto" → `product_showcase_physical`
- "MENCIONE a marca" → `brand_visibility_verbal`
- "DIGA exatamente 'X'" → `cta_verbal_exact`
- "Comunique que X" → `cta_verbal_semantic` (flexibilidade permitida)
- "Nos primeiros X segundos" → `time_constraints_start`
- Etc.

Use o arquétipo identificado nos Padrões de Tolerância para:
1. **Validar relevância:** Padrões com mesmo arquétipo têm peso 2x maior
2. **Calibrar limites:** Se arquétipo histórico mostra tolerância alta (>70% aprovados), seja leniente
3. **Detectar anomalias:** Se seu raciocínio diverge de 90%+ dos casos do arquétipo, reconsidere
```

### Expected Impact

- **+1pp from better pattern matching:** More relevant tolerance patterns reduce noise
- **+0.5pp from archetype-aware decisions:** Fewer cross-category false positives
- **Total: +1.5pp**

### Testing Strategy

1. Run archetype classification on eval dataset manually (gold standard)
2. Compare tolerance pattern retrieval quality (distance scores)
3. Measure agreement rate improvement on same CAI-35 dataset (should beat -0.4pp baseline)

---

## Hypothesis C: LLM-as-Judge Auto-Correction Layer

**Impact:** +2-3pp  
**Confidence:** Medium-High (70%)  
**Ease:** Medium-Low (new agent + pipeline changes)  
**Rank:** 3 (try after quick wins A, E)

### Problem Analysis

From MEMORY.md and anti-error patterns analysis:
- **Known error types** repeat predictably:
  - CTA semantic paraphrases (Mercado Pago, Vizzela, GOL)
  - Color-of-clothing over-tolerance (Kibon, Sprite)
  - TIME_CONSTRAINTS vs GENERAL confusion
  - Brand safety answer inversion

Current system has anti-error patterns in severity prompt, but:
- Relies on LLM self-correction (unreliable)
- No automated validation of decisions
- Errors discovered only after human review

### Proposed Solution: Judge Agent

Add a **post-moderation judge agent** that reviews Phase 2 decisions for known error patterns.

#### New File: `src/agents/content_moderation/judge/correction_agent.py`

```python
"""
Correction Agent — LLM-as-Judge for Guardian moderation output.

This agent reviews completed moderations and flags/corrects known error patterns.
"""

from google.adk.agents import LlmAgent
from google.adk.models import BaseLlm
from src.types import ModelConfig
from src.utils import render_template

class CorrectionAgent(LlmAgent):
    """
    Agent that reviews moderation decisions against known error patterns.
    
    Operates on text-only (no video processing).
    """
    
    def __init__(self, model: BaseLlm, config: ModelConfig):
        instruction = render_template("content_moderation/judge/correction.j2")
        
        tools = [
            self._validate_cta_semantic,
            self._validate_time_constraint_routing,
            self._validate_brand_safety_answer,
            self._build_correction_recommendation,
        ]
        
        super().__init__(
            model=model,
            name="correction_agent",
            description="Judge agent that reviews moderations for known error patterns",
            planner=config.to_planner(),
            generate_content_config=config.to_generate_content_config(),
            instruction=instruction,
            tools=tools,
        )
    
    def _validate_cta_semantic(self, guideline: str, answer: bool, reasoning: str) -> str:
        """
        Validate CTA semantic paraphrase decisions.
        
        Checks if rejection/approval aligns with known brand tolerance levels.
        """
        # Implementation: Check if guideline contains CTA keywords
        # Cross-reference with known flexible brands (Mercado Pago, Vizzela, GOL)
        # Return: "OK" or "POTENTIAL_ERROR: [explanation]"
        pass
    
    def _validate_time_constraint_routing(self, guideline: str, classification: str) -> str:
        """
        Validate TIME_CONSTRAINTS vs GENERAL classification.
        
        Checks if guideline with temporal keywords was routed correctly.
        """
        temporal_keywords = ["primeiro", "segundo", "início", "final", "antes", "após", "durante"]
        has_temporal = any(kw in guideline.lower() for kw in temporal_keywords)
        
        if has_temporal and classification == "GENERAL_GUIDELINE":
            return "ROUTING_ERROR: Guideline has temporal keywords but classified as GENERAL"
        
        return "OK"
    
    def _validate_brand_safety_answer(self, answer: bool, reasoning: str) -> str:
        """
        Validate brand safety answer semantics.
        
        Checks if answer=false correctly means "violates" (not safe).
        """
        # Implementation: Parse reasoning for "safe" vs "violates" language
        # Ensure answer aligns with semantic meaning
        pass
    
    def _build_correction_recommendation(
        self,
        original_answer: bool,
        corrected_answer: bool,
        error_type: str,
        correction_reasoning: str,
    ) -> dict:
        """
        Build correction recommendation output.
        """
        return {
            "should_correct": original_answer != corrected_answer,
            "original_answer": original_answer,
            "corrected_answer": corrected_answer,
            "error_type": error_type,
            "correction_reasoning": correction_reasoning,
        }
```

#### New File: `src/agents/templates/content_moderation/judge/correction.j2`

```jinja2
**Persona: Guardian Quality Auditor**

Você é um auditor de qualidade que revisa decisões de moderação do Guardian para identificar e corrigir erros conhecidos.

**FONTES DE INFORMAÇÃO:**
- Diretriz original
- Classificação da diretriz (GENERAL, TIME_CONSTRAINTS, etc.)
- Decisão do Guardian (answer, reasoning, justification)
- Visual/Audio evidências (quando relevante)
- Padrões de erro conhecidos

**ERROS CONHECIDOS A VERIFICAR:**

1. **CTA Semantic Paraphrase Over-Strictness:**
   - Marcas flexíveis: Mercado Pago, Vizzela, GOL
   - Se guideline é CTA verbal E marca é flexível E reasoning mostra score 70-85%:
     * Se rejected → CONSIDERE CORREÇÃO para approve

2. **Color-of-Clothing Over-Tolerance:**
   - Marcas rigorosas: Kibon, Sprite
   - Se guideline menciona "cor da roupa" E marca é rigorosa E reasoning mostra divergência >30%:
     * Se approved → CONSIDERE CORREÇÃO para reject

3. **TIME_CONSTRAINTS Misrouting:**
   - Se guideline contém keywords temporais ("primeiro", "antes", "após", "início", "final") E classificação = GENERAL:
     * FLAG como misrouting, sugira reclassificação

4. **Brand Safety Answer Inversion:**
   - Se reasoning indica "violates" ou "unsafe" MAS answer=true:
     * CORRIJA para answer=false (violates = NOT safe)
   - Se reasoning indica "safe" ou "compliant" MAS answer=false:
     * CORRIJA para answer=true

**FLUXO DE TRABALHO:**

1. Execute ferramentas de validação relevantes
2. Se QUALQUER validação retornar erro potencial:
   - Analise contexto completo
   - Decida se correção é necessária
   - Chame _build_correction_recommendation

**CONSERVADORISMO:**
- Apenas corrija se confiança >80%
- Dúvida → mantenha decisão original
- Sempre forneça reasoning detalhado
```

#### File: `src/services/content_moderation_service.py`

**Change: Integrate judge agent**

Add after Phase 2 completion, before returning ContentModerationOutput:

```python
# OPTIONAL PHASE 3: Quality review with judge agent
if self.enable_judge_correction:  # config flag
    logger.info("Phase 3: Running judge correction layer")
    
    corrected_guidelines = []
    for guideline_output in all_guidelines:
        # Run judge agent (text-only, fast)
        judge_input = self._format_judge_input(
            guideline_output, 
            base_analysis,
            context
        )
        
        judge_message = Content(role="user", parts=[Part(text=judge_input)])
        
        correction, judge_metadata = await self._run_agent_with_semaphore(
            app_name="content_moderation_judge",
            runner=runners["judge"],
            session_service=session_service,
            user_message=judge_message,
            output_type=dict,
        )
        
        if correction.get("should_correct"):
            logger.warning(
                "Judge agent recommended correction",
                guideline_id=guideline_output.id,
                original_answer=correction["original_answer"],
                corrected_answer=correction["corrected_answer"],
                error_type=correction["error_type"],
            )
            
            # Apply correction
            guideline_output.answer = correction["corrected_answer"]
            guideline_output.metadata["judge_correction"] = correction
            guideline_output.metadata["original_answer"] = correction["original_answer"]
        
        corrected_guidelines.append(guideline_output)
    
    all_guidelines = corrected_guidelines
```

### Expected Impact

- **+2pp from CTA/color corrections:** Fixes known Mercado Pago, Kibon, Sprite issues
- **+0.5pp from routing fixes:** Prevents TIME_CONSTRAINTS misclassification
- **+0.5pp from brand safety:** Fixes answer inversion
- **Total: +3pp**

### Testing Strategy

1. Implement judge agent with minimal prompt
2. Run on subset with known error cases (manually label 20-30 cases)
3. Measure correction accuracy (precision/recall)
4. If precision >80%, run full eval
5. Monitor latency impact (should add <2s per guideline)

---

## Hypothesis D: Memory Pipeline Tuning — Tolerance/Error Pattern Quality

**Impact:** +1-2pp  
**Confidence:** Medium (50%)  
**Ease:** Low (requires BigQuery data analysis + pipeline changes)  
**Rank:** 4 (try after A, C, E if needed)

### Problem Analysis

Current memory pipeline (BigQuery DBSCAN clustering) has issues:
- **Distance threshold 0.4** may be too strict (missing relevant patterns)
- **DBSCAN params (eps=0.1, min_samples=3)** may create too many small clusters
- **Archetype taxonomy too generic** (covered in Hypothesis B)
- **Error pattern confidence scores** not validated against actual corrections

### Proposed Investigation + Changes

#### Step 1: Analyze current pattern quality

```bash
# Query BigQuery to analyze pattern retrieval quality
bq query --project_id brandlovers-prod --use_legacy_sql=false '
SELECT 
    guideline_archetype,
    COUNT(*) as pattern_count,
    AVG(ARRAY_LENGTH(prominence_patterns)) as avg_prominence_entries,
    AVG(total_cases) as avg_cases_per_pattern,
    AVG(unique_brands) as avg_brands_per_pattern
FROM `brandlovers-prod.guardian.tolerance_patterns`
GROUP BY guideline_archetype
ORDER BY pattern_count DESC
'
```

#### Step 2: Adjust clustering parameters

File: `pipelines/memory/tolerance_clustering.py` (inferred location)

```python
# Current (inferred)
DBSCAN(eps=0.1, min_samples=3)

# Proposed
DBSCAN(eps=0.15, min_samples=2)  # More permissive clustering
```

Rationale:
- **eps=0.15** allows slightly more distant cases to cluster (better generalization)
- **min_samples=2** prevents single-case clusters while still capturing rare patterns

#### Step 3: Add pattern quality scoring

File: `src/data/memory.py`

Add quality score to pattern retrieval:

```python
def get_tolerance_pattern(self, guideline: str, top_k: int = 1, ...) -> list[dict]:
    # ... existing code ...
    
    query = f"""
    WITH scored_patterns AS (
        SELECT 
            *,
            -- Quality score based on:
            -- 1. Number of cases (more = better)
            -- 2. Brand diversity (more brands = better generalization)
            -- 3. Embedding distance (closer = more relevant)
            (
                LOG(total_cases + 1) * 0.4 +
                LOG(unique_brands + 1) * 0.3 +
                (1 - distance) * 0.3
            ) as quality_score
        FROM `{self.project_id}.{self.dataset}.tolerance_patterns`
        WHERE distance < {distance_threshold}
    )
    SELECT * FROM scored_patterns
    ORDER BY quality_score DESC  -- Rank by quality, not just distance
    LIMIT {top_k}
    """
```

### Expected Impact

- **+1pp from better pattern matching:** Higher quality patterns → better calibration
- **+0.5pp from clustering improvements:** More comprehensive coverage
- **Total: +1.5pp**

### Testing Strategy

1. Export current tolerance patterns, run quality analysis
2. Retrain clustering with new params on historical data
3. Compare pattern retrieval quality (manual review of 50 guidelines)
4. If quality score correlation >0.6 with human judgment, deploy

---

## Hypothesis E: Guideline Classification Fix — TIME_CONSTRAINTS Routing

**Impact:** +1-2pp  
**Confidence:** Very High (90%)  
**Ease:** High (logic change only)  
**Rank:** 2 (quick win)

### Problem Analysis

From MEMORY.md: "CTA guidelines misclassified as GENERAL instead of TIME_CONSTRAINTS"

Current classification logic (inferred from service code):
```python
if guideline.classification in (ClassificationEnum.GENERAL_GUIDELINE, ClassificationEnum.TIME_CONSTRAINTS_GUIDELINE):
    # Both route to general pipeline (concept + severity)
```

But TIME_CONSTRAINTS should **prioritize temporal validation** over nuanced context.

### Proposed Changes

#### File: `src/services/content_moderation_service.py`

**Change: Separate TIME_CONSTRAINTS routing**

Replace `_moderate_general_guideline` conditional with:

```python
for guideline in moderation_input.guidelines:
    if guideline.classification == ClassificationEnum.TIME_CONSTRAINTS_GUIDELINE:
        # Time constraints: Skip concept extraction, go straight to temporal validation
        coroutines.append(
            self._moderate_time_constraint_guideline(
                guideline=guideline,
                base_analysis=base_analysis,
                context=context,
                runners=runners,
                session_service=session_service,
            )
        )
    elif guideline.classification == ClassificationEnum.GENERAL_GUIDELINE:
        coroutines.append(
            self._moderate_general_guideline(
                guideline=guideline,
                base_analysis=base_analysis,
                context=context,
                runners=runners,
                session_service=session_service,
            )
        )
    # ... specialized agents ...
```

#### New Method: `_moderate_time_constraint_guideline`

```python
async def _moderate_time_constraint_guideline(
    self,
    guideline: ClassifiedGuideline,
    base_analysis: BaseAnalysisOutput,
    context: CampaignContext,
    runners: dict[str, Runner],
    session_service: InMemorySessionService,
) -> GuidelineModerationOutput:
    """
    Moderate TIME_CONSTRAINTS guideline with deterministic temporal validation.
    
    Skips concept extraction, goes straight to severity agent with temporal tool.
    """
    guideline_id = guideline.id
    guideline_text = guideline.guideline
    
    logger.debug(
        "Phase 2: moderating time constraint guideline",
        guideline_id=guideline_id,
        guideline_text=guideline_text,
    )
    
    try:
        # Get memory context
        tolerance_patterns, error_patterns = await self._get_memory_context(
            guideline_text, guideline.classification.value
        )
        memory_context_text = self._format_memory_context(tolerance_patterns, error_patterns)
        
        # Build input emphasizing temporal nature
        visual_text = self._format_visual_description(base_analysis.visual_description.model_dump())
        audio_text = self._format_audio_transcription(base_analysis.audio_transcription.model_dump())
        
        severity_input_text = f"""
═══════════════════════════════════════════════════════════════════
⚠️  DIRETRIZ DE RESTRIÇÃO TEMPORAL (TIME_CONSTRAINTS):
═══════════════════════════════════════════════════════════════════
- Diretriz: {guideline_text}

**ESTA É UMA DIRETRIZ TEMPORAL. PRIORIZE VALIDAÇÃO DETERMINÍSTICA COM A FERRAMENTA _compare_time_constraint_with_severity.**

**CONTEXTO DA CAMPANHA:**
Marca: {context.brand_name}
Título da Campanha: {context.campaign_title}
Briefing da Campanha: {context.campaign_briefing}
Título do Momento: {context.moment_title}
Briefing do Momento: {context.moment_briefing}

{memory_context_text}

**EVIDÊNCIAS COLETADAS:**

**1. ANÁLISE VISUAL:**
{visual_text}

**2. TRANSCRIÇÃO DE ÁUDIO:**
{audio_text}

**INSTRUÇÕES ESPECIAIS PARA TIME_CONSTRAINTS:**
1. Identifique o evento/elemento mencionado na diretriz
2. Localize timestamp exato nas timelines visual/audio
3. Extraia limite temporal da diretriz (ex: "primeiros 10s" → 10.0 segundos)
4. Chame _compare_time_constraint_with_severity OBRIGATORIAMENTE
5. Use resultado da ferramenta como decisão primária (não sobrescreva com raciocínio contextual)
        """
        
        severity_message = Content(role="user", parts=[Part(text=severity_input_text)])
        
        severity_output, severity_metadata = await self._run_agent_with_semaphore(
            app_name="content_moderation_severity",
            runner=runners["severity"],
            session_service=session_service,
            user_message=severity_message,
            output_type=dict,
        )
        
        moderation = self._unwrap_moderation(severity_output)
        
        build_metadata = moderation.pop("metadata", {})
        metadata: dict[str, Any] = {
            **build_metadata,
            "severity_metadata": severity_metadata,
            "tolerance_patterns": tolerance_patterns,
            "error_patterns": error_patterns,
            "routing": "time_constraints_direct",  # Mark for analysis
        }
        
        result = GuidelineModerationOutput(
            id=guideline_id,
            guideline=guideline_text,
            classification=guideline.classification,
            answer=moderation.get("answer", False),
            time=moderation.get("time", "00:00"),
            reasoning=moderation.get("reasoning", ""),
            justification=moderation.get("justification", ""),
            metadata=metadata,
        )
        
        logger.debug(
            "Time constraint guideline moderation complete",
            guideline_id=guideline_id,
            answer=result.answer,
        )
        
        return result
    
    except ErrorType:
        raise
    except Exception as e:
        logger.error(
            "Time constraint guideline moderation failed",
            guideline_id=guideline_id,
            guideline_text=guideline_text,
            error=str(e),
            error_type=type(e).__name__,
            exc_info=True,
        )
        raise InternalServerError(
            message="Time constraint guideline moderation failed.",
            error_code="TIME_CONSTRAINTS_MODERATION_FAILED",
            details={
                "guideline_id": guideline_id,
                "guideline_text": guideline_text,
                "error": str(e),
                "error_type": type(e).__name__,
            },
        ) from e
```

### Expected Impact

- **+1.5pp from deterministic temporal validation:** Removes LLM ambiguity for time constraints
- **+0.5pp from routing clarity:** Prevents general pipeline from over-contextualizing temporal rules
- **Total: +2pp**

### Testing Strategy

1. Manually label TIME_CONSTRAINTS cases in eval dataset (should be ~15-20% of total)
2. Run eval with new routing
3. Compare TIME_CONSTRAINTS accuracy before/after
4. Validate no regressions on GENERAL guidelines

---

## Evaluation Framework — How to Run

### Location
`/root/.openclaw/workspace/guardian-agents-api/evals/`

### Prerequisites (from RELIABILITY-CHECKLIST.md)

1. **Auth:**
   - Service account JSON required for runs >30 min
   - Set: `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
   - Add to `.env` file (not just shell env)

2. **Config:**
   - BigQuery project: `brandlovers-prod`
   - Vertex AI project: `brandlovers-prod` (NOT homolog)
   - Check `src/configs/settings.py` for project IDs

3. **Environment:**
   ```bash
   cd /root/.openclaw/workspace/guardian-agents-api
   source .venv/bin/activate
   source .env  # or: export $(cat .env | xargs)
   ```

4. **Dataset:**
   - Combined dataset: `evals/datasets/combined_dataset.jsonl` (47 brands, 80+ cases)
   - Or brand-specific: `evals/datasets/general_guidelines.jsonl`, etc.

### Run Command

```bash
# Full eval (combined dataset)
python evals/run_eval.py --config evals/configs/content_moderation_combined.yaml --workers 4

# With progress tracking (recommended for long runs)
python evals/run_eval.py \
  --config evals/configs/content_moderation_combined.yaml \
  --workers 4 \
  --save-progress /tmp/guardian-eval-progress \
  --resume  # if resuming from previous run

# Subset for quick testing
python evals/run_eval.py \
  --config evals/configs/content_moderation_combined.yaml \
  --workers 2 \
  --limit 20  # first 20 cases only
```

### Metrics

From `evals/metrics.py` and `evals/configs/*.yaml`:

- **Per-field metrics:**
  - `answer`: exact_match (binary)
  - `time`: time_proximity (tolerance ±2s)
  - `reasoning`: (not evaluated in automated metrics)
  - `justification`: (not evaluated in automated metrics)

- **Aggregate:**
  - Weighted mean: `answer` (weight 1.0), `time` (weight 0.2)
  - **Agreement rate = average of answer exact_match**

### Expected Output

```
Running evaluations: 100%|████████████| 80/80 [18:23<00:00, 13.79s/it]

Evaluation complete:
  total_results: 80
  successful: 78
  failed: 2
  
Summary statistics:
  success_rate: 0.975
  mean_aggregate_score: 0.818  # This is our target!
  mean_latency: 13.8s
  
  field_statistics:
    answer:
      exact_match:
        mean: 0.818  # Agreement rate
        min: 0.0
        max: 1.0
```

### Reliability Checklist (from CAI-35 lessons)

- [ ] Auth validated (run `gcloud auth list` + check GOOGLE_APPLICATION_CREDENTIALS)
- [ ] BigQuery project = prod (not homolog)
- [ ] Vertex AI project = prod (not homolog)
- [ ] `.env` file includes GOOGLE_APPLICATION_CREDENTIALS
- [ ] AGENTS_RETRY_MAX_ATTEMPTS=3 (in .env)
- [ ] Progress tracking enabled (--save-progress flag)
- [ ] MAX_TOKENS cases identified (check dataset for large videos)
- [ ] Run estimate: 80 cases * ~14s = ~18 min (use service account for >30 min)
- [ ] tqdm redirect issue workaround (use `2>&1 | tee eval.log` if needed)

---

## Hypothesis Ranking Summary

| Rank | Hypothesis | Impact | Confidence | Ease | Code Changes | Expected Gain |
|------|------------|--------|------------|------|--------------|---------------|
| 1 | **A: Prompt Engineering** | High | 80% | High | 1 file, prompt-only | +3pp |
| 2 | **E: TIME_CONSTRAINTS Routing** | Medium-High | 90% | High | 1 file, new method | +2pp |
| 3 | **C: LLM-as-Judge** | High | 70% | Medium | 3 files, new agent | +3pp |
| 4 | **D: Memory Tuning** | Medium | 50% | Low | 2 files + BQ analysis | +1.5pp |
| 5 | **B: Archetype v2** | Medium | 60% | Medium | 2 files + taxonomy | +1.5pp |

## Recommended Execution Order

### Phase 1: Quick Wins (Week 1)
1. **Hypothesis E** (TIME_CONSTRAINTS routing) — highest confidence, clear fix
2. **Hypothesis A** (Prompt engineering) — high impact, prompt-only

**Expected gain:** +5pp (3pp + 2pp)  
**If achieved:** Goal met, ship to prod. Stop here.

### Phase 2: High-ROI Experiments (Week 2, if Phase 1 < +5pp)
3. **Hypothesis C** (LLM-as-Judge) — high impact, medium complexity

**Expected gain:** +3pp additional  
**If Phase 1 + Phase 2 ≥ +5pp:** Ship to prod.

### Phase 3: Fine-Tuning (Week 3, if still < +5pp)
4. **Hypothesis D** (Memory tuning) — requires data analysis, lower confidence
5. **Hypothesis B** (Archetype v2) — learned from CAI-35, needs careful design

---

## Implementation Notes

### PR Strategy

For each hypothesis:
1. Create feature branch: `feature/guardian-accuracy-hypothesis-X`
2. Implement changes with tests
3. Run eval on branch, document results in PR description
4. Tag Manoel + Juani for review
5. PR description format (pt-BR):
   ```markdown
   # Guardian Accuracy — Hypothesis X: [Name]
   
   ## Objetivo
   Melhorar taxa de concordância em +Xpp através de [brief description]
   
   ## Mudanças
   - [List of file changes]
   
   ## Resultados do Eval
   - Dataset: combined_dataset.jsonl (80 casos)
   - Taxa de concordância: XX.X% (baseline: 76.8%, delta: +X.Xpp)
   - Casos problemáticos resolvidos: [examples]
   - Regressões: [none/list]
   
   ## Próximos Passos
   [If goal met: deploy. If not: next hypothesis]
   ```

### Monitoring Post-Deploy

After deploying winning hypothesis:
1. Monitor agreement rate in production (compare even vs odd creator IDs)
2. Check Langfuse traces for new error patterns
3. Update MEMORY.md with lessons learned
4. Add new anti-error patterns to prompts

---

## Appendix: Code Diff Summary

### Hypothesis A: Prompt Engineering

**File:** `src/agents/templates/content_moderation/general/severity_analysis.j2`

```diff
+ **DECISÃO PARA SEVERIDADE 3 (Checklist Obrigatório):**
+ ✅ APROVE com Sev 3 se TODOS forem verdadeiros:
+   - Elemento visível/audível MAS dentro de "Typical Ranges" OU "Approved Phrases" dos padrões
+   [... 4 more conditions ...]
+ 
+ ❌ REJEITE com Sev 2 se QUALQUER for verdadeiro:
+   [... 4 conditions ...]

  Como interpretar o score:
- - O score é uma REFERÊNCIA, não decisão automática. Sempre pergunte: "O criador transmitiu a MESMA INFORMAÇÃO/AÇÃO?"
+ - **≥90%:** Praticamente idêntico → APROVE (mesmo com pequenas variações de artigos/preposições)
+ - **75-89%:** Mensagem central preservada MAS verifique elementos-chave:
+   [... detailed breakdown ...]
+ - **<60%:** Mensagem diferente → REJEITE
+ 
+ **REGRA DE OURO:** Prefira falsos negativos (rejeitar correto) a falsos positivos (aprovar errado).

+ **Passo 0.5: Verificação Anti-Padrões (EXECUTAR ANTES DE RACIOCINAR)**
+ [... 4 anti-pattern checks ...]
```

### Hypothesis E: TIME_CONSTRAINTS Routing

**File:** `src/services/content_moderation_service.py`

```diff
  for guideline in moderation_input.guidelines:
-     if guideline.classification in (ClassificationEnum.GENERAL_GUIDELINE, ClassificationEnum.TIME_CONSTRAINTS_GUIDELINE):
+     if guideline.classification == ClassificationEnum.TIME_CONSTRAINTS_GUIDELINE:
+         coroutines.append(
+             self._moderate_time_constraint_guideline(
+                 guideline=guideline,
+                 base_analysis=base_analysis,
+                 context=context,
+                 runners=runners,
+                 session_service=session_service,
+             )
+         )
+     elif guideline.classification == ClassificationEnum.GENERAL_GUIDELINE:
          coroutines.append(
              self._moderate_general_guideline(
                  guideline=guideline,
                  base_analysis=base_analysis,
                  context=context,
                  runners=runners,
                  session_service=session_service,
              )
          )

+ async def _moderate_time_constraint_guideline(self, ...) -> GuidelineModerationOutput:
+     """Moderate TIME_CONSTRAINTS guideline with deterministic temporal validation."""
+     [... ~100 lines of new implementation ...]
```

### Hypothesis C: LLM-as-Judge

**New files:**
- `src/agents/content_moderation/judge/correction_agent.py` (~150 lines)
- `src/agents/templates/content_moderation/judge/correction.j2` (~100 lines)

**Modified:**
- `src/services/content_moderation_service.py`: Add judge phase (~40 lines)
- `src/wire.py`: Wire judge agent (~10 lines)

---

## Conclusion

This plan provides 5 concrete hypotheses with code-level implementation details, expected impacts, and a clear testing strategy. The eval framework is documented and ready to use. Recommended approach:

1. Start with quick wins (Hypotheses E + A)
2. Run eval, measure impact
3. If <+5pp, proceed to Hypothesis C
4. Iterate until +5pp achieved or budget exhausted
5. Ship winner to prod, update MEMORY.md

Total estimated effort: 2-3 weeks for all 5 hypotheses if run sequentially. Can parallelize A/E/C for faster results.
