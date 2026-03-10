# Nano-Banana Scripts

## generate_image.py

Python wrapper for Gemini image generation that fixes the file-saving issue with the nano-banana MCP server.

### Problem

The nano-banana MCP server returns base64-encoded images but doesn't properly handle the `outputPath` parameter to save files to disk.

### Solution

This script:
1. Calls the Gemini Image Generation API directly
2. Extracts base64 image data from the `inlineData.data` field in the response
3. Decodes base64 to binary
4. Saves to disk when `--output` is provided
5. Returns proper JSON status

### Usage

```bash
python3 generate_image.py --prompt "description" --output path.png [--model name]
```

### Arguments

- `--prompt` (required): Image generation prompt
- `--output`, `-o`: Output file path (e.g., `./image.png`)
- `--aspect-ratio`: Aspect ratio (default: `1:1`) - Note: may not be supported by all models
- `--model`: Gemini model to use (default: `gemini-2.5-flash-image`)

### Available Models

- `gemini-3-pro-image-preview` - Highest quality (slower)
- `gemini-2.5-flash-image` - Fast, good quality (default)
- `gemini-2.0-flash-exp` - Fallback (maps to flash-image)

### Examples

```bash
# Basic usage
python3 generate_image.py \
  --prompt "minimalist tech lobster icon" \
  --output ./lobster.png

# High quality with specific model
python3 generate_image.py \
  --prompt "robot lobster, cyberpunk aesthetic, glowing circuits" \
  --output ./robot-lobster.png \
  --model gemini-3-pro-image-preview

# Without saving (returns base64)
python3 generate_image.py \
  --prompt "circuit pattern"
```

### Output

Success:
```json
{
  "success": true,
  "output_path": "/absolute/path/to/image.png",
  "size_bytes": 557087,
  "mime_type": "image/jpeg",
  "model": "gemini-3-pro-image-preview"
}
```

Error:
```json
{
  "success": false,
  "error": "API error 404: Model not found"
}
```

### Environment

The script looks for `GEMINI_API_KEY` in the environment or falls back to the key configured in `mcporter.json`.

### Exit Codes

- `0` - Success
- `1` - Error (API failure, file save error, etc.)

### Integration

This script can be used directly or wrapped in shell functions/aliases for convenience:

```bash
# Add to ~/.bashrc or similar
alias gen-image='python3 /Users/fonsecabc/.openclaw/workspace/skills/nano-banana/scripts/generate_image.py'

# Then use:
gen-image --prompt "cool image" --output ./cool.png
```

### Future Improvements

- Support for aspect ratio in API calls (if/when Gemini adds support)
- Batch generation (multiple prompts at once)
- Image editing wrapper (similar functionality for edit_image tool)
- Progress indicators for long-running generation
