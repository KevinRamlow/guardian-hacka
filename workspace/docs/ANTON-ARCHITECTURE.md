# Anton Architecture - Two-Level Self-Training

**Inspired by Karpathy's autoresearch (March 2026)**

## The Key Insight

> **Agents should improve both the product AND themselves**

Karpathy's autoresearch: agent improves LLM training code
Anton: agent improves Guardian AND its own orchestration

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CAIO                                │
│          (edits OBJECTIVES.md, reviews results)             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ reads objectives
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    ANTON ORCHESTRATOR                       │
│                                                             │
│  ┌──────────────────────┐   ┌──────────────────────────┐  │
│  │   GUARDIAN LOOP      │   │      META LOOP           │  │
│  │   (every 4 hours)    │   │   (every 24 hours)       │  │
│  │                      │   │                          │  │
│  │  Improves:           │   │  Improves:               │  │
│  │  - Guardian accuracy │   │  - Agent templates       │  │
│  │  - Cost per mod      │   │  - Spawn efficiency      │  │
│  │  - Latency           │   │  - Success rate          │  │
│  │                      │   │  - Token usage           │  │
│  │  Target: 87%         │   │  Target: 85% success     │  │
│  │  Current: 79.3%      │   │  Current: 60% success    │  │
│  └──────────┬───────────┘   └─────────┬────────────────┘  │
│             │                         │                   │
└─────────────┼─────────────────────────┼───────────────────┘
              │                         │
              │ spawns                  │ spawns
              ▼                         ▼
    ┌──────────────────┐      ┌──────────────────┐
    │  Guardian Agents │      │   Meta Agents    │
    │  (3-5 parallel)  │      │  (2 parallel)    │
    │                  │      │                  │
    │  Test:           │      │  Improve:        │
    │  - Prompts       │      │  - CLAUDE.md     │
    │  - Routing       │      │  - Templates     │
    │  - Archetypes    │      │  - Spawn scripts │
    │  - Judges        │      │  - Codemaps      │
    │                  │      │                  │
    │  Fast: 5 min     │      │  Time: 20 min    │
    │  Full: 35 min    │      │  Validation: N/A │
    └──────┬───────────┘      └──────┬───────────┘
           │                         │
           │ results                 │ improvements
           ▼                         ▼
    ┌──────────────────────────────────────────┐
    │           AUTO-COMMIT                    │
    │                                          │
    │  Guardian: +1pp → commit                 │
    │  Meta: +5% success rate → commit         │
    │                                          │
    │  Git history = knowledge accumulation    │
    └──────────────────────────────────────────┘
```

## Comparison with Karpathy's Autoresearch

| Dimension | Karpathy Autoresearch | Anton |
|-----------|----------------------|-------|
| **Product loop** | LLM training code | Guardian moderation |
| **Meta loop** | Training infrastructure | Anton orchestration |
| **Cycle time** | 5 min (fast!) | 5 min fast / 35 min full |
| **Metrics** | Validation loss | Accuracy, success rate |
| **Auto-commit** | Yes (if loss improves) | Yes (if metrics improve) |
| **Knowledge base** | Git commits | Git commits + codemaps |
| **Human role** | Edit prompt.md | Edit OBJECTIVES.md |

## Why Two Levels?

**Level 1 (Guardian):** Improves the product
- Better accuracy
- Lower cost
- Faster latency

**Level 2 (Meta):** Improves the platform
- Agents succeed more often
- Tasks complete faster
- Less token waste
- Better parallelization

**Compounding effect:** Better platform → better agents → better product → faster improvement → better platform → ...

## Key Files

### Configuration
- `OBJECTIVES.md` - What to optimize (Guardian + Meta targets)
- `.anton-auto-state.json` - Guardian loop state
- `.anton-meta-state.json` - Meta loop state

### Scripts
- `scripts/anton-auto-loop.sh` - Guardian improvement loop
- `scripts/anton-meta-loop.sh` - Meta improvement loop
- `scripts/fast-eval.sh` - 5-min eval (10% dataset)
- `scripts/run-guardian-eval.sh` - Full eval (121 cases)

### Scheduling
- `~/Library/LaunchAgents/com.anton.auto-loop.plist` - Guardian (4h)
- `~/Library/LaunchAgents/com.anton.meta-loop.plist` - Meta (24h)

### Knowledge Base
- `knowledge/guardian-agents-api.map.md` - Codemap
- `knowledge/common-errors.md` - Error patterns
- `templates/claude-md/` - Task templates

## Expected Improvements

### Week 1
- **Guardian:** +1-2pp accuracy (6 cycles × 0.3pp avg)
- **Meta:** Agent templates simplified, common errors documented

### Week 2
- **Guardian:** +2-3pp (learning what works)
- **Meta:** Spawn time -20s, success rate +10%

### Week 3
- **Guardian:** +3-4pp (meta-learning)
- **Meta:** Token usage -30%, parallel capacity 5→8 slots

### Month 1
- **Guardian:** +5-8pp total (target: 87%, current: 79.3%)
- **Meta:** 85% agent success rate (vs 60% today)

## The Endgame

**Fully autonomous R&D loop:**
1. Caio sets high-level goals (OBJECTIVES.md)
2. Anton explores solution space autonomously
3. Git accumulates working improvements
4. Platform gets better at exploring
5. Product improves faster over time

**No human in the loop except:**
- Setting objectives
- Reviewing final results
- Approving risky changes

This is **self-training AI research infrastructure** - exactly what Karpathy built, but for product improvement instead of LLM training.

---

**Status:** ✅ Active since 2026-03-08
**Guardian baseline:** 79.3% → target 87%
**Meta baseline:** 60% success → target 85%
**Cycles:** Guardian (4h), Meta (24h)
