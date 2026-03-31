# Error Forensics Skill

## Purpose
Systematic analysis of Guardian eval disagreements to find actionable patterns.

## Error Taxonomy

| Type | Definition | Direction | Action |
|------|-----------|-----------|--------|
| **False Positive (FP)** | Guardian rejected, human approved | Guardian too strict | Relax the relevant check |
| **False Negative (FN)** | Guardian approved, human rejected | Guardian too lenient | Tighten the relevant check |
| **Guideline Ambiguity** | Both answers defensible | N/A | Clarify guideline wording |
| **Media Edge Case** | Unusual content format | N/A | Add handling for edge case |
| **Prompt Interpretation** | Guardian misread the guideline | N/A | Rephrase prompt section |

## Pattern Detection Heuristics

### Step 1: Classify each error
```python
for case in disagreement_cases:
    guardian = case['actual']['answer']
    human = case['expected']['answer']

    if guardian == True and human == False:
        error_type = 'false_negative'  # Guardian too lenient
    elif guardian == False and human == True:
        error_type = 'false_positive'  # Guardian too strict
    else:
        error_type = 'interpretation_error'
```

**IMPORTANT - Brand Safety Inversion:**
In brand_safety, `answer: false` means "DOES violate" (NOT safe).
So `guardian=false, human=true` means Guardian said "violates", human said "doesn't violate" = False Positive.

### Step 2: Group by pattern
- Sort errors by classification + error_type
- Look for common guideline keywords
- Minimum 3 cases to form a pattern
- Example patterns:
  - "Informal language flagged as brand violation" (FP, 8 cases)
  - "Subtle product placement missed" (FN, 5 cases)
  - "Time boundary off-by-one" (FP, 3 cases)

### Step 3: Generate hypothesis
For each pattern:
```
HYPOTHESIS: [Specific change to make]
FILE: [exact path in guardian-agents-api-real/]
REASON: [Why this pattern exists, based on current prompt/logic]
EXPECTED IMPACT: [+Xpp on this classification]
EVIDENCE: [N cases showing this pattern]
```

## Hypothesis Generation Templates

### For False Positives (too strict):
"Relax [specific check] in [file] to allow [pattern] when [condition]. Currently flagging [N] cases where human evaluators approve."

### For False Negatives (too lenient):
"Add [specific check] in [file] to catch [pattern] when [condition]. Currently missing [N] cases where human evaluators reject."

### For Prompt Interpretation:
"Rephrase [section] in [file] prompt from '[current wording]' to '[proposed wording]' to better match human interpretation of [guideline type]."

## Few-Shot Query Patterns

```bash
# Get success examples for a classification
bash scripts/few-shot-db.sh query --classification brand_safety --type success --limit 5

# Get failure examples
bash scripts/few-shot-db.sh query --classification brand_safety --type failure --limit 5

# Semantic search for similar cases
bash scripts/few-shot-db.sh query --text "informal language profanity" --limit 10

# Filter by error type
bash scripts/few-shot-db.sh query --classification general --error-type false_positive --limit 5
```

## Injection Format for Prompts

When developers inject few-shot examples into Guardian prompts:
```xml
<examples>
<example verdict="approved">
<guideline>[guideline text]</guideline>
<content>[media description]</content>
<reasoning>[why this should be approved]</reasoning>
</example>
<example verdict="rejected">
<guideline>[guideline text]</guideline>
<content>[media description]</content>
<reasoning>[why this should be rejected]</reasoning>
</example>
</examples>
```
