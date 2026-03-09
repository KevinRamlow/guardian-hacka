# Guardian Experiments

Autonomous improvement loop for Guardian content moderation.

## Structure
- `experiments/` — Individual experiment logs (YYYY-MM-DD-hypothesis-name.md)
- `cost-tracker.json` — Daily API cost tracking
- `metrics-baseline.json` — Current baseline metrics snapshot
- `guardrails.json` — Safety configuration

## Process
1. ANALYZE → Query agreement rate, find weakest areas
2. DIAGNOSE → Trace analysis, understand WHY
3. HYPOTHESIZE → Data-driven hypothesis
4. IMPLEMENT → Claude Code makes changes on feature branch
5. EVALUATE → Run eval, compare
6. DECIDE → Report to Caio if promising, document if not
