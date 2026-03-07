# Task: [Short Description]

**Task ID:** CAI-XXX
**Type:** Bug Fix | Feature | Analysis | Test | Deployment
**Estimated time:** 5min | 15min | 25min
**Created:** YYYY-MM-DD HH:MM UTC

## Goal

One-sentence goal: "Fix X so that Y works" or "Analyze X to find Y"

## Success Criteria (MANDATORY)

Define EXACTLY how to verify this task is complete:

**For Bug Fixes:**
- [ ] Bug reproduced (show error)
- [ ] Fix applied (show diff)
- [ ] Bug no longer reproduces (show test)
- [ ] No regression (run related tests)

**For Features:**
- [ ] Feature implemented (show code/config)
- [ ] Feature works manually (show test steps + output)
- [ ] Documentation updated (README/SKILL.md)
- [ ] No breaking changes (test existing functionality)

**For Analysis:**
- [ ] Data queried (show SQL/commands used)
- [ ] Results analyzed (show findings with numbers)
- [ ] Patterns identified (list 3-5 key insights)
- [ ] Recommendations made (actionable next steps)

**For Tests:**
- [ ] Test cases written (show test file)
- [ ] Tests pass (show output)
- [ ] Coverage adequate (show what's tested)
- [ ] CI/automation added if needed

**For Deployment:**
- [ ] Changes deployed (show where)
- [ ] Service healthy (show status check)
- [ ] Functionality verified (manual test post-deploy)
- [ ] Rollback plan documented

## Context

What's the current state? What's broken/missing? Include:
- Error messages/logs
- File paths
- Relevant code snippets
- Links to related issues

## Task Details

Step-by-step what needs to be done:
1. First step
2. Second step
3. ...

## Validation Commands

Exact commands the orchestrator will run to verify completion:

```bash
# Example for bug fix
bash scripts/reproduce-bug.sh  # Should show error BEFORE
bash scripts/apply-fix.sh
bash scripts/reproduce-bug.sh  # Should show success AFTER
```

```bash
# Example for feature
bash skills/new-feature/test.sh
# Expected output: "✅ All tests passed"
```

```bash
# Example for analysis
mysql -e "SELECT COUNT(*) FROM results"
# Expected: > 0 rows
cat analysis-output.md | grep "Key findings"
# Expected: 3-5 bullet points
```

## Output Format

Where should results be saved? What format?
- Analysis → `/root/.openclaw/workspace/analysis/YYYY-MM-DD-topic.md`
- Fix → PR link or commit hash
- Feature → Documentation path
- Test → Test output log

## Blocking Risks

What could block this task?
- Missing permissions (MySQL, write, shell)
- Missing data/credentials
- Dependencies on other tasks
- Unclear requirements

If you hit a blocker: STOP, document it, report to orchestrator with exact error.
