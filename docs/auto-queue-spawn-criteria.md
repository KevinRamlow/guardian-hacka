# Auto-Queue Spawn Criteria

**Updated:** 2026-03-07 15:40 UTC
**Goal:** Avoid spawning agents for tasks that waste tokens (quick reads, analysis-only work)

## When Auto-Queue WILL Spawn

✅ **Label-based:**
- Task has `agent-required` label → always spawn

✅ **Keyword-based (title or description):**
- `eval` — evals take >20 min, worth spawning
- `hypothesis` — multi-hypothesis testing
- `implement` — code implementation work
- `fix` — bug fixes with code changes
- `refactor` — code refactoring
- `test` — test suite work
- `pr review` — review + changes
- `build` — building features
- `create` — creating new tools/scripts
- `deploy` — deployment work

## When Auto-Queue WILL SKIP

❌ **Label-based:**
- Task has `quick-win` or `manual` label → never spawn

❌ **Pattern-based (title or description):**
- Starts with `Read`, `Analyze`, `Document`, `Review` (without "implement"/"fix"/"test")
- Contains: `just read`, `only analyze`, `quick`, `5 min`, `simple`

❌ **Default:**
- If no spawn keywords found → skip (conservative approach)

## Examples

| Task Title | Spawn? | Reason |
|------------|--------|--------|
| "Implement multi-hypothesis Guardian eval" | ✅ Yes | keyword:implement |
| "Fix apostrophe escaping in spawn-agent.sh" | ✅ Yes | keyword:fix |
| "Test 3 prompt variations in parallel" | ✅ Yes | keyword:test |
| "Read Perfect-Web-Clone code and document patterns" | ❌ No | pattern:^read |
| "Analyze disagreement patterns (quick query)" | ❌ No | pattern:quick |
| "Document API endpoints" | ❌ No | pattern:^document |
| "Build dashboard UI generator" | ✅ Yes | keyword:build |

## Override with Labels

Want to force spawn or skip?

- Add `agent-required` label → always spawns (overrides skip patterns)
- Add `quick-win` or `manual` label → never spawns (overrides spawn keywords)

## Budget Protection

Even if task matches spawn criteria, auto-queue will skip if:
- Budget status = `over_monthly_limit` or `critical`
- No available slots (capacity check via agent-registry.sh)

## Testing the Logic

```bash
# Dry-run test (won't spawn, just shows decisions)
bash /root/.openclaw/workspace/scripts/auto-queue-v2.sh 2>&1 | grep -E "SPAWN|SKIP"
```

Expected output:
```
  SKIP: CAI-123 - pattern:^read - "Read code and analyze"
  SPAWN: CAI-124 (keyword:implement) - Implement feature X
  SKIP: CAI-125 - default:no-spawn-keyword - "Update documentation"
```
