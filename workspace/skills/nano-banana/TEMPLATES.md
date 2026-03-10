# Nano-Banana Prompt Templates

Quick-start templates for common use cases. Copy, customize, generate.

---

## 🎨 Profile Pictures

### Tech Mascot (Minimalist)
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "a [MASCOT] [ACTIVITY], minimalist flat design, geometric shapes, [COLOR] color scheme, 1:1 aspect ratio, centered composition, clean and modern" \
  --output ./profile-pic-minimalist.png \
  --model gemini-3-pro-image-preview
```
**Example:** `a lobster wearing headphones, minimalist flat design, geometric shapes, blue and white color scheme, 1:1 aspect ratio, centered composition, clean and modern`

### Pixel Art Style
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "a [CHARACTER] [DOING WHAT], 8-bit pixel art style, retro gaming aesthetic, vibrant colors, 1:1 aspect ratio, centered composition, nostalgic vibe" \
  --output ./profile-pic-pixel.png \
  --model gemini-2.5-flash-image
```
**Example:** `a robot assistant coding, 8-bit pixel art style, retro gaming aesthetic, vibrant colors, 1:1 aspect ratio, centered composition, nostalgic vibe`

### Abstract Logo
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[CONCEPT DESCRIPTION], abstract vector logo style, single color [COLOR], 1:1 aspect ratio, minimalist and scalable, modern tech aesthetic" \
  --output ./profile-pic-abstract.png \
  --model gemini-3-pro-image-preview
```
**Example:** `brain with circuit patterns, abstract vector logo style, single color blue, 1:1 aspect ratio, minimalist and scalable, modern tech aesthetic`

---

## 📊 Presentations

### Clean Background (Professional)
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "abstract geometric pattern, presentation slide background, modern minimalist design, 16:9 aspect ratio, [COLOR] gradient, professional corporate style, space for centered text" \
  --output ./slide-bg-professional.png \
  --model gemini-2.5-flash-image
```
**Variables:** Replace `[COLOR]` with "blue to white", "purple to pink", "gray to light blue"

### Tech/Data Theme
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "circuit board pattern background, tech presentation slide, modern digital aesthetic, 16:9 aspect ratio, dark theme with [COLOR] accents, space for title text at top" \
  --output ./slide-bg-tech.png \
  --model gemini-2.5-flash-image
```
**Variables:** `[COLOR]` = "neon blue", "cyan", "green", "purple"

### Hero Slide (Product Launch)
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "celebration scene with confetti and light rays, hero image for product launch, vibrant and exciting, 16:9 aspect ratio, dynamic composition, colorful and joyful, space for large title" \
  --output ./slide-hero-launch.png \
  --model gemini-3-pro-image-preview
```

---

## 📱 Social Media

### Instagram Post (Square)
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[MAIN VISUAL], Instagram post for [PURPOSE], 1:1 aspect ratio, modern gradient, minimalist tech style, space for text overlay in center, vibrant and eye-catching" \
  --output ./social-instagram.png \
  --model gemini-2.5-flash-image
```
**Example:** `modern gradient background from blue to purple, Instagram post for AI feature announcement, 1:1 aspect ratio, modern gradient, minimalist tech style, space for text overlay in center, vibrant and eye-catching`

### LinkedIn Banner (Wide)
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "professional [THEME] background, LinkedIn banner, corporate modern style, 16:9 aspect ratio, [COLOR SCHEME], clean and trustworthy, subtle pattern" \
  --output ./social-linkedin.png \
  --model gemini-2.5-flash-image
```
**Example:** `professional data visualization background, LinkedIn banner, corporate modern style, 16:9 aspect ratio, blue and gray color scheme, clean and trustworthy, subtle pattern`

### Twitter/X Header
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[VISUAL CONCEPT], Twitter header image, 16:9 aspect ratio, dynamic and modern, [COLOR] gradient, tech aesthetic, eye-catching" \
  --output ./social-twitter.png \
  --model gemini-2.5-flash-image
```

---

## 📐 Diagrams

### System Architecture
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "system architecture diagram showing [COMPONENT 1], [COMPONENT 2], and [COMPONENT 3], use boxes and arrows to show connections, modern tech style, clean lines, blue and white color scheme, horizontal layout" \
  --output ./diagram-architecture.png \
  --model gemini-2.5-flash-image
```
**Example:** `system architecture diagram showing API Gateway, Backend Service, and Database, use boxes and arrows to show connections, modern tech style, clean lines, blue and white color scheme, horizontal layout`

### Flowchart
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "flowchart diagram showing [PROCESS]: [STEP 1] → [STEP 2] → [STEP 3] → [STEP 4], use rounded rectangles and arrows, modern minimalist style, step-by-step flow from left to right" \
  --output ./diagram-flowchart.png \
  --model gemini-2.5-flash-image
