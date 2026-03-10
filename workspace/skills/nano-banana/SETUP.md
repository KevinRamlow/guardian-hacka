# Nano-Banana Setup Guide

## Installation Status

✅ **Package installed:** `@rafarafarafa/nano-banana-pro-mcp@1.0.4` (global)  
✅ **Binary location:** `/usr/bin/nano-banana-pro-mcp`  
✅ **mcporter configured:** 3 tools available (generate_image, edit_image, analyze_image)  
⚠️ **Needs API key:** Replace placeholder in config with real Gemini API key

## What is Nano-Banana?

Nano-Banana is an MCP (Model Context Protocol) server that enables image generation using Google's Gemini models, including:
- **Nano Banana Pro** (`gemini-3-pro-image-preview`) - Highest quality
- **Nano Banana** (`gemini-2.5-flash-preview-05-20`) - Fast iterations
- **Fallback** (`gemini-2.0-flash-exp`) - Widely available

It can **generate**, **edit**, and **analyze** images through simple text prompts.

## Prerequisites

### 1. Get a Gemini API Key

1. Visit [Google AI Studio](https://aistudio.google.com/apikey)
2. Sign in with your Google account (can use work or personal)
3. Click "Create API Key" or "Get API Key"
4. Copy the key (starts with `AIzaSy...`)

**Keep it secure!** Never commit it to Git or share publicly.

### 2. Configure mcporter

The package is already installed and configured in mcporter. You just need to add your API key.

**File:** `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json`

Find the `nano-banana` section and replace the placeholder:

```json
{
  "mcpServers": {
    "nano-banana": {
      "command": "nano-banana-pro-mcp",
      "env": {
        "GEMINI_API_KEY": "YOUR_GEMINI_API_KEY_HERE"  ← Replace this
      }
    }
  }
}
```

Replace `YOUR_GEMINI_API_KEY_HERE` with your actual Gemini API key from step 1.

### 3. Verify Setup

The server is already visible to mcporter:

```bash
# List servers - should show nano-banana with 3 tools
mcporter list

# Output should include:
# - nano-banana (3 tools, 0.4s)
```

Once you add your API key, test image generation:

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "a cute cat wearing sunglasses on a beach",
  "outputPath": "./test-output.png",
  "aspectRatio": "1:1"
}'
```

If successful, you should see `test-output.png` created with your generated image!

Alternatively, run the demo script:

```bash
cd ${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/nano-banana
./test-demo.sh
```

## Usage via mcporter

### Generate an Image

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "modern tech hero image showing collaboration",
  "aspectRatio": "16:9",
  "outputPath": "./images/hero.png"
}'
```

### Edit an Image

First, you need the image as base64. Helper script:

```bash
# Convert image to base64 for editing
IMAGE_B64=$(base64 -w 0 input.png)

mcporter call nano-banana edit_image --params "{
  \"prompt\": \"add sunglasses to the person\",
  \"images\": [{\"data\": \"$IMAGE_B64\", \"mimeType\": \"image/png\"}],
  \"outputPath\": \"./edited.png\"
}"
```

### Analyze an Image

```bash
IMAGE_B64=$(base64 -w 0 photo.jpg)

mcporter call nano-banana analyze_image --params "{
  \"prompt\": \"describe this image in detail\",
  \"images\": [{\"data\": \"$IMAGE_B64\", \"mimeType\": \"image/jpeg\"}]
}"
```

## Integration with OpenClaw/CaioBot

Once configured with a real API key, CaioBot can invoke nano-banana through the mcporter skill:

```bash
# In a skill or HEARTBEAT.md
mcporter call nano-banana generate_image --params '{"prompt": "...", "outputPath": "..."}'
```

Or if OpenClaw adds native MCP support, tools will be directly available.

## Example Use Cases

### 1. Team Update Images
Generate visuals for Slack announcements:

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "celebration image for feature launch, confetti and success theme, vibrant colors",
  "aspectRatio": "16:9",
  "outputPath": "./team-update-hero.png"
}'
```

### 2. Presentation Slides
Create backgrounds for technical presentations:

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "abstract geometric pattern for tech presentation background, corporate blue",
  "aspectRatio": "16:9",
  "imageSize": "2K"
}'
```

