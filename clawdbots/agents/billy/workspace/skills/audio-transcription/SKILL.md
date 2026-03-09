# Audio Transcription Skill

Transcribe audio files (m4a, mp3, wav, flac, etc.) to text using Google Gemini API.

## Description

This skill provides audio transcription capabilities using Gemini 2.5 Flash, which supports native audio input. It automatically detects the language and preserves natural speech patterns.

**Supported formats:**
- m4a (iPhone voice memos)
- mp3
- wav
- flac
- ogg
- aac

## Usage

### Basic Transcription

```bash
./skills/audio-transcription/transcribe.sh /path/to/audio.m4a
```

### Direct Python Script

```bash
python3 ./skills/audio-transcription/scripts/transcribe.py <audio_file>
```

### Save to File

```bash
./skills/audio-transcription/transcribe.sh audio.m4a --output transcription.txt
```

### Use Different Model

```bash
python3 ./skills/audio-transcription/scripts/transcribe.py audio.m4a --model gemini-2.5-pro
```

## Configuration

**API Key:** Set in environment or pass via `--api-key`

The skill automatically reads `GEMINI_API_KEY` from:
1. Command line `--api-key` argument
2. Environment variable `GEMINI_API_KEY`
3. Falls back to the key in wrapper script

**Current API key:** Set via `$GEMINI_API_KEY` env var

## Models

Available models (in order of speed/cost):
- `gemini-2.5-flash` (default) — fast, accurate, cheap
- `gemini-2.5-pro` — slower, more accurate, expensive
- `gemini-flash-latest` — alias for latest flash
- `gemini-pro-latest` — alias for latest pro

## Examples

**Transcribe iPhone voice memo:**
```bash
./skills/audio-transcription/transcribe.sh ~/Downloads/audio_message.m4a
```

**Transcribe from OpenClaw media inbound:**
```bash
./skills/audio-transcription/transcribe.sh /root/.openclaw/media/inbound/[file-id].m4a
```

**Batch transcription:**
```bash
for audio in *.m4a; do
  echo "=== $audio ==="
  ./skills/audio-transcription/transcribe.sh "$audio"
  echo
done
```

## Dependencies

- Python 3.8+
- `google-genai` package (installed automatically if missing)

Install manually:
```bash
pip3 install google-genai
```

## How It Works

1. Reads audio file from disk
2. Uploads to Gemini API with proper MIME type
3. Sends prompt for accurate transcription
4. Returns text output (preserves language and punctuation)
5. Outputs to stdout or file

## Integration

Use in other scripts:
```bash
TRANSCRIPTION=$(./skills/audio-transcription/transcribe.sh audio.m4a)
echo "User said: $TRANSCRIPTION"
```

Use from Python:
```python
from skills.audio_transcription.scripts.transcribe import transcribe_audio

text = transcribe_audio(
    audio_path="/path/to/audio.m4a",
    api_key="YOUR_API_KEY",
    model="gemini-2.5-flash"
)
print(text)
```

## Troubleshooting

**"ERROR: google-genai not installed"**
```bash
pip3 install --break-system-packages google-genai
```

**"ERROR: No API key provided"**
```bash
export GEMINI_API_KEY="your-api-key-here"
```

**"ERROR: models/X is not found"**
Check available models:
```python
from google import genai
client = genai.Client(api_key="YOUR_KEY")
print([m.name for m in client.models.list()])
```

## Quality Notes

- **Gemini 2.5 Flash:** Best balance of speed/quality/cost for transcription
- **Language detection:** Automatic (Portuguese, English, Spanish, etc.)
- **Accuracy:** High for clear audio, may struggle with background noise
- **Punctuation:** Automatically adds periods, commas, etc.
- **Speaker diarization:** Not supported (use single speaker audio)

## Cost

Gemini API pricing (as of 2025):
- **Input:** ~$0.075 per 1M tokens
- **Audio:** Billed as tokens based on duration
- **Typical 1-min audio:** ~$0.001-0.01

For high-volume transcription, consider OpenAI Whisper API or local Whisper models.
