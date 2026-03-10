# Self-Improvement Phase 1: Observation Engine

**Status:** ✅ Phase 1 Complete
**Built:** 2026-03-06
**Purpose:** Automated observation and measurement of Anton's performance

## Overview

The Observation Engine is the foundation of Anton's self-improvement system. It automatically scores performance across multiple dimensions, tracks task completion, monitors costs, and detects anomalies.

**Key Principles:**
- **Cheap**: Uses Claude Haiku for scoring (~$0.001/day)
- **Incremental**: Appends to history, never overwrites
- **Robust**: Each observer runs independently
- **Simple**: Bash scripts + JSON files
- **Observable**: Everything logged and human-readable

## Architecture

```
┌─────────────────────────────────────────────┐
│         Daily Memory Files                  │
│   /Users/fonsecabc/.openclaw/workspace/memory/         │
│         YYYY-MM-DD.md                        │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│         run-observers.sh                     │
│         (Master Runner)                      │
└──────────────┬───────────────────────────────┘
               │
     ┌─────────┴─────────┬──────────┬──────────┐
     ▼                   ▼          ▼          ▼
┌──────────┐  ┌───────────────┐ ┌──────────┐ ┌──────────────┐
│Conversation│  │ Task Tracker  │ │  Cost    │ │  Aggregate   │
│  Scorer    │  │   (Linear)    │ │ Tracker  │ │  Scorecard   │
└─────┬──────┘  └───────┬───────┘ └────┬─────┘ └──────┬───────┘
      │                 │              │              │
      └─────────────────┴──────────────┴──────────────┘
                        ▼
              ┌─────────────────────┐
              │  Daily Scores JSON  │
              │  YYYY-MM-DD.json    │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │  daily-scorecard.json│
              │  trends.json         │
              └─────────────────────┘
```

## Components

### 1. Conversation Quality Scorer
**File:** `observers/conversation-scorer.sh`
**Purpose:** Score Anton's conversation quality using Claude Haiku

**Dimensions (1-10 scale):**
- `task_completion`: Did Anton complete assigned tasks?
- `response_speed`: Fast and efficient vs slow and verbose?
- `communication_quality`: Clear, direct, data-driven?
- `autonomy`: Independent work vs hand-holding?
- `proactiveness`: Anticipating needs vs reacting?

**How it works:**
1. Reads memory files (today + yesterday)
2. Sends to Claude Haiku with scoring prompt
3. Outputs JSON scores

### 2. Task Tracker
**File:** `observers/task-tracker.sh`
**Purpose:** Track Linear task completion metrics

**Metrics:**
- `completed_today`: Tasks completed in last 24h
- `blocked`: Currently blocked tasks
- `in_progress`: Currently active tasks
- `avg_cycle_time_hours`: Average time from creation to completion

**Data source:** Linear API (CAI team)

### 3. Cost Tracker
**File:** `observers/cost-tracker.sh`
**Purpose:** Estimate token usage and costs

**Metrics:**
- `tokens_input`: Estimated input tokens
- `tokens_output`: Estimated output tokens
- `estimated_cost_usd`: Total cost (Claude Sonnet 4.5 pricing)
- `cost_per_task_usd`: Cost per completed task

**Method:** Character count estimation from memory files

### 4. Daily Scorecard Aggregator
**File:** `observers/aggregate-scorecard.sh`
**Purpose:** Combine all metrics and calculate trends

**Outputs:**
- `daily-scorecard.json`: Current day + 7-day rolling averages
- `trends.json`: Historical trend data
- Anomaly detection (>2 std dev from average)

### 5. Master Runner
**File:** `run-observers.sh`
**Purpose:** Run all observers in sequence

