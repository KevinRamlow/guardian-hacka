#!/usr/bin/env python3
"""
Audio transcription using Google Gemini API
Supports: m4a, mp3, wav, flac, and other audio formats
"""

import sys
import os
import argparse
import mimetypes
from pathlib import Path

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("ERROR: google-genai not installed. Run: pip install google-genai", file=sys.stderr)
    sys.exit(1)


def transcribe_audio(audio_path: str, api_key: str, model: str = "gemini-2.5-flash") -> str:
    """
    Transcribe audio file using Gemini API
    
    Args:
        audio_path: Path to audio file
        api_key: Gemini API key
        model: Gemini model to use (default: gemini-2.5-flash)
    
    Returns:
        Transcription text
    """
    # Check if file exists
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
    
    # Get file info
    file_path = Path(audio_path)
    mime_type, _ = mimetypes.guess_type(audio_path)
    if not mime_type:
        # Default to common audio types
        ext = file_path.suffix.lower()
        mime_map = {
            '.m4a': 'audio/mp4',
            '.mp3': 'audio/mpeg',
            '.wav': 'audio/wav',
            '.flac': 'audio/flac',
            '.ogg': 'audio/ogg',
            '.aac': 'audio/aac'
        }
        mime_type = mime_map.get(ext, 'audio/mpeg')
    
    # Read audio file
    with open(audio_path, 'rb') as f:
        audio_data = f.read()
    
    # Create client
    client = genai.Client(api_key=api_key)
    
    # Create part with audio data
    audio_part = types.Part.from_bytes(data=audio_data, mime_type=mime_type)
    
    prompt = """Transcribe this audio file accurately. 
    - Return ONLY the transcription text, no preamble or explanation
    - Preserve natural speech patterns and punctuation
    - If the audio is in Portuguese, transcribe in Portuguese
    - If the audio is in another language, transcribe in that language"""
    
    # Generate transcription
    response = client.models.generate_content(
        model=model,
        contents=[prompt, audio_part]
    )
    
    return response.text.strip()


def main():
    parser = argparse.ArgumentParser(description="Transcribe audio files using Gemini API")
    parser.add_argument("audio_file", help="Path to audio file")
    parser.add_argument("--api-key", help="Gemini API key (or set GEMINI_API_KEY env var)")
    parser.add_argument("--model", default="gemini-2.5-flash", help="Gemini model to use")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    
    args = parser.parse_args()
    
    # Get API key
    api_key = args.api_key or os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: No API key provided. Use --api-key or set GEMINI_API_KEY env var", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Transcribe
        transcription = transcribe_audio(args.audio_file, api_key, args.model)
        
        # Output
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(transcription)
            print(f"Transcription saved to: {args.output}", file=sys.stderr)
        else:
            print(transcription)
    
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
