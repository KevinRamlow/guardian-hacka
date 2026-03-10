# Agent Validation Checklist

Use this checklist after every agent completion. Do NOT report success without completing validation.

## 1. Read Agent Output

```bash
cat /Users/fonsecabc/.openclaw/tasks/agent-logs/CAI-XXX-output.log
```

**Check:**
- [ ] Agent completed without errors
- [ ] Agent didn't report being blocked
- [ ] Agent didn't request permissions/approvals

If blocked/errored: Move to "Blocked" status, investigate blocker.

## 2. Verify Claims

For each claim in the agent's output ("fixed X", "implemented Y", "analyzed Z"):

**Bug Fix Claims:**
```bash
# Reproduce the original bug
bash scripts/reproduce-bug.sh
# Expected: Should FAIL or show error

# Apply the fix (if not already applied by agent)
bash scripts/apply-fix.sh

# Re-test
bash scripts/reproduce-bug.sh
# Expected: Should PASS or work correctly
```

**Feature Claims:**
```bash
# Test the feature manually
bash skills/feature-name/test.sh
# Expected: Success message, no errors

# Check documentation was updated
ls -lh skills/feature-name/README.md
grep "new feature" skills/feature-name/README.md
# Expected: File exists and mentions the feature
```

**Analysis Claims:**
```bash
# Verify output file exists
ls -lh /Users/fonsecabc/.openclaw/workspace/analysis/YYYY-MM-DD-topic.md

# Check for actual findings (not empty)
wc -l /Users/fonsecabc/.openclaw/workspace/analysis/YYYY-MM-DD-topic.md
grep -c "Key finding" /Users/fonsecabc/.openclaw/workspace/analysis/YYYY-MM-DD-topic.md
# Expected: >50 lines, 3-5 findings
```

**Code Changes:**
```bash
# If agent claims to have modified code, check diff
cd /path/to/repo
git diff HEAD~1 -- file.py
# Expected: Shows actual changes

# If it's a script, test it
bash scripts/new-script.sh --help
# Expected: No syntax errors, shows usage
```

## 3. Run Success Criteria Commands

From the original task description, run EVERY validation command:

```bash
# Example from task
bash scripts/test-apostrophe-handling.sh
# Expected output from task: "✅ All 5 test cases passed"
```

**Compare actual vs expected:**
- [ ] Actual output matches expected output
- [ ] Exit code is 0 (success)
- [ ] No error messages in output

## 4. Check for Regressions

```bash
# Run related tests if they exist
bash scripts/test-related-functionality.sh

# For spawn system changes, test spawn still works
bash scripts/spawn-agent.sh --task CAI-TEST --label "validation-test" --timeout 5 "echo hello"
# Expected: Agent spawns successfully, no syntax errors
```

## 5. Document Validation Results

Create validation report:

```markdown
## CAI-XXX Validation Report

**Agent claim:** [what agent said it did]

**Validation steps:**
1. [command 1] → [result]
2. [command 2] → [result]
3. [command 3] → [result]

**Validation status:** ✅ PASS | ❌ FAIL | ⚠️ PARTIAL

**Evidence:**
- File X exists and contains Y
- Test Z passed with output: [paste output]
- Metric improved from A to B

**Conclusion:** Task complete / Task failed / Needs rework
```

## 6. Report to Caio

**If validation PASSED:**
```
✅ CAI-XXX validated and working

[Agent task name]

Validation:
• [test 1] passed
• [test 2] passed
• [metric] improved by Xpp

Evidence: [link or key output]
```

**If validation FAILED:**
```
❌ CAI-XXX failed validation

[Agent task name]

Agent claimed: [X]
Test result: [Y]

Error: [paste error]

Next action: [what you're doing to fix it]
```

**If validation BLOCKED:**
```
⚠️ CAI-XXX blocked - cannot validate

[Agent task name]

Blocker: [what's blocking validation]
Agent output: [relevant error snippet]

Need from you: [specific approval/access needed]
```

## Common Validation Patterns

**For spawn system fixes:**
```bash
# Test with problematic characters
bash scripts/spawn-agent.sh --task CAI-TEST --label "test-with-apostrophe's" --timeout 5 "echo test"
# Expected: No Python syntax errors, agent spawns
```

**For Guardian analysis:**
```bash
# Check output file exists and has content
[ -f /Users/fonsecabc/.openclaw/workspace/analysis/guardian-disagreements.md ] && echo "✅ File exists" || echo "❌ Missing"
wc -l /Users/fonsecabc/.openclaw/workspace/analysis/guardian-disagreements.md
# Expected: >100 lines with findings
```

**For Billy skills:**
```bash
# Test skill end-to-end
cd /Users/fonsecabc/.openclaw/workspace/clawdbots/agents/billy/workspace
bash skills/skill-name/test.sh
# Expected: Success output, no errors
```

## Anti-Patterns (Don't Do This)

❌ **"Agent said done, so it's done"** → Always verify
❌ **"File exists, task complete"** → Check file CONTENT
❌ **"No errors in log, must be good"** → Run the actual validation
❌ **"Looks reasonable"** → Use objective tests, not judgment
❌ **Skip validation because agent seems confident** → Confidence ≠ correctness

## Emergency Validation (When Blocked)

If you can't run full validation (missing tools, permissions, etc.):

**Minimal validation:**
1. Read agent output completely
2. Check if files mentioned actually exist
3. Spot-check 1-2 claims manually
4. Document what you COULDN'T validate
5. Report partial validation to Caio with gap list

**Better:** Fix the validation blocker first, then validate properly.
