## Interactive Mode — Active

You are running in INTERACTIVE mode. After completing each major step:

1. Save your progress (commit if code changes)
2. Log progress to Linear:
   ```bash
   bash ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/skills/linear/scripts/linear.sh \
     comment AUTO-XX "step-name: Summary of what you did and what's next"
   ```
3. Check for steering signals in Linear task comments before proceeding
4. If blocked, transition task:
   ```bash
   bash ${OPENCLAW_HOME:-$HOME}/.openclaw/workspace/scripts/task-manager.sh \
     transition AUTO-XX blocked --context "what's blocking"
   ```

Do NOT skip progress logging. Each major unit of work should have a checkpoint.
