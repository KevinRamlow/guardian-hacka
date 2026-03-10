# Audio Transcription Skill

Fast, accurate audio-to-text transcription using Google Gemini API.

## Quick Start

```bash
./transcribe.sh audio.m4a
```

## Features

✅ Supports m4a, mp3, wav, flac, ogg, aac  
✅ Auto-detects language (Portuguese, English, etc.)  
✅ Preserves punctuation and natural speech  
✅ Fast and cheap (Gemini 2.5 Flash)  
✅ Simple CLI interface  

## Installation

Dependencies auto-install on first run. Manual install:
```bash
pip3 install google-genai
```

## Configuration

API key auto-configured. Override with:
```bash
export GEMINI_API_KEY="your-key"
./transcribe.sh audio.m4a
```

## Full Documentation

See [SKILL.md](SKILL.md) for complete usage, examples, and integration guide.

## Testing

Tested with Caio's voice memo:
```bash
./transcribe.sh /Users/fonsecabc/.openclaw/media/inbound/ce3f6537-b0d2-4942-9653-bbfe12e24dd4.m4a
# Output: "Just a check, I'm just here to listen. Audios."
```

## Structure

```
audio-transcription/
├── SKILL.md           # Full documentation
├── README.md          # This file
├── transcribe.sh      # Convenience wrapper
└── scripts/
    └── transcribe.py  # Main Python script
```
