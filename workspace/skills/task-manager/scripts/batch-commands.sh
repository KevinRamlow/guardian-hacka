#!/usr/bin/env bash
# batch-commands.sh - Execute multiple commands with single shell invocation
# Usage: batch-commands.sh "cmd1" "cmd2" "cmd3"

set -e

for cmd in "$@"; do
    echo "▶ $cmd"
    eval "$cmd"
done
