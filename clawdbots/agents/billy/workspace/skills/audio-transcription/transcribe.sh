#!/bin/bash
# Audio transcription wrapper
# Usage: ./transcribe.sh <audio_file> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/scripts/transcribe.py"

# Default API key (can be overridden by env var)
export GEMINI_API_KEY="${GEMINI_API_KEY:-REDACTED_GEMINI_KEY}"

# Check if python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "ERROR: Python script not found at $PYTHON_SCRIPT" >&2
    exit 1
fi

# Check if audio file provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <audio_file> [--output file] [--model model_name]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 audio.m4a" >&2
    echo "  $0 audio.m4a --output transcription.txt" >&2
    echo "  $0 audio.m4a --model gemini-2.5-pro" >&2
    exit 1
fi

# Run Python script
python3 "$PYTHON_SCRIPT" "$@"
