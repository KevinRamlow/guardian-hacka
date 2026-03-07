#!/bin/bash
# validate-agent.sh — Automated validation runner for agent tasks
# Parses validation commands from task markdown and executes them.
# Usage: bash scripts/validate-agent.sh <task-file.md>
# Exit 0 if all pass, exit 1 if any fail.

set -o pipefail

TASK_FILE="$1"

if [[ -z "$TASK_FILE" || ! -f "$TASK_FILE" ]]; then
    echo "Usage: validate-agent.sh <task-file.md>"
    echo "Error: Task file not found: $TASK_FILE"
    exit 2
fi

# Extract validation commands from ```bash blocks under "## Validation" header
extract_validation_blocks() {
    local in_section=0
    local in_block=0
    local block=""
    local block_num=0

    while IFS= read -r line; do
        # Detect validation section (## Validation Commands or ## Validation)
        if [[ "$line" =~ ^##[[:space:]]+Validation ]]; then
            in_section=1
            continue
        fi
        # Stop at next section
        if [[ $in_section -eq 1 && "$line" =~ ^##[[:space:]] && ! "$line" =~ ^##[[:space:]]+Validation ]]; then
            # Flush last block
            if [[ $in_block -eq 1 && -n "$block" ]]; then
                echo "---BLOCK_${block_num}---"
                echo "$block"
            fi
            break
        fi
        if [[ $in_section -eq 1 ]]; then
            if [[ "$line" =~ ^\`\`\`bash ]]; then
                in_block=1
                block=""
                ((block_num++))
                continue
            fi
            if [[ "$line" =~ ^\`\`\` && $in_block -eq 1 ]]; then
                in_block=0
                if [[ -n "$block" ]]; then
                    echo "---BLOCK_${block_num}---"
                    echo "$block"
                fi
                continue
            fi
            if [[ $in_block -eq 1 ]]; then
                # Skip comment-only lines and "Expected:" lines
                if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
                    continue
                fi
                if [[ -n "$block" ]]; then
                    block="$block"$'\n'"$line"
                else
                    block="$line"
                fi
            fi
        fi
    done < "$TASK_FILE"

    # Flush if file ended inside section
    if [[ $in_block -eq 1 && -n "$block" ]]; then
        echo "---BLOCK_${block_num}---"
        echo "$block"
    fi
}

total=0
passed=0
failed=0
results=""

# Parse and execute each validation block
current_block=""
block_label=""

while IFS= read -r line; do
    if [[ "$line" =~ ^---BLOCK_([0-9]+)--- ]]; then
        # Execute previous block if exists
        if [[ -n "$current_block" ]]; then
            ((total++))
            output=$(bash -c "$current_block" 2>&1)
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                ((passed++))
                results+="  ✅ Test $total: PASS (exit $exit_code)"$'\n'
            else
                ((failed++))
                results+="  ❌ Test $total: FAIL (exit $exit_code)"$'\n'
                results+="     Output: $(echo "$output" | head -3)"$'\n'
            fi
        fi
        current_block=""
        block_label="${BASH_REMATCH[1]}"
        continue
    fi
    if [[ -n "$block_label" ]]; then
        if [[ -n "$current_block" ]]; then
            current_block="$current_block"$'\n'"$line"
        else
            current_block="$line"
        fi
    fi
done < <(extract_validation_blocks)

# Execute last block
if [[ -n "$current_block" ]]; then
    ((total++))
    output=$(bash -c "$current_block" 2>&1)
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        ((passed++))
        results+="  ✅ Test $total: PASS (exit $exit_code)"$'\n'
    else
        ((failed++))
        results+="  ❌ Test $total: FAIL (exit $exit_code)"$'\n'
        results+="     Output: $(echo "$output" | head -3)"$'\n'
    fi
fi

# Report
echo "=== Validation Results ==="
echo "File: $TASK_FILE"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

if [[ $total -eq 0 ]]; then
    echo "⚠️  No validation blocks found in task file."
    exit 2
fi

echo "$results"

if [[ $failed -gt 0 ]]; then
    echo "❌ VALIDATION FAILED ($failed/$total tests failed)"
    exit 1
else
    echo "✅ ALL TESTS PASSED ($passed/$total)"
    exit 0
fi
