# Nano-Banana Skill

**Quick Reference:** Image generation via Gemini MCP server

## Status

✅ **Installed:** `@rafarafarafa/nano-banana-pro-mcp@1.0.4`  
⚠️ **Needs:** Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)

## Quick Start

### 1. Configure
Add to `/Users/fonsecabc/.openclaw/workspace/config/mcporter.json`:
```json
{
  "mcpServers": {
    "nano-banana": {
      "command": "nano-banana-pro-mcp",
      "env": {
        "GEMINI_API_KEY": "YOUR_KEY_HERE"
      }
    }
  }
}
```

### 2. Generate an Image
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "your image description here",
  "aspectRatio": "16:9",
  "outputPath": "./output.png"
}'
```

## Common Commands

### Hero Image for Presentations
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "modern tech presentation background, abstract blue gradient",
  "aspectRatio": "16:9",
  "imageSize": "2K"
}'
```

### Meme for Team Chat
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "funny surprised cat meme, text space at top and bottom",
  "aspectRatio": "1:1"
}'
```

### Architecture Diagram
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "system diagram: API → Backend → Database, boxes and arrows",
  "aspectRatio": "16:9"
}'
```

## Files

- **SETUP.md** - Complete setup instructions
- **SKILL.md** - Full documentation, API reference, best practices
- **examples.md** - Prompt library for common use cases

## Aspect Ratios

- `1:1` - Square (social media posts)
- `16:9` - Widescreen (presentations, YouTube)
- `9:16` - Vertical (mobile, stories)
- `4:3` - Classic (slides)
- `3:4` - Portrait

## Models

- `gemini-3-pro-image-preview` - Highest quality (default)
- `gemini-2.5-flash-preview-05-20` - Fast iterations
- `gemini-2.0-flash-exp` - Fallback

## Tools Available

1. `generate_image` - Create from text
2. `edit_image` - Modify existing images
3. `analyze_image` - Describe/analyze images

---

**Need help?** Read SETUP.md for step-by-step instructions.
