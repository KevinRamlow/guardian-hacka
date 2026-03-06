# Ralph Loop — Iterative Agent Orchestration

Based on [snarktank/ralph](https://github.com/snarktank/ralph). Fresh context per iteration, file-based memory, explicit acceptance criteria.

## Core Concept

Instead of spawning one agent for a big task and hoping, Ralph breaks work into **stories** (small units with acceptance criteria) and loops through them. Each iteration = fresh subagent with clean context + accumulated learnings.

## Files

```
/root/.openclaw/tasks/ralph/
├── {project-id}/
│   ├── prd.json          # Stories with passes:true/false + acceptance criteria
│   ├── progress.txt      # Append-only learnings across iterations
│   └── iterations.log    # Machine-readable iteration history
```

## Usage (Anton Orchestrator)

### 1. Create a PRD
```bash
ralph-loop.sh create <project-id> "<description>" "<branch>"
```
Then edit `/root/.openclaw/tasks/ralph/<project-id>/prd.json` to add stories.

### 2. Add stories
```bash
ralph-loop.sh add-story <project-id> "<title>" "<description>" '<acceptance_criteria_json>'
```

### 3. Run one iteration
```bash
# Returns the spawn task text for the next incomplete story
ralph-loop.sh next <project-id>
```
Use the output as task text for `sessions_spawn`.

### 4. Mark story complete (after agent finishes)
```bash
ralph-loop.sh pass <project-id> <story-id> "<learnings>"
```

### 5. Mark story failed (agent couldn't complete)
```bash
ralph-loop.sh fail <project-id> <story-id> "<reason>" "<learnings>"
```

### 6. Check status
```bash
ralph-loop.sh status <project-id>
```

### 7. Run full loop (spawn → wait → evaluate → next)
This is done by Anton (the orchestrator) in main thread:
1. `ralph-loop.sh next <project-id>` → get task text
2. `sessions_spawn` with that task text
3. Wait for completion announcement
4. Evaluate output against acceptance criteria
5. `ralph-loop.sh pass/fail` with learnings
6. Repeat until all stories pass or max iterations

## PRD Format
```json
{
  "project": "guardian-severity3",
  "branchName": "experiment/severity-3-boundary",
  "description": "Tune severity 3 boundary for +2pp agreement rate",
  "maxIterations": 10,
  "runtime": "subagent",
  "model": "anthropic/claude-sonnet-4-5",
  "cwd": "/root/.openclaw/workspace/guardian-agents-api",
  "stories": [
    {
      "id": "S-001",
      "title": "Analyze severity 3 disagreements",
      "description": "Query MySQL for all severity 3 cases where agent and brand disagree. Classify patterns.",
      "acceptanceCriteria": [
        "SQL query returns results",
        "At least 3 disagreement patterns identified",
        "Results written to /tmp/severity3-analysis.json"
      ],
      "priority": 1,
      "passes": false,
      "attempts": 0,
      "maxAttempts": 3,
      "notes": ""
    }
  ]
}
```

## Agent Prompt Template

Each spawned agent gets:
1. The ONE story to implement (not the whole PRD)
2. `progress.txt` contents (codebase patterns + previous learnings)
3. Acceptance criteria (explicit pass/fail checklist)
4. Working directory + branch
5. Instruction to append learnings before finishing

## Integration with Pipeline

Ralph loops can feed into the existing pipeline system:
- `ralph-loop.sh queue <project-id>` — adds next story to fast pipeline queue
- Pipeline spawner picks it up and runs it
- Completion triggers next story evaluation

## Key Principles

1. **One story per spawn** — never give an agent multiple stories
2. **Fresh context** — each spawn is clean, only progress.txt carries over
3. **Explicit acceptance** — every story has testable criteria
4. **Learnings accumulate** — progress.txt grows, future agents learn from past
5. **Fail fast, retry smart** — max 3 attempts per story, then escalate
6. **Quality gates** — tests/typecheck must pass before marking done
