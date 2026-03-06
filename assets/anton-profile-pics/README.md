# Anton Profile Pictures

Generated on 2026-03-05 using the fixed nano-banana image generation script.

## Files

1. **anton-1-minimalist.png** (545KB)
   - **Style:** Minimalist tech lobster icon
   - **Prompt:** "minimalist tech lobster icon, clean geometric shapes, blue and white color scheme, modern flat design, simple silhouette, professional avatar style"
   - **Best for:** Professional contexts, LinkedIn, formal presentations

2. **anton-2-robot.png** (821KB)
   - **Style:** Robot lobster avatar
   - **Prompt:** "robot lobster avatar, mechanical parts, glowing blue circuits, futuristic tech design, cyberpunk aesthetic, profile picture style, high detail"
   - **Best for:** Tech blogs, GitHub profile, Discord

3. **anton-3-circuit.png** (997KB)
   - **Style:** Circuit board pattern
   - **Prompt:** "circuit board pattern in the shape of a lobster, blue PCB traces, electronic components, tech aesthetic, modern digital art, square avatar"
   - **Best for:** Tech presentations, code repository branding

4. **anton-4-pixel.png** (633KB)
   - **Style:** 8-bit pixel art
   - **Prompt:** "pixel art lobster avatar, 8-bit retro style, vibrant colors, game character design, nostalgic pixelated aesthetic, square format"
   - **Best for:** Casual social media, Slack emoji, fun contexts

## Generation Details

- **Model:** gemini-3-pro-image-preview (highest quality)
- **Tool:** `/root/.openclaw/workspace/skills/nano-banana/scripts/generate_image.py`
- **Format:** JPEG (returned by Gemini API)
- **Resolution:** 1024x1024 (standard for Gemini image models)

## Regeneration

To regenerate any image or create variations:

```bash
cd /root/.openclaw/workspace

# Regenerate minimalist style
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "minimalist tech lobster icon, clean geometric shapes, blue and white color scheme" \
  --output assets/anton-profile-pics/anton-1-minimalist-v2.png \
  --model gemini-3-pro-image-preview

# Create new variation
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "your custom lobster prompt here" \
  --output assets/anton-profile-pics/anton-custom.png \
  --model gemini-3-pro-image-preview
```

## Usage in IDENTITY.md

These images can be referenced in Anton's IDENTITY.md:

```markdown
**Avatar:** `/root/.openclaw/workspace/assets/anton-profile-pics/anton-1-minimalist.png`
```

Or for Slack/Discord emoji:
- Upload `anton-4-pixel.png` as `:anton:` emoji
- Use in messages: `:anton: coordinating sub-agents...`
