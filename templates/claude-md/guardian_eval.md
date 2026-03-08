# Guardian Eval Instructions

## Environment Setup

**MUST** source the environment before any eval command:
```bash
source /root/.openclaw/workspace/.env.guardian-eval
```
If you get a 403 error, you forgot this step. Source it and retry.

## Constraints

- **Max workers on Mac:** 10 (do not exceed or eval will OOM)
- Eval runs are stored in `/root/.openclaw/workspace/eval-runs/`

## Partial Results

If an eval is interrupted, check for partial results before re-running. Don't discard completed work — resume from where it stopped.

## Known Pitfalls

Read `knowledge/eval-patterns.md` for known pitfalls before starting.

## Baseline

Current production baseline: **86.78%** accuracy. Always compare your results against this.
