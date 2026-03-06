# presentations - AI-Generated Google Slides

**Description:** Generate premium presentation slides using nano-banana (Gemini image gen) and publish them as Google Slides presentations.

**Triggers:** Presentation requests, slide creation, deck building, pitch decks, team updates, keynotes.

## How It Works

1. **Generate slide images** via nano-banana (Gemini Pro image generation)
2. **Build .pptx** with python-pptx (images as full-bleed slide backgrounds)
3. **Upload to Google Drive** with automatic conversion to Google Slides
4. **Return shareable link** to the user

## Prerequisites

- ✅ nano-banana (Gemini API key configured)
- ✅ python-pptx installed
- ✅ gog auth with `drive` service for the target account

## Quick Usage

```bash
# Generate a single slide image
python3 skills/presentations/scripts/generate_slide.py \
  --prompt "Your slide description" \
  --output /tmp/slide.png

# Build a full deck and upload to Google Slides
python3 skills/presentations/scripts/build_deck.py \
  --title "My Presentation" \
  --slides /tmp/slide1.png /tmp/slide2.png /tmp/slide3.png \
  --account caio.fonseca@brandlovers.ai \
  --upload
```

## Workflow (Step by Step)

### Step 1: Design the Prompt

Use the **SaaS Diagram Template** (see TEMPLATES.md) as base. Customize:
- Header (brand, title, subtitle)
- Content (steps, data, layout)
- Style (colors, typography, mood)

**CRITICAL:** Always enhance prompts before generating. Add detail, specify exact layout, describe visual style. Never pass raw user text as-is.

### Step 2: Generate Images

```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "$(cat prompt.txt)" \
  --output slides/slide-1.png \
  --model gemini-3-pro-image-preview \
  --aspect-ratio 16:9
```

**Settings (always):**
- Model: `gemini-3-pro-image-preview` (highest quality)
- Aspect ratio: `16:9` (presentation standard)
- Temperature: 0.5 (in API call)
- Resolution: 4K

### Step 3: Build & Upload

```bash
python3 skills/presentations/scripts/build_deck.py \
  --title "Presentation Title" \
  --slides slides/slide-1.png slides/slide-2.png \
  --account caio.fonseca@brandlovers.ai \
  --upload
```

This creates a .pptx, uploads to Google Drive, converts to Google Slides, and returns the shareable URL.

## Rules

1. **ALWAYS generate images** via nano-banana — never use text-only slides
2. **ALWAYS upload to Google Slides** — never return local file paths
3. **ALWAYS enhance prompts** — better prompt = better slide
4. **ALWAYS use 16:9** aspect ratio for slides
5. **ALWAYS use gemini-3-pro-image-preview** for final output
6. **Return Google Slides URL** to the user, not file paths

## Error Handling

- If Drive auth fails → tell user to run: `gog auth add <email> --services gmail,calendar,drive`
- If image generation fails → retry once with simplified prompt
- If upload fails → save .pptx locally and share via Slack as fallback
