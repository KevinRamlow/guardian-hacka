# nano-banana - Gemini Image Generation

**Description:** Generate, edit, and analyze images using Google's Gemini image generation models (Nano Banana Pro) via MCP server integration.

**Triggers:** Image generation requests, visual content creation, memes, diagrams, presentations, photo editing.

## Optimal Settings (Always Use These)

**Temperature:** 0.5 (best balance of creativity and accuracy to prompt)
**Resolution:** 4K (outputOptions.imageSize for highest quality)

**Critical:** The model performs significantly better and more accurate to the prompt with these settings. Always use temp 0.5 + 4K resolution unless user explicitly asks otherwise.

**Prompt Enhancement:** Always improve the user's prompt before generating. Use your skills to enhance clarity, add detail, specify style. A better prompt = better output.

**Prerequisites:**
- Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)
- MCP server configured in mcporter

## Installation Status

✅ **Package installed:** `@rafarafarafa/nano-banana-pro-mcp@1.0.4`
✅ **Binary available:** `/usr/bin/nano-banana-pro-mcp`
✅ **API key configured:** `GEMINI_API_KEY` in mcporter.json
✅ **Fixed:** Python wrapper script added to handle file saving (`scripts/generate_image.py`)

## 🔧 Fix Applied: File Saving Issue Resolved

**Problem:** The nano-banana MCP server returns base64-encoded images but doesn't handle the `outputPath` parameter to save files to disk.

**Solution:** Created a Python wrapper script (`scripts/generate_image.py`) that:
1. Calls the Gemini Image Generation API directly
2. Extracts base64 image data from the API response
3. Decodes and saves to disk when `--output` is provided
4. Returns proper JSON status with file path and size

**Usage:**
```bash
# Generate and save an image
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "your prompt here" \
  --output ./path/to/image.png \
  --model gemini-3-pro-image-preview

# Available models:
# - gemini-3-pro-image-preview (highest quality)
# - gemini-2.5-flash-image (fast, default)
```

**Example output:**
```json
{
  "success": true,
  "output_path": "/absolute/path/to/image.png",
  "size_bytes": 557087,
  "mime_type": "image/jpeg",
  "model": "gemini-3-pro-image-preview"
}
```

## Configuration

### mcporter Setup

Add to `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json`:

```json
{
  "servers": {
    "nano-banana": {
      "type": "stdio",
      "command": "nano-banana-pro-mcp",
      "env": {
        "GEMINI_API_KEY": "YOUR_GEMINI_API_KEY_HERE"
      }
    }
  }
}
```

Then use mcporter to interact:
```bash
# List available tools
mcporter list nano-banana

# Generate an image
mcporter call nano-banana generate_image --params '{"prompt": "a sunset over mountains", "outputPath": "./output.png"}'
```

## Available Tools

### 1. `generate_image` - Create images from text prompts

**Parameters:**
- `prompt` (required): Description of the image to generate
- `model` (optional): Gemini model to use
  - `gemini-3-pro-image-preview` - Nano Banana Pro (highest quality, default)
  - `gemini-2.5-flash-preview-05-20` - Nano Banana (fast)
  - `gemini-2.0-flash-exp` - Widely available fallback
- `aspectRatio` (optional): `"1:1"` | `"3:4"` | `"4:3"` | `"9:16"` | `"16:9"`
- `imageSize` (optional): `"1K"` | `"2K"` | `"4K"` (only for image models)
- `images` (optional): Array of reference images to guide generation
- `outputPath` (optional): File path to save the generated image

### 2. `edit_image` - Edit existing images

**Parameters:**
- `prompt` (required): Instructions for how to edit the image(s)
- `images` (required): Array of images to edit (base64 data)
- `model` (optional): Gemini model to use
- `outputPath` (optional): File path to save the edited image

### 3. `analyze_image` - Describe and analyze images

**Parameters:**
- `images` (required): Array of images to analyze
- `prompt` (optional): Custom analysis prompt
- `model` (optional): Gemini model to use

## Prompting Best Practices

### For Image Generation

**Be specific and descriptive:**
```
❌ "a cat"
✅ "a fluffy orange tabby cat wearing round sunglasses, sitting on a beach towel, digital art style"
```

**Include style/mood:**
```
✅ "minimalist logo for a tech startup, using blue and white colors, geometric shapes"
✅ "hero image for a travel website, showing a tropical beach at sunset, vibrant colors, professional photography style"
✅ "funny meme template with a surprised cat expression, text overlay space at top"
```

**Specify technical details when needed:**
```
✅ "presentation slide background, 16:9 aspect ratio, abstract geometric pattern in corporate blue"
✅ "Instagram post, 1:1 aspect ratio, product showcase, clean white background"
```

