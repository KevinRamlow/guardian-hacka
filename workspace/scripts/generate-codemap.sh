#!/usr/bin/env bash
# generate-codemap.sh — Generate a compact markdown codemap for a repository
# Usage: generate-codemap.sh /path/to/repo
# Output: markdown to stdout (caller redirects to file)
# Dependencies: bash, grep, awk, find, wc (no Python, no LLM)
# Compatible with bash 3.x (macOS default)

set -euo pipefail

REPO_PATH="${1:?Usage: generate-codemap.sh /path/to/repo}"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
REPO_NAME="$(basename "$REPO_PATH")"

MAX_FILES_PER_DIR=12

# Directories to skip
PRUNE_ARGS=""
for d in .venv venv node_modules __pycache__ .git .mypy_cache .pytest_cache htmlcov .tox dist build .eggs .next .nuxt coverage; do
    PRUNE_ARGS="$PRUNE_ARGS -path \"*/$d\" -prune -o"
done

# File extensions to include
EXT_ARGS="-name '*.py' -o -name '*.go' -o -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' -o -name '*.yaml' -o -name '*.yml'"

# Get all matching files sorted
ALL_FILES=$(eval "find \"$REPO_PATH\" $PRUNE_ARGS -type f \\( $EXT_ARGS \\) -print" | sort)
TOTAL_FILES=$(echo "$ALL_FILES" | grep -c . || echo 0)

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "# Codemap: $REPO_NAME"
    echo ""
    echo "No source files found."
    exit 0
fi

# Count total lines
TOTAL_LINES=0
while IFS= read -r f; do
    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    TOTAL_LINES=$((TOTAL_LINES + lines))
done <<< "$ALL_FILES"

