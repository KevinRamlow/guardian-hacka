# Ralph Loop — Anton Orchestration Guide

## How Anton Uses Ralph Loop

### For Multi-Step Tasks (Guardian improvements, Billy features, etc.)

1. **Receive task from Caio** → break into stories
2. **Create project:** `ralph-loop.sh create <id> "<desc>" "<branch>"`
3. **Add stories:** `ralph-loop.sh add-story <id> ...` (one per step)
4. **Loop:**
   ```
   a. task_text = ralph-loop.sh next <id>
   b. if COMPLETE → report to Caio
   c. sessions_spawn(task=task_text, label=ralph-<id>-<story>, mode=run)
   d. Wait for completion announcement (push-based)
   e. Evaluate: check acceptance criteria against agent output
   f. ralph-loop.sh pass/fail <id> <story> "<learnings>"
   g. Go to (a)
   ```

### Evaluating Agent Output

When a ralph subagent completes, Anton must:
1. Read the agent's output (from completion announcement)
2. Check each acceptance criterion:
   - If agent reported PASS with evidence → mark pass
   - If agent reported FAIL → mark fail with reason + learnings
   - If unclear → run verification commands (check files, run tests)
3. Extract learnings from agent's "Learnings for future iterations" section
4. Call pass/fail with combined learnings

### Parallel Ralph Loops

Multiple ralph projects can run simultaneously:
- `guardian-sev3` — severity 3 boundary tuning
- `billy-campaign-export` — Billy campaign feature
- Each has independent state, progress, iterations

### Integration with Pipeline

For automated execution without Anton in the loop:
1. Add stories to ralph project
2. Run `ralph-loop.sh next <id>` to get task text
3. Feed task text into pipeline: `pipeline-ctl.sh fast add <id> "<task_text>"`
4. Pipeline spawner handles execution
5. On completion: evaluate + pass/fail + queue next

### When to Use Ralph vs Direct Spawn

**Use Ralph when:**
- Task has 3+ steps that build on each other
- Previous attempts failed (need accumulated learnings)
- Quality gates matter (tests must pass before proceeding)
- Task is complex enough that one agent can't do it all

**Use Direct Spawn when:**
- Simple, single-step task
- Research/analysis (no code changes)
- One-shot operations (send message, check status)

### Story Design Tips

1. **Smallest possible scope** — each story should take 5-15 min for an agent
2. **Testable criteria** — "file exists" > "code is good"
3. **Independence** — earlier stories shouldn't need to be undone for later ones
4. **Progressive** — later stories build on earlier ones' output
5. **3 attempts max** — if 3 agents can't do it, the story needs redesigning