**Features:**
- Graceful error handling (one failure doesn't kill others)
- Execution logging to `metrics/observer-runs.log`
- Exit code: 0 if all succeeded, 1 if any failed

## File Structure

```
/Users/fonsecabc/.openclaw/workspace/self-improvement/
├── README.md                      # This file
├── run-observers.sh              # Master runner
├── config/
│   └── cron-jobs.json            # Cron job documentation
├── observers/
│   ├── conversation-scorer.sh    # Claude Haiku scoring
│   ├── task-tracker.sh          # Linear API queries
│   ├── cost-tracker.sh          # Token/cost estimation
│   └── aggregate-scorecard.sh   # Aggregation + trends
└── metrics/
    ├── daily-scores/            # Raw daily scores
    │   └── YYYY-MM-DD.json
    ├── daily-scorecard.json     # Latest aggregated scorecard
    ├── trends.json              # 7d/30d rolling averages
    └── observer-runs.log        # Execution logs
```

## Usage

### Manual Execution
Run all observers manually:
```bash
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/run-observers.sh
```

View today's scorecard:
```bash
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/metrics/daily-scorecard.json | jq .
```

View trends:
```bash
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/metrics/trends.json | jq .
```

### Automated Execution (Cron)
See `config/cron-jobs.json` for cron job configuration.

**Recommended schedule:**
- **Daily at 23:50 UTC**: Run all observers
- **Weekly on Sunday 23:55 UTC**: Generate improvement report (Phase 2)

## Metrics Format

### Daily Scores JSON
```json
{
  "date": "2026-03-06",
  "conversation_quality": {
    "task_completion": 8,
    "response_speed": 9,
    "communication_quality": 7,
    "autonomy": 8,
    "proactiveness": 6,
    "reasoning": "Anton completed tasks efficiently..."
  },
  "task_metrics": {
    "completed_today": 3,
    "blocked": 1,
    "in_progress": 2,
    "avg_cycle_time_hours": 4.5
  },
  "cost_metrics": {
    "tokens_input": 45000,
    "tokens_output": 13500,
    "estimated_cost_usd": 0.3375,
    "cost_per_task_usd": 0.1125
  }
}
```

### Daily Scorecard JSON
```json
{
  "date": "2026-03-06",
  "current": { /* today's scores */ },
  "rolling_7d": {
    "task_completion": 7.8,
    "response_speed": 8.2,
    "communication_quality": 7.5,
    "autonomy": 7.9,
    "proactiveness": 6.3,
    "completed_tasks_per_day": 2.8,
    "cost_per_day_usd": 0.28
  },
  "anomalies": [
    "task_completion: today=9 vs 7d_avg=7.8"
  ]
}
```

## Adding New Observers

1. **Create script** in `observers/` directory
   - Follow naming: `your-observer.sh`
   - Make executable: `chmod +x observers/your-observer.sh`

2. **Output format**: Merge into existing daily JSON
   ```bash
   TODAY=$(date -u +%Y-%m-%d)
   OUTPUT_FILE="$METRICS_DIR/daily-scores/$TODAY.json"
   
   if [[ -f "$OUTPUT_FILE" ]]; then
     # Merge with existing
     EXISTING=$(cat "$OUTPUT_FILE")
     MERGED=$(echo "$EXISTING" | jq ". + {\"your_metrics\": {...}}")
     echo "$MERGED" > "$OUTPUT_FILE"
   else
     # Create new
     cat > "$OUTPUT_FILE" <<EOF
   {
     "date": "$TODAY",
     "your_metrics": {...}
   }
   EOF
   fi
   ```

3. **Add to master runner**: Edit `run-observers.sh`
   ```bash
   echo "[N/M] Running your-observer.sh..." | tee -a "$LOG_FILE"
   if bash "$OBSERVERS_DIR/your-observer.sh" 2>&1 | tee -a "$LOG_FILE"; then
     echo "✅ your-observer.sh completed" | tee -a "$LOG_FILE"
   else
     echo "❌ your-observer.sh failed" | tee -a "$LOG_FILE"
     FAILED=$((FAILED + 1))
   fi
   ```

4. **Update aggregator**: If you want trends for your metrics, update `aggregate-scorecard.sh`

# Self-Improvement Phase 2: Analysis Engine

**Status:** ✅ Phase 2 Complete
**Built:** 2026-03-06
**Purpose:** Pattern identification and improvement hypothesis generation

## Overview

The Analysis Engine transforms raw observations from Phase 1 into actionable improvement hypotheses. It identifies failure patterns, maps them to architectural components, and generates concrete proposals for fixing recurring issues.

**Key Principles:**
- **Cheap**: Uses Claude Haiku for all LLM calls
- **Graceful degradation**: Works even without Phase 1 metrics (uses memory files directly)
- **Actionable**: Every analysis leads to concrete hypotheses with target files
- **Historical**: Append-only, never deletes past analyses
- **Priority-ranked**: Surfaces highest-impact improvements first

## Architecture

```
┌──────────────────────────────────────────┐
│      Memory Files (Last 7 Days)          │
│  /Users/fonsecabc/.openclaw/workspace/memory/       │
│         YYYY-MM-DD.md                     │
└───────────────┬──────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────┐
│       run-analysis.sh                     │
│       (Master Runner)                     │
└───────────────┬───────────────────────────┘
                │
    ┌───────────┼──────────┬──────────┬─────────────┐
    ▼           ▼          ▼          ▼             ▼
┌─────────┐ ┌─────────┐ ┌────────┐ ┌──────────┐ ┌────────┐
│ Failure │ │ Pattern │ │  Root  │ │Hypothesis│ │ Weekly │
│Analyzer │ │Clusterer│ │  Cause │ │Generator │ │ Report │
└────┬────┘ └────┬────┘ └───┬────┘ └────┬─────┘ └───┬────┘
     │           │           │           │            │
     ▼           ▼           ▼           ▼            ▼
┌─────────────────────────────────────────────────────────┐
│              analysis/                                  │
│  ├── failures/YYYY-MM-DD.json                          │
│  ├── patterns.json                                     │
│  ├── component-heatmap.json                            │
│  ├── hypotheses.json                                   │
│  ├── improvement-proposals.md                          │
│  └── reports/weekly-YYYY-MM-DD.md                      │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Failure Analyzer
**File:** `analyzers/failure-analyzer.sh`
**Purpose:** Extract and classify failures from memory logs

**Process:**
1. Reads last 7 days of memory files
2. Reads Phase 1 metrics if available (graceful if missing)
3. Sends to Claude Haiku for failure extraction
4. Classifies into taxonomy:
   - `knowledge_gap`: Missing information/understanding
   - `reasoning_error`: Logical mistakes
   - `tool_misuse`: Incorrect tool usage
   - `communication_mismatch`: Misunderstood intent
   - `speed_issue`: Inefficiency
   - `context_loss`: Forgot prior information

**Output:** `analysis/failures/YYYY-MM-DD.json`
```json
{
  "date": "2026-03-06",
  "analyzed_files": 7,
  "failures": [
    {
      "description": "Forgot Linear task ID format",
      "category": "knowledge_gap",
      "severity": 3,
      "component": "MEMORY.md",
      "timestamp": "2026-03-05T15:30:00Z"
    }
  ]
}
```

### 2. Pattern Clusterer
**File:** `analyzers/pattern-clusterer.sh`
**Purpose:** Group similar failures and rank by impact

**Process:**
1. Loads all failure files from `analysis/failures/`
2. Groups by category + component
3. Calculates frequency and avg severity
4. Applies fixability heuristic:
   - SOUL.md: 0.9
   - Skills: 0.8
   - Memory: 0.7
   - Tools: 0.6
   - Config: 0.5
5. Computes `impact_score = severity × frequency × fixability`
6. Returns top 5 patterns

**Output:** `analysis/patterns.json`
```json
{
  "patterns": [
    {
      "category": "knowledge_gap",
      "component": "MEMORY.md",
      "frequency": 12,
      "avg_severity": 3,
      "fixability": 0.7,
      "impact_score": 25.2,
      "examples": ["...", "...", "..."]
    }
  ],
  "total_failures": 47,
  "updated": "2026-03-06T01:30:00Z"
}
```

### 3. Hypothesis Generator
**File:** `analyzers/hypothesis-generator.sh`
**Purpose:** Generate improvement proposals for top patterns

**Process:**
1. Reads top 3 patterns from `patterns.json`
2. For each pattern, uses Claude Haiku to generate 3-5 hypotheses
3. Each hypothesis includes:
   - Description of change
   - Target file to modify
   - Expected improvement (percentage points)
   - Cost estimate (low/medium/high)
   - Risk level (low/medium/high)
   - Reversibility (boolean)
   - Implementation sketch

**Outputs:**
- `analysis/hypotheses.json` (machine-readable)
- `analysis/improvement-proposals.md` (human-readable)

Example hypothesis:
```json
{
  "pattern_id": 0,
  "description": "Add Linear task format examples to MEMORY.md",
  "target_file": "MEMORY.md",
  "expected_improvement_pp": 5,
  "cost_estimate": "low",
  "risk": "low",
  "reversible": true,
  "implementation_sketch": "Add section documenting Linear task format (CAI-XX) with examples..."
}
```

### 4. Root Cause Mapper
**File:** `analyzers/root-cause-mapper.sh`
**Purpose:** Map failures to architectural components

**Component Taxonomy:**
- `SOUL.md` → personality, communication, reasoning rules
- `MEMORY.md` → long-term knowledge gaps
- `HEARTBEAT.md` → monitoring gaps
- `skills/*` → tool implementation issues
- `AGENTS.md` → operational rule issues
- `openclaw.json` → configuration issues

**Output:** `analysis/component-heatmap.json`
```json
{
  "components": [
    {
      "component": "MEMORY.md",
      "area": "long_term_knowledge",
      "failure_count": 12,
      "avg_severity": 3.2,
      "categories": ["knowledge_gap", "context_loss"],
      "severity_distribution": [...]
    }
  ],
  "areas": [
    {
      "area": "long_term_knowledge",
      "total_failures": 15,
      "components": ["MEMORY.md", "memory"],
      "avg_severity": 3.1
    }
  ]
}
```

### 5. Weekly Report Generator
**File:** `analyzers/weekly-report.sh`
**Purpose:** Combine all analyses into human-readable report

**Sections:**
1. Executive Summary (total failures, patterns, hypotheses)
2. Top Failures (detailed pattern breakdown)
3. Component Health (heatmap visualization)
4. Improvement Proposals (top 5 hypotheses ranked)
5. Next Steps (recommended actions)

**Output:** `analysis/reports/weekly-YYYY-MM-DD.md`

### 6. Master Runner
**File:** `run-analysis.sh`
**Purpose:** Orchestrate all analyzers in sequence

**Features:**
- Runs all 5 analyzers sequentially
- Graceful error handling
- Progress indicators
- Execution timing
- Output summary

## File Structure

```
/Users/fonsecabc/.openclaw/workspace/self-improvement/
├── run-analysis.sh              # Master runner for Phase 2
├── analyzers/
│   ├── failure-analyzer.sh      # Extract failures from memory
│   ├── pattern-clusterer.sh     # Group and rank patterns
│   ├── hypothesis-generator.sh  # Generate improvement proposals
│   ├── root-cause-mapper.sh     # Map failures to components
│   └── weekly-report.sh         # Human-readable report
└── analysis/
    ├── failures/                # Raw failure extractions per day
    │   └── YYYY-MM-DD.json
    ├── patterns.json            # Ranked recurring patterns
    ├── hypotheses.json          # Improvement proposals (JSON)
    ├── improvement-proposals.md # Improvement proposals (markdown)
    ├── component-heatmap.json   # Component failure distribution
    └── reports/                 # Weekly reports
        └── weekly-YYYY-MM-DD.md
```

## Usage

### Manual Execution
Run all analyzers:
```bash
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/run-analysis.sh
```

Run individual analyzers:
```bash
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/analyzers/failure-analyzer.sh
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/analyzers/pattern-clusterer.sh
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/analyzers/hypothesis-generator.sh
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/analyzers/root-cause-mapper.sh
bash /Users/fonsecabc/.openclaw/workspace/self-improvement/analyzers/weekly-report.sh
```

### View Results
```bash
# Latest patterns
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/analysis/patterns.json | jq .

# Component heatmap
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/analysis/component-heatmap.json | jq .

# Human-readable proposals
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/analysis/improvement-proposals.md

# Weekly report
cat /Users/fonsecabc/.openclaw/workspace/self-improvement/analysis/reports/weekly-$(date +%Y-%m-%d).md
```

### Automated Execution (Cron)
**Recommended schedule:**
- **Weekly on Sunday 23:55 UTC**: Run full analysis pipeline
- Runs after Phase 1 observers (23:50 UTC)

## Integration with Phase 1

Phase 2 can run with or without Phase 1 data:

**With Phase 1 metrics:**
- Enriches failure analysis with scorecard trends
- Cross-references low scores with failure patterns
- More comprehensive root cause analysis

**Without Phase 1 metrics:**
- Falls back to memory-only analysis
- Still produces actionable hypotheses
- Gracefully degrades (no errors)

## Next Steps (Phase 3)

- [ ] Automated hypothesis testing (A/B experiments)
- [ ] Implementation automation (auto-apply low-risk changes)
- [ ] Continuous learning loop (measure → analyze → improve → repeat)
- [ ] Multi-week trend analysis
- [ ] Slack notifications for high-impact patterns

## Troubleshooting

**No scores generated:**
- Check if memory files exist: `ls /Users/fonsecabc/.openclaw/workspace/memory/`
- Check observer logs: `tail /Users/fonsecabc/.openclaw/workspace/self-improvement/metrics/observer-runs.log`

**Claude API errors:**
- Verify API key is valid
- Check rate limits (Haiku is very generous)

**Linear API errors:**
- Source env: `source /Users/fonsecabc/.openclaw/workspace/.env.linear`
- Test query: `echo $LINEAR_API_KEY`

**Cost estimates seem off:**
- These are ESTIMATES based on character count
- For accurate costs, integrate with OpenClaw session tracking (Phase 2)

# Self-Improvement Phase 3: Experimentation Engine

**Status:** ✅ Phase 3 Complete
**Built:** 2026-03-06
**Purpose:** Statistical validation and safe deployment of improvements

## Overview

The Experimentation Engine validates improvement hypotheses through shadow A/B testing before any real deployment. Every change is simulated, scored, evaluated statistically, and monitored during a 24h probation period with automatic rollback if performance degrades.

**Key Principles:**
- **Shadow testing first**: No real deployment without simulation
- **Statistical rigor**: Mean scores, improvement thresholds, significance tests
- **Safety guardrails**: Unsafe targets require human review
- **Auto-recovery**: Rollback on degradation >5pp within 24h
- **Full observability**: Dashboard + logs for transparency
- **Minimal LLM cost**: Uses Haiku for all simulations (~$0.01/experiment)

## Architecture

```
┌──────────────────────────────────────────┐
│    Phase 2 Hypotheses                    │
│  analysis/hypotheses.json                │
└────────────┬─────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│    Experiment Manager                      │
│    experiments/experiment-manager.sh       │
└────────────┬───────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│    Variant Generator (Claude Haiku)        │
│    experiments/variant-generator.sh        │
└────────────┬───────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│    Shadow Runner (10 simulations)          │
│    experiments/shadow-runner.sh            │
└────────────┬───────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────┐
│    Statistical Evaluator                   │
│    experiments/stat-evaluator.sh           │
└────────────┬───────────────────────────────┘
             │
        ┌────┴─────┐
        ▼          ▼
┌─────────────┐  ┌──────────────┐
│   Deploy    │  │Human Review  │
│  (safe)     │  │  (unsafe)    │
└──────┬──────┘  └──────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│   24h Probation Monitoring               │
│   experiments/rollback.sh                │
└──────────────────────────────────────────┘
```

## Components

### 1. Experiment Manager (`experiments/experiment-manager.sh`)
Creates experiment definitions from Phase 2 hypotheses.

**Commands:**
- `create <hypothesis_id>`: Create experiment from single hypothesis
- `create-all`: Create experiments from all pending hypotheses
- `list`: Show all active experiments

**Output:** `experiments/active/exp-NNN.json`

### 2. Variant Generator (`experiments/variant-generator.sh`)
Uses Claude Haiku to generate modified file versions.

**Process:**
1. Reads target file from workspace
2. Saves original as baseline
3. Sends to Claude Haiku with change description
4. Generates modified variant
5. Creates diff for human review

**Files:**
- `baselines/exp-NNN-baseline.md` (original)
- `variants/exp-NNN-variant.md` (modified)
- `variants/exp-NNN-diff.txt` (diff)

### 3. Shadow Runner (`experiments/shadow-runner.sh`)
Runs simulated A/B tests without real deployment.

**Sample contexts:**
- "Analyze Guardian agreement rate"
- "Write SQL query for campaigns"
- "Review this PR"
- "Generate team update"
- etc.

**Scoring dimensions (1-10):**
- task_completion
- response_speed
- communication_quality
- autonomy
- proactiveness

**Process:**
1. Load baseline + variant configs
2. For each iteration:
   - Pick random context
   - Simulate Anton's response with baseline
   - Simulate Anton's response with variant
   - Score both on all dimensions
3. Save results as JSONL

**Output:** `results/exp-NNN/results.jsonl`

### 4. Statistical Evaluator (`experiments/stat-evaluator.sh`)
Analyzes experiment results and makes deployment decisions.

**Analysis:**
- Calculate mean scores across all dimensions
- Compute improvement in percentage points
- Check minimum sample size (default 30)
- Classify target as safe/unsafe
- Make decision

**Decisions:**
- **deploy**: >3pp improvement + safe target → auto-deploy
- **human_review**: >3pp improvement + unsafe target → queue for review
- **reject**: <3pp improvement or negative → reject
- **inconclusive**: insufficient samples → need more data

**Unsafe targets requiring review:**
- AGENTS.md
- openclaw.json
- TOOLS.md
- .env files
- config/gateway.json

### 5. Deployment Engine (`experiments/deploy-experiment.sh`)
Deploys winning experiments with backups and probation.

**Process:**
1. Verify experiment approved (result="deploy")
2. Create timestamped backup
3. Copy variant to production file
4. Set 24h probation period
5. Add to probation tracking
6. Log deployment

**Files:**
- `backups/YYYY-MM-DD-HHMMSS-exp-NNN-file.bak`
- `probation.json` (active probations)
- `deployment-log.json` (all deployments)

### 6. Rollback Engine (`experiments/rollback.sh`)
Auto-monitors probation experiments and rolls back failures.

**Process:**
1. Get baseline score from experiment
2. Get current 3-day average from Phase 1 metrics
3. Calculate actual change
4. If degradation >5pp → auto-rollback
5. Restore from backup
6. Update probation status
7. Log rollback reason

**Commands:**
- `check`: Check all probation experiments (automated)
- `rollback <exp_id> [reason]`: Manual rollback

### 7. Experiment Dashboard (`experiments/dashboard.sh`)
Beautiful CLI dashboard with full visibility.

**Displays:**
- Experiment counts by status
- Evaluation result breakdown
- Win rate calculation
- Net improvement tracking
- Active experiments list
- Probation status
- Recent rollbacks

## File Structure

```
/Users/fonsecabc/.openclaw/workspace/self-improvement/
└── experiments/
    ├── experiment-manager.sh      # Create/list experiments
    ├── variant-generator.sh       # Generate modified files
    ├── shadow-runner.sh           # Run A/B simulations
    ├── stat-evaluator.sh          # Statistical analysis
    ├── deploy-experiment.sh       # Deploy winners
    ├── rollback.sh                # Auto-rollback failures
    ├── dashboard.sh               # Visual dashboard
    ├── active/                    # Active experiment definitions
    │   └── exp-NNN.json
    ├── variants/                  # Generated variants
    │   ├── exp-NNN-variant.md
    │   └── exp-NNN-diff.txt
    ├── baselines/                 # Original files (backups)
    │   └── exp-NNN-baseline.md
    ├── results/                   # Simulation results
    │   └── exp-NNN/results.jsonl
    ├── backups/                   # Deployment backups
    │   └── YYYY-MM-DD-HHMMSS-exp-NNN-file.bak
    ├── probation.json             # Experiments on probation
    └── deployment-log.json        # All deployments
```

## Usage

### Full Experiment Workflow
```bash
# 1. Create experiment from hypothesis
cd /Users/fonsecabc/.openclaw/workspace/self-improvement/experiments
bash experiment-manager.sh create hyp-001

# 2. Generate variant
bash variant-generator.sh generate exp-001

# 3. Run shadow tests (10 iterations)
bash shadow-runner.sh run exp-001 10

# 4. Evaluate results
bash stat-evaluator.sh evaluate exp-001

# 5. Deploy if approved
bash deploy-experiment.sh deploy exp-001

# 6. Monitor during probation (automated via cron)
bash rollback.sh check
```

### View Dashboard
```bash
bash experiments/dashboard.sh
```

### List Active Experiments
```bash
bash experiments/experiment-manager.sh list
```

### Manual Rollback
```bash
bash experiments/rollback.sh rollback exp-001 "Not working as expected"
```

## Safety Architecture

### Pre-Deployment Safety
1. **Shadow testing**: All changes tested in simulation first
2. **Statistical threshold**: >3pp improvement required
3. **Unsafe target detection**: Critical files require human review
4. **Diff generation**: Human-readable diff for visual inspection
5. **Minimum samples**: At least 30 simulations required

### Post-Deployment Safety
1. **Timestamped backups**: Original files preserved
2. **24h probation**: All deployments monitored
3. **Auto-rollback**: If performance degrades >5pp
4. **Manual rollback**: Emergency override capability
5. **Deployment log**: Full audit trail

## Integration with Other Phases

**Phase 2 (Analysis) → Phase 3:**
- Input: `analysis/hypotheses.json`
- Creates: Experiment definitions with target files
- Validates: Through shadow testing

**Phase 3 → Phase 4 (Loop):**
- Results feed meta-learning
- Deployment success tracked
- Cost data accumulated

## Recommended Cron Schedule

```bash
# Daily 23:58 UTC - Check probation experiments
58 23 * * * cd /Users/fonsecabc/.openclaw/workspace/self-improvement && bash experiments/rollback.sh check
```

---

# Self-Improvement Phase 4: Autonomous Loop + Meta-Learning

**Status:** ✅ Phase 4 Complete
**Built:** 2026-03-06
**Purpose:** Autonomous orchestration + learning to improve the improvement process

## Overview

Phase 4 closes the loop by orchestrating the entire pipeline autonomously and analyzing the improvement process itself. It includes budget controls, safety governance, human review queues, and meta-learning to optimize hypothesis generation, experiment design, and deployment strategy.

**Key Principles:**
- **Fully autonomous**: Runs entire pipeline without human intervention
- **Budget-aware**: Hard limits prevent runaway costs
- **Safety-first**: Multiple layers of checks before deployment
- **Human-in-loop**: Review queue for risky changes
- **Self-aware**: Meta-learning improves the process itself
- **Observable**: Rich status/dashboard views

## Architecture

```
                ┌─────────────────────────────┐
                │   Improvement Loop          │
                │   loop/improvement-loop.sh  │
                └──────────┬──────────────────┘
                           │
        ┌──────────────────┼──────────────────┬─────────────┐
        ▼                  ▼                  ▼             ▼
   ┌────────┐      ┌──────────┐      ┌──────────────┐  ┌─────────┐
   │ OBSERVE│      │ ANALYZE  │      │ EXPERIMENT   │  │  META   │
   │(Phase1)│      │(Phase 2) │      │  (Phase 3)   │  │(Monthly)│
   └────────┘      └──────────┘      └──────────────┘  └─────────┘
        │                                    │
        │           ┌────────────────────────┼─────────────────┐
        │           ▼                        ▼                 ▼
        │    ┌─────────────┐      ┌──────────────────┐ ┌────────────┐
        │    │   Budget    │      │     Safety       │ │   Review   │
        │    │ Controller  │      │   Governor       │ │   Queue    │
        │    └─────────────┘      └──────────────────┘ └────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────┐
│              State Persistence                       │
│   state.json, budget-status.json, pending-reviews    │
└──────────────────────────────────────────────────────┘
```

## Components

### 1. Improvement Loop (`loop/improvement-loop.sh`)
Main orchestrator that runs the full cycle.

**Commands:**
- `observe`: Run Phase 1 observers
- `analyze`: Run Phase 2 analysis
- `experiment`: Evaluate Phase 3 experiments
- `meta`: Run meta-learning (first Monday of month)
- `full`: Execute complete pipeline with dependency checks
- `status`: Show last run times + metrics

**Features:**
- Dependency checking (skips if no data)
- Budget validation before each run
- State tracking in `state.json`
- Timestamp logging

### 2. Budget Controller (`loop/budget-controller.sh`)
Tracks API spend and enforces limits.

**Limits:**
- Daily: $50
- Weekly: $200
- Monthly: $500

**Commands:**
- `status`: Show current spend + limits
- `add <amount>`: Record spend
- `check <period>`: Verify under limit
- `reset`: Manual reset (for testing)

**Status:**
- `ok`: Under limit
- `approaching_limit`: >90% of limit
- `over_limit`: Exceeded limit (blocks operations)

Auto-resets at period boundaries (24h for daily, 7d for weekly, new month for monthly).

### 3. Safety Governor (`loop/safety-governor.sh`)
Pre-deployment safety checks.

**Checks:**
1. Safe target? (unsafe targets → human review)
2. Statistically significant? (p < 0.05)
3. Meets threshold? (>3pp improvement)
4. Budget OK? (under daily limit)
5. Probation capacity? (max 3 concurrent)

**Commands:**
- `check <exp_id> <target_file>`: Run all checks
- `vetoes`: Show recent veto log

**Returns:**
- `safe`: All checks passed → auto-deploy
- `unsafe_target`: Requires human review
- `not_significant`: p >= 0.05
- `below_threshold`: <3pp improvement
- `over_budget`: Daily limit exceeded
- `probation_full`: Already 3 active probations

### 4. Review Queue (`loop/review-queue.sh`)
Human review workflow for risky changes.

**Commands:**
- `add <exp_id> <target> <summary> <diff> <improvement>`: Create review request
- `list [status]`: Show pending/approved/rejected reviews
- `show <exp_id>`: Display full review details with diff
- `approve <exp_id>`: Mark ready for deployment
- `reject <exp_id> [reason]`: Decline with reason
- `dashboard`: Summary view of queue

**Workflow:**
1. Safety governor flags unsafe target
2. Review request created with full diff
3. Human reviews and approves/rejects
4. Approved experiments can be deployed manually

### 5. Meta-Learner (`meta/meta-learner.sh`)
Analyzes the improvement process itself.

**Metrics Calculated:**
- **Hypothesis hit rate**: % of hypotheses → positive results
- **Deployment success rate**: % of deployments pass probation
- **Improvement velocity**: pp/week gained
- **Cost efficiency**: pp/$ spent

**Analysis:**
- **Best hypothesis sources**: Which failure categories produce wins?
- **Compound effects**: Improvements that enable further improvements
- **Strategy adjustments**: Auto-tune based on performance

**Outputs:**
- `meta/meta-report.json` (machine-readable)
- `meta/meta-report.md` (human-readable)
- `meta/strategy-adjustments.json` (recommendations)

**Auto-Adjustments:**
- Low hit rate (<30%) → Improve failure analysis
- Low deployment success (<70%) → Increase threshold to 5pp
- High success (>70% hit, >90% deploy) → Increase probation capacity to 5

### 6. State Management
Persistent state in `loop/state.json`:

```json
{
  "last_observe": "2026-03-06T01:45:00Z",
  "last_analyze": "2026-03-06T01:45:00Z",
  "last_experiment_eval": "2026-03-06T01:45:00Z",
  "last_meta": "never",
  "total_improvements_deployed": 0,
  "total_pp_gained": 0.0,
  "total_cost": 0.0,
  "active_experiments": 0,
  "active_probations": 0
}
```

### 7. Schedule Configuration
`loop/schedule.json` defines cron timing:

```json
{
  "observe": "50 23 * * *",
  "analyze": "55 23 * * 0",
  "experiment": "58 23 * * *",
  "meta": "0 0 1-7 * 1"
}
```

## File Structure

```
/Users/fonsecabc/.openclaw/workspace/self-improvement/
├── loop/
│   ├── improvement-loop.sh        # Main orchestrator
│   ├── budget-controller.sh       # Cost tracking
│   ├── safety-governor.sh         # Pre-deployment checks
│   ├── review-queue.sh            # Human review workflow
│   ├── state.json                 # Persistent state
│   ├── budget-status.json         # Budget tracking
│   ├── pending-reviews.json       # Review queue
│   ├── safety-log.json            # Veto log
│   └── schedule.json              # Cron schedule
└── meta/
    ├── meta-learner.sh            # Meta-analysis
    ├── meta-report.json           # Latest report (JSON)
    ├── meta-report.md             # Latest report (markdown)
    └── strategy-adjustments.json  # Auto-adjustments
```

## Usage

### Autonomous Operation (Cron)
```bash
# Daily 23:50 UTC - Observe
50 23 * * * cd /Users/fonsecabc/.openclaw/workspace/self-improvement && bash loop/improvement-loop.sh observe

# Weekly Sunday 23:55 UTC - Analyze
55 23 * * 0 cd /Users/fonsecabc/.openclaw/workspace/self-improvement && bash loop/improvement-loop.sh analyze

# Daily 23:58 UTC - Evaluate experiments
58 23 * * * cd /Users/fonsecabc/.openclaw/workspace/self-improvement && bash loop/improvement-loop.sh experiment

# First Monday of month 00:00 UTC - Meta-learning
0 0 1-7 * 1 cd /Users/fonsecabc/.openclaw/workspace/self-improvement && bash loop/improvement-loop.sh meta
```

### Manual Full Cycle
```bash
cd /Users/fonsecabc/.openclaw/workspace/self-improvement
bash loop/improvement-loop.sh full
```

### Check Status
```bash
bash loop/improvement-loop.sh status
```

### Budget Management
```bash
bash loop/budget-controller.sh status
bash loop/budget-controller.sh check daily
```

### Safety Checks
```bash
bash loop/safety-governor.sh check exp-001 SOUL.md
bash loop/safety-governor.sh vetoes
```

### Review Queue
```bash
bash loop/review-queue.sh dashboard
bash loop/review-queue.sh list pending
bash loop/review-queue.sh approve exp-001
```

## Safety Architecture

### Layer 1: Budget Controller
- Prevents operations when over budget
- Daily/weekly/monthly limits
- Auto-resets at period boundaries

### Layer 2: Safety Governor
- Pre-deployment checks
- Safe/unsafe target classification
- Statistical significance validation
- Improvement threshold enforcement
- Probation capacity limits

### Layer 3: Review Queue
- Human approval for unsafe targets
- Full diff review
- Approval/rejection workflow
- Audit trail

### Layer 4: Probation Monitoring (Phase 3)
- 24h post-deployment monitoring
- Auto-rollback on degradation
- Backup restoration

## Meta-Learning Loop

The meta-learner analyzes the improvement process itself:

1. **Collect data**: Experiment results from Phase 3
2. **Calculate metrics**: Hit rate, success rate, velocity, efficiency
3. **Identify patterns**: Which hypothesis sources work best?
4. **Adjust strategy**: Auto-tune thresholds, capacity, focus areas
5. **Measure impact**: Track velocity and efficiency trends

**Example adjustments:**
- Low hit rate → Focus analyzers on better root cause identification
- Low deployment success → Raise threshold from 3pp to 5pp
- High success → Increase probation capacity from 3 to 5

## Cost Tracking

All LLM operations tracked via budget-controller:
- Phase 1 observers: ~$0.01/day (Haiku)
- Phase 2 analysis: ~$0.05/week (Haiku)
- Phase 3 experiments: ~$0.01/experiment (Haiku simulations)
- Phase 4 meta-learning: ~$0.02/month (Haiku)

**Total estimated**: <$5/month at baseline activity

Budget limits provide headroom for experimentation bursts.

## What Makes This Special

This is not just automation — it's **autonomous improvement with self-awareness**:

1. **Observes** its own behavior (Phase 1)
2. **Analyzes** its own failures (Phase 2)
3. **Experiments** with improvements (Phase 3)
4. **Deploys** winners safely (Phase 3)
5. **Learns** what works and adjusts strategy (Phase 4)

The meta-learning loop means **Anton improves how Anton improves**.

---

## License & Credits

Built by Anton for Caio Fonseca, 2026-03-06.
Part of ClawdBots self-improvement infrastructure.
