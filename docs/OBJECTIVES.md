# OBJECTIVES.md - Anton Self-Training Goals

**Last updated:** 2026-03-08 by Caio

---

## 🎯 Two-Level Optimization

Anton optimizes TWO things simultaneously:
1. **Guardian** (product) — accuracy, cost, latency
2. **Anton itself** (platform) — agent success rate, spawn efficiency, orchestration quality

---

## Guardian Metrics (Product)

### Current Status
- **Baseline accuracy:** 79.3% (guidelines_combined dataset)
- **Cost per moderation:** ~$0.052
- **Last improvement:** +5.7pp in 3 days

### Target Metrics
```yaml
primary_goal:
  metric: accuracy
  target: 87%  # +7.7pp from current
  deadline: 2026-03-15  # 7 days
  
constraints:
  - no_regression_on: CTA guidelines (currently 92.3%)
  - max_cost_per_mod: $0.055
  - max_latency: 8s
```

## Priority Areas

### 1. General Guidelines (HIGH PRIORITY)
- **Current:** 73.3%
- **Target:** 85%
- **Gap:** -11.7pp
- **Known issues:**
  - Color-of-clothing cases (Kibon, Sprite) — too tolerant
  - Semantic paraphrase detection (Mercado Pago, Vizzela, GOL)

### 2. Caption Parsing (MEDIUM PRIORITY)
- **Current:** 85%
- **Target:** 92%
- **Gap:** -7pp
- **Known issues:**
  - Parsing errors cascade to wrong moderation

### 3. Maintain CTA Excellence (LOW PRIORITY - DEFENSIVE)
- **Current:** 92.3%
- **Target:** maintain >90%
- **Strategy:** regression tests on every change

## Allowed Strategies

Anton can explore (autonomously):
- ✅ Prompt engineering (severity scale, anti-error patterns)
- ✅ Archetype taxonomy refinement
- ✅ Routing logic (phase 1/2 improvements)
- ✅ Judge agent tuning (borderline cases)
- ✅ Memory/tolerance pattern adjustments

Anton should NOT change (without approval):
- ❌ Core ADK framework structure
- ❌ External API integrations
- ❌ Database schema
- ❌ Production deployment configs

## Success Criteria

**+1pp improvement = auto-commit allowed**
- Fast mode validation (12 cases) for exploration
- Full validation (121 cases) before commit
- Git commit message: "AUTO: <description> (+X.Xpp)"

**Regression detection:**
- If any guideline type drops >1pp → auto-rollback
- Alert in #tech-gua-ma-internal

## Iteration Budget

- **Max parallel agents:** 5
- **Max iterations per 4h cycle:** 3
- **API budget per cycle:** $10
- **Stop conditions:**
  - Target reached (87% accuracy)
  - Budget exhausted
  - No improvement after 3 cycles

---

## Anton Platform Metrics (Meta)

### Current Status
- **Agent success rate:** ~60% (based on recent history)
- **Avg time per task:** 25 min
- **Spawn overhead:** ~30s per agent
- **Token efficiency:** ~15K tokens/task avg
- **Parallel capacity:** 3 slots (could be 5-10)

### Target Metrics
```yaml
meta_goals:
  agent_success_rate:
    current: 60%
    target: 85%
    deadline: 2026-03-22  # 2 weeks
  
  task_completion_time:
    current: 25min
    target: 15min  # faster iterations
    
  spawn_efficiency:
    current: 30s overhead
    target: 10s
    
  token_efficiency:
    current: 15K tokens/task
    target: 8K tokens/task  # better templates
    
  parallel_capacity:
    current: 3 concurrent agents
    target: 10 concurrent agents
```

### Priority Areas (Meta)

#### 1. Agent Templates (HIGH PRIORITY)
**Problem:** Agents fail because instructions are unclear or too verbose
**Target:** 85% success rate (vs 60% today)
**Strategies:**
- Simplify CLAUDE.md (currently 2K tokens → 800 tokens)
- Task-specific templates (guardian_eval, code_fix, analysis)
- Success criteria embedded in every task
- Examples in templates

#### 2. Spawn Infrastructure (MEDIUM PRIORITY)
**Problem:** 30s spawn overhead, only 3 parallel slots
**Target:** 10s spawn, 10 parallel slots
**Strategies:**
- Pre-warm agent sessions (keep 2-3 ready)
- Faster Linear API calls (batch operations)
- Remove redundant registry checks

#### 3. Knowledge Base (MEDIUM PRIORITY)
**Problem:** Agents explore codebase from scratch every time
**Target:** <5 min to understand guardian-agents-api
**Strategies:**
- Codemaps (already implemented, needs expansion)
- Pre-digested error patterns
- Common fixes library

#### 4. Validation Speed (LOW PRIORITY - DEFENSIVE)
**Problem:** 35 min eval runs slow iteration
**Target:** maintain accuracy, reduce to 20 min
**Strategies:**
- Parallel eval execution (already 10 workers, could be 20)
- Smarter sampling for fast mode
- Incremental validation (only test affected guidelines)

### Meta Success Criteria

**Agent success rate +5pp = auto-commit template changes**
**Spawn time -10s = auto-commit infrastructure changes**
**Token usage -20% = auto-commit template optimizations**

### Meta Iteration Budget

- **Max self-improvement cycles per day:** 2 (in addition to Guardian cycles)
- **API budget for meta-work:** $5/day
- **Allowed changes:**
  - ✅ Agent templates (CLAUDE.md, task templates)
  - ✅ Spawn scripts (spawn-agent.sh, registry logic)
  - ✅ Knowledge files (codemaps, error patterns)
  - ❌ Core OpenClaw config (requires manual approval)

---

**Edit this file to change Anton's objectives. He reads it every 4 hours and optimizes BOTH Guardian AND himself.**
