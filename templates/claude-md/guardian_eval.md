# Guardian Eval Instructions

## Environment Setup

**MUST** source the environment before any eval command:
```bash
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
```
If you get a 403 error, you forgot this step. Source it and retry.

## Constraints

- **Max workers on Mac:** 10 (do not exceed or eval will OOM)
- Eval runs are stored in `evals/.runs/content_moderation/`
- Work from repo root: `cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real`

## CRITICAL: Fire and Forget

Evals take 30-40 minutes. **Do NOT wait for them to finish.** Launch in background and exit:

```bash
cd /Users/fonsecabc/.openclaw/workspace/guardian-agents-api-real
source /Users/fonsecabc/.openclaw/workspace/.env.guardian-eval
nohup python -m evals.run_eval \
  --config evals/content_moderation/eval.yaml \
  --workers 4 > /tmp/eval-${CAI_TASK_ID:-eval}.log 2>&1 &
echo "Eval PID=$!, log: /tmp/eval-${CAI_TASK_ID:-eval}.log"
```

Then log "Eval launched" and **exit immediately**. The watchdog handles the rest.

**NEVER:** Loop checking progress_meta.json, use `sleep` + check, poll with `callback`, or `while [ ! -f ... ]`.

## Partial Results

If an eval is interrupted, check for partial results before re-running. Use `--resume` to continue.

## Known Pitfalls

Read `knowledge/eval-patterns.md` for known pitfalls before starting.

## Baseline

Current production baseline: **86.78%** accuracy. Always compare your results against this.