# Extract a short description for a file
extract_signature() {
    local file="$1"
    local ext="${file##*.}"

    case "$ext" in
        py)
            # Try module docstring (first triple-quoted string in first 10 lines)
            local docstring
            docstring=$(awk '
                NR <= 10 {
                    if (/^"""/ || /^'"'"''"'"''"'"'/) {
                        gsub(/^"""|"""$|^'"'"''"'"''"'"'|'"'"''"'"''"'"'$/, "")
                        if (NF > 0) { print; exit }
                        getline
                        gsub(/^[[:space:]]*/, "")
                        if (NF > 0) { print; exit }
                    }
                }
            ' "$file" 2>/dev/null)

            if [ -n "$docstring" ]; then
                echo "$docstring"
                return
            fi

            # Extract class and top-level def names
            local sigs
            sigs=$(grep -E '^(class |def )' "$file" 2>/dev/null | head -4 | sed 's/(.*//' | sed 's/://' | sed 's/[[:space:]]*$//' | tr '\n' ', ' | sed 's/, $//')
            if [ -n "$sigs" ]; then
                echo "$sigs"
                return
            fi
            ;;
        go)
            local sigs
            sigs=$(grep -E '^(type |func )' "$file" 2>/dev/null | head -4 | sed 's/{.*//' | sed 's/[[:space:]]*$//' | tr '\n' ', ' | sed 's/, $//')
            [ -n "$sigs" ] && echo "$sigs"
            ;;
        js|ts|jsx|tsx)
            local sigs
            sigs=$(grep -E '^\s*(export |)(default |)(class |function |const |async function )' "$file" 2>/dev/null | head -4 | sed 's/{.*//' | sed 's/=.*//' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' | tr '\n' ', ' | sed 's/, $//')
            [ -n "$sigs" ] && echo "$sigs"
            ;;
        yaml|yml)
            local keys
            keys=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "$file" 2>/dev/null | head -6 | sed 's/:.*//' | tr '\n' ', ' | sed 's/, $//')
            [ -n "$keys" ] && echo "keys: $keys"
            ;;
    esac
}

# Build intermediate data: dir|file|lines|signature per file
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

while IFS= read -r f; do
    rel="${f#$REPO_PATH/}"
    dir="$(dirname "$rel")"
    base="$(basename "$rel")"
    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    sig=$(extract_signature "$f" 2>/dev/null | head -1 | cut -c1-100 || true)
    # Use tab as delimiter (safe since sig won't have tabs)
    printf '%s\t%s\t%s\t%s\n' "$dir" "$base" "$lines" "$sig" >> "$TMPFILE"
done <<< "$ALL_FILES"

# Sort by directory first (stable grouping), then by filename within each dir
sort -t$'\t' -k1,1 -k2,2 "$TMPFILE" > "${TMPFILE}.sorted"
mv "${TMPFILE}.sorted" "$TMPFILE"

# Header
echo "# Codemap: $REPO_NAME"
echo ""
echo "## Structure ($TOTAL_LINES lines across $TOTAL_FILES files)"
echo ""

# Process grouped by directory using awk
awk -F'\t' -v max_files="$MAX_FILES_PER_DIR" '
BEGIN {
    dir_count = 0
}
{
    dir = $1
    base = $2
    lines = $3
    sig = $4

    if (dir != current_dir) {
        # Print previous directory if exists
        if (current_dir != "") {
            print_dir()
        }
        current_dir = dir
        dir_lines = 0
        dir_file_count = 0
        delete files
        delete file_lines
        delete file_sigs
    }

    dir_file_count++
    dir_lines += lines
    files[dir_file_count] = base
    file_lines[dir_file_count] = lines
    file_sigs[dir_file_count] = sig
}

function print_dir() {
    if (current_dir == ".") {
        printf "### Root (%d lines, %d files)\n", dir_lines, dir_file_count
    } else {
        printf "### %s/ (%d lines, %d files)\n", current_dir, dir_lines, dir_file_count
    }

    limit = dir_file_count
    truncated = 0
    if (dir_file_count > max_files) {
        limit = max_files
        truncated = 1
    }

    for (i = 1; i <= limit; i++) {
        if (file_sigs[i] != "") {
            printf "- `%s` (%d lines) — %s\n", files[i], file_lines[i], file_sigs[i]
        } else {
            printf "- `%s` (%d lines)\n", files[i], file_lines[i]
        }
    }

    if (truncated) {
        printf "- ... and %d more files\n", dir_file_count - max_files
    }

    printf "\n"
}

END {
    if (current_dir != "") {
        print_dir()
    }
}
' "$TMPFILE"

# Entry points
echo "### Key entry points"
found_entry=0

# Check for main.py, __main__.py
while IFS= read -r f; do
    rel="${f#$REPO_PATH/}"
    base="$(basename "$f")"
    if [ "$base" = "main.py" ] || [ "$base" = "__main__.py" ]; then
        echo "- \`$rel\`"
        found_entry=1
    fi
done <<< "$ALL_FILES"

# Check for if __name__ == "__main__" (only in files we already indexed, not .venv etc)
py_files_only=$(echo "$ALL_FILES" | grep '\.py$' || true)
main_guard_files=""
if [ -n "$py_files_only" ]; then
    main_guard_files=$(echo "$py_files_only" | xargs grep -l '__name__.*__main__' 2>/dev/null | head -8) || true
fi
if [ -n "$main_guard_files" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#$REPO_PATH/}"
        base="$(basename "$f")"
        # Skip if already listed
        [ "$base" = "main.py" ] || [ "$base" = "__main__.py" ] && continue
        echo "- \`$rel\` (has \`__main__\` guard)"
        found_entry=1
    done <<< "$main_guard_files"
fi

# Check for Go main.go
while IFS= read -r f; do
    base="$(basename "$f")"
    if [ "$base" = "main.go" ]; then
        rel="${f#$REPO_PATH/}"
        echo "- \`$rel\`"
        found_entry=1
    fi
done <<< "$ALL_FILES"

# Check for JS/TS entry points
while IFS= read -r f; do
    base="$(basename "$f")"
    rel="${f#$REPO_PATH/}"
    case "$base" in
        index.js|index.ts|server.js|server.ts|app.js|app.ts)
            echo "- \`$rel\`"
            found_entry=1
            ;;
    esac
done <<< "$ALL_FILES"

# Check for Makefile/Dockerfile
[ -f "$REPO_PATH/Makefile" ] && echo "- \`Makefile\`" && found_entry=1
[ -f "$REPO_PATH/Dockerfile" ] && echo "- \`Dockerfile\`" && found_entry=1

[ $found_entry -eq 0 ] && echo "- (none detected)"
echo ""