### 3. Memes for Team Chat
Generate work-appropriate memes:

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "funny meme showing surprised cat at computer, text space at top and bottom",
  "aspectRatio": "1:1"
}'
```

### 4. Diagrams
Create technical architecture diagrams:

```bash
mcporter call nano-banana generate_image --params '{
  "prompt": "system architecture diagram: API Gateway, Backend Services, Database, use boxes and arrows, modern tech style",
  "aspectRatio": "16:9"
}'
```

## Best Practices

### Prompting Tips

1. **Be specific:** "a sunset over mountains" → "dramatic sunset over snowy mountains, vibrant orange and purple sky, professional photography"
2. **Include style:** Add "minimalist", "professional", "funny", "corporate", "meme format"
3. **Specify format:** Always mention aspect ratio and intended use
4. **Iterate fast:** Use `gemini-2.5-flash-preview-05-20` for drafts, then `gemini-3-pro-image-preview` for finals

### Model Selection

- **Quick tests/iterations:** `gemini-2.5-flash-preview-05-20` (fast, good quality)
- **Final output:** `gemini-3-pro-image-preview` (slower, highest quality)
- **Fallback:** `gemini-2.0-flash-exp` (if others unavailable)

### File Organization

Save outputs to organized directories:

```bash
./images/presentations/
./images/team-updates/
./images/memes/
./images/diagrams/
```

### Security

- ⚠️ Never commit API keys to Git
- ✅ Use environment variables or secure config files
- ✅ Generated images are saved locally (not uploaded unless you share them)
- ✅ Consider adding `config/mcporter.json` to `.gitignore` if sharing repo

## Troubleshooting

### "GEMINI_API_KEY environment variable is required"

- Check that `config/mcporter.json` has your actual key (not the placeholder)
- Verify the key is correct (starts with `AIzaSy`)
- Make sure there are no extra spaces or quotes around the key

### "Rate limit exceeded"

- Gemini API has usage quotas (free tier: ~15 requests/minute)
- Wait a few minutes and try again
- Consider upgrading to paid tier for higher limits at https://ai.google.dev/pricing

### "Model not available"

- Try a different model: `gemini-2.5-flash-preview-05-20` or `gemini-2.0-flash-exp`
- Check Google AI Studio for model availability in your region
- Some models may require billing enabled

### Images are low quality

- Use `gemini-3-pro-image-preview` model (default)
- Increase `imageSize` to `"2K"` or `"4K"` when supported
- Make prompt more detailed and specific
- Add style references: "photorealistic", "digital art", "professional"

### mcporter doesn't see nano-banana

```bash
# Check if server is in config
cat ${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json | grep nano-banana

# List all servers
mcporter list

# If not showing up, check the binary exists
which nano-banana-pro-mcp
```

## What Caio Needs to Provide

✅ **Installation:** Complete (package installed, mcporter configured)  
⚠️ **API Key:** Get from https://aistudio.google.com/apikey  
⚠️ **Config Update:** Replace `YOUR_GEMINI_API_KEY_HERE` in `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json`

That's it! Just need the API key and CaioBot will be ready to generate images.

## Next Steps

1. **Get your Gemini API key** from https://aistudio.google.com/apikey
2. **Update mcporter config** at `${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/config/mcporter.json`
3. **Test it** with the demo script: `cd skills/nano-banana && ./test-demo.sh`
4. **Explore examples** in `examples.md` for common use cases
5. **Read SKILL.md** for detailed documentation and integration tips

## Resources

- **GitHub Repo:** https://github.com/mrafaeldie12/nano-banana-pro-mcp
- **Google AI Studio:** https://aistudio.google.com/apikey
- **mcporter Documentation:** See `/usr/lib/node_modules/openclaw/skills/mcporter/SKILL.md`
- **Example Prompts:** See `examples.md` in this skill directory
- **Quick Reference:** See `README.md` for common commands

## Support

If you encounter issues:
1. Check the GitHub repo for updates and known issues
2. Verify API key is correct and has not expired
3. Test with the simplest possible prompt first
4. Check Gemini API status/quotas in Google AI Studio dashboard
5. Try different models if one isn't working

---

**Ready to generate?** Just add your API key and start creating images! 🎨