### For Image Editing

**Clear action verbs:**
```
✅ "Add sunglasses to the person in this photo"
✅ "Remove the background and make it transparent"
✅ "Change the sky to sunset colors"
✅ "Combine these two images into one scene, with the cat on the left and dog on the right"
```

### For Presentations & Diagrams

**Structured layouts:**
```
✅ "system architecture diagram showing 3 services: API Gateway, Backend Service, Database. Use boxes and arrows, modern tech style"
✅ "slide background for 'Product Launch' presentation, elegant gradient, space for text in center"
✅ "flowchart showing user signup process: Email → Verify → Profile → Done"
```

### For Memes

**Format + context:**
```
✅ "distracted boyfriend meme format, but with AI models comparing Claude vs GPT, funny style"
✅ "Drake hotline bling meme template, clean background, spaces for text labels"
```

## Common Use Cases

### Quick Hero Image
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "modern tech startup hero image, showing collaboration and innovation, vibrant colors",
  "aspectRatio": "16:9",
  "outputPath": "./hero.png"
}'
```

### Presentation Background
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "abstract geometric pattern background for presentation, corporate blue and white",
  "aspectRatio": "16:9",
  "imageSize": "2K"
}'
```

### Social Media Post
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "Instagram post announcing new feature launch, modern gradient, tech aesthetic",
  "aspectRatio": "1:1"
}'
```

### Logo Design
```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "minimalist logo for AI chatbot app named CaioBot, using lobster emoji concept, clean vector style",
  "aspectRatio": "1:1"
}'
```

## Model Selection Guide

| Model | Best For | Speed | Quality |
|-------|----------|-------|---------|
| `gemini-3-pro-image-preview` | High-quality final output | Slower | Highest |
| `gemini-2.5-flash-preview-05-20` | Quick iterations, drafts | Fast | Good |
| `gemini-2.0-flash-exp` | Fallback when others unavailable | Medium | Decent |

**Recommendation:** Use `gemini-2.5-flash-preview-05-20` for prototyping and testing, then regenerate with `gemini-3-pro-image-preview` for final output.

## Tips for CaioBot

1. **Aspect ratio matters:** Match the intended use case (16:9 for slides, 1:1 for social, 9:16 for mobile)
2. **Iterate fast:** Start with flash model, refine prompt, then use pro model for final
3. **Reference images:** When user shows an example style, use it as reference in `images` param
4. **Save outputs:** Always specify `outputPath` to keep generated images organized
5. **Team messages:** When generating images for team updates, aim for professional but friendly style
6. **Memes:** Lean into humor but keep it work-appropriate for Slack

## Error Handling

- **API key missing:** Returns error message with setup instructions
- **Invalid prompt:** Gemini will try its best, but specific prompts work better
- **Rate limits:** Gemini has usage quotas - if hit, wait or reduce frequency

## Security

- Never share API keys in messages or commits
- Store key in environment variables or secure config
- Generated images are saved locally by default

## Integration with OpenClaw

CaioBot can use mcporter skill to invoke nano-banana directly:
```bash
# In CaioBot workflow
mcporter call nano-banana generate_image --params '{"prompt": "...", "outputPath": "./images/result.png"}'
```

Or configure as MCP server for direct tool access (if OpenClaw supports MCP protocol).

## What Caio Needs to Provide

1. **Gemini API key** from https://aistudio.google.com/apikey
2. Add key to mcporter config at `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json`
3. Restart OpenClaw gateway if needed for config reload

Once configured, CaioBot can generate images on demand for presentations, team messages, memes, and more.

## ✅ Example: Anton Profile Pics

Generated 4 profile pictures for Anton using the fixed wrapper script:

1. **Minimalist Tech Lobster** - `assets/anton-profile-pics/anton-1-minimalist.png` (545KB)
   - Clean geometric shapes, blue/white, modern flat design
   
2. **Robot Lobster** - `assets/anton-profile-pics/anton-2-robot.png` (821KB)
   - Mechanical parts, glowing blue circuits, cyberpunk aesthetic
   
3. **Circuit Pattern** - `assets/anton-profile-pics/anton-3-circuit.png` (997KB)
   - PCB traces shaped like a lobster, electronic components
   
4. **Pixel Art** - `assets/anton-profile-pics/anton-4-pixel.png` (633KB)
   - 8-bit retro style, vibrant colors, nostalgic aesthetic

All generated using:
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "..." \
  --output assets/anton-profile-pics/anton-X-name.png \
  --model gemini-3-pro-image-preview
```
