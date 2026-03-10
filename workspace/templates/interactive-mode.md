## Interactive Mode — Active

You are running in INTERACTIVE mode. After completing each major step:

1. Save your progress (commit if code changes)
2. Call the checkpoint script:
   ```bash
   bash ${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/scripts/interactive-checkpoint.sh \
     AUTO-XX "step-name" "Summary of what you did and what's next"
   ```
3. Read the response:
   - `continue` -> proceed to next step
   - `abort` -> stop and mark task as blocked
   - `steer:direction` -> adjust your approach based on the direction
4. Act on the response before proceeding

Do NOT skip checkpoints. Each major unit of work should have a checkpoint.