```
**Example:** `flowchart diagram showing user signup: Email input → Verification → Profile setup → Dashboard, use rounded rectangles and arrows, modern minimalist style, step-by-step flow from left to right`

### Data Flow
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "data flow visualization showing [SOURCE] → [STAGE 1] → [STAGE 2] → [STAGE 3] → [DESTINATION], use icons and directional arrows, clean tech aesthetic, gradient blue connections, horizontal layout" \
  --output ./diagram-dataflow.png \
  --model gemini-2.5-flash-image
```

---

## 😂 Memes (Work-Appropriate)

### Custom Meme Scene
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[SCENARIO DESCRIPTION], meme format, [THEME] humor, space for text at top and bottom, funny style, simple background" \
  --output ./meme-custom.png \
  --model gemini-2.5-flash-image
```
**Example:** `a cat staring at computer screen looking confused, meme format, tech humor, space for text at top and bottom, funny style, simple background`

### Celebration Meme
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "person celebrating with confetti and fireworks, success meme format, energetic and joyful, space for victory text overlay, vibrant colors, funny style" \
  --output ./meme-celebration.png \
  --model gemini-2.5-flash-image
```

---

## 🏢 Corporate/Team Content

### Feature Announcement
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "modern gradient background from [COLOR 1] to [COLOR 2], feature announcement banner, tech aesthetic, 16:9 aspect ratio, professional and exciting, space for large title text" \
  --output ./team-announcement.png \
  --model gemini-2.5-flash-image
```

### Progress Update Visual
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "abstract progress visualization, showing growth and improvement, modern style, [COLOR] gradient, optimistic and professional, horizontal layout" \
  --output ./team-progress.png \
  --model gemini-2.5-flash-image
```

---

## 🎯 Logo Concepts

### Minimalist Symbol
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "logo for [PRODUCT NAME], [SYMBOL/CONCEPT], minimalist vector style, geometric shapes, simple and clean, [COLOR 1] and [COLOR 2], 1:1 aspect ratio, professional and modern" \
  --output ./logo-concept.png \
  --model gemini-3-pro-image-preview
```
**Example:** `logo for AI assistant app, brain with circuit pattern, minimalist vector style, geometric shapes, simple and clean, blue and white, 1:1 aspect ratio, professional and modern`

### App Icon
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "app icon for [APP PURPOSE], [ICON SYMBOLS], flat design style, rounded square format, gradient [COLOR] to [COLOR], simple and modern, 1:1 aspect ratio" \
  --output ./app-icon.png \
  --model gemini-3-pro-image-preview
```
**Example:** `app icon for productivity tool, checkmark and calendar symbol, flat design style, rounded square format, gradient blue to cyan, simple and modern, 1:1 aspect ratio`

---

## 🎬 Hero Images

### Website Hero
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[SCENE DESCRIPTION], hero image for [PURPOSE], professional photography style, 16:9 aspect ratio, bright and inviting, [LIGHTING], clean aesthetic, space for headline text" \
  --output ./hero-website.png \
  --model gemini-3-pro-image-preview
```
**Example:** `modern workspace with laptop and coffee, hero image for tech startup landing page, professional photography style, 16:9 aspect ratio, bright and inviting, natural lighting, clean aesthetic, space for headline text`

### Event Banner
```bash
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "[VISUAL CONCEPT], hero banner for [EVENT TYPE], modern digital art style, 16:9 aspect ratio, energetic and futuristic, [COLOR] gradient, dynamic composition" \
  --output ./hero-event.png \
  --model gemini-3-pro-image-preview
```

---

## 💡 Tips for Using Templates

1. **Replace brackets:** All `[VARIABLES]` should be replaced with your specific content
2. **Model selection:**
   - `gemini-2.5-flash-image` — Fast, drafts, iterations
   - `gemini-3-pro-image-preview` — High quality, final output
3. **Iterate:** Start with flash, refine prompt, regenerate with pro
4. **Aspect ratios:**
   - 1:1 — Profile pics, Instagram, logos
   - 16:9 — Presentations, YouTube, websites
   - 3:4 / 9:16 — Mobile content, Stories
5. **Color schemes:** Be specific (e.g., "navy blue to sky blue" vs just "blue")
6. **Style keywords matter:** "minimalist", "modern", "professional", "playful" set the tone

---

## 🔄 Quick Iteration Pattern

1. **First pass (flash):**
   ```bash
   python3 skills/nano-banana/scripts/generate_image.py \
     --prompt "[YOUR PROMPT]" \
     --output ./draft.png \
     --model gemini-2.5-flash-image
   ```

2. **Refine prompt based on result**
   - Too busy? Add "minimalist", "clean", "simple"
   - Wrong mood? Add "professional", "playful", "elegant"
   - Wrong colors? Be specific: "gradient navy blue to cyan"

3. **Final pass (pro):**
   ```bash
   python3 skills/nano-banana/scripts/generate_image.py \
     --prompt "[REFINED PROMPT]" \
     --output ./final.png \
     --model gemini-3-pro-image-preview
   ```

---

**Last updated:** 2026-03-05
**See also:** PROMPTING.md (comprehensive guide), SKILL.md (setup), examples.md (more examples)
