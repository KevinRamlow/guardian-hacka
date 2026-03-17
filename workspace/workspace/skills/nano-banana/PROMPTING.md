# Prompt Engineering Guide for Nano-Banana (Gemini Image Generation)

**Purpose:** Make image generation consistent, high-quality, and predictable by following proven prompt patterns.

**Audience:** Anton (orchestrator), Caio, and anyone using nano-banana for image generation.

---

## Table of Contents

1. [Prompt Anatomy](#prompt-anatomy)
2. [Style Keywords Library](#style-keywords-library)
3. [Gemini-Specific Behaviors](#gemini-specific-behaviors)
4. [Use Case Patterns](#use-case-patterns)
5. [What Works / What Doesn't](#what-works--what-doesnt)
6. [Quality Checklist](#quality-checklist)

---

## Prompt Anatomy

### Basic Structure

```
[SUBJECT] + [ACTION/CONTEXT] + [STYLE] + [TECHNICAL SPECS] + [MOOD/ATMOSPHERE]
```

### Examples Broken Down

**Example 1: Profile Picture**
```
Subject: "a lobster"
Action: "wearing headphones, working at a laptop"
Style: "pixel art style, 8-bit retro aesthetic"
Technical: "1:1 aspect ratio, centered composition"
Mood: "vibrant colors, playful"

Full prompt: "a lobster wearing headphones, working at a laptop, pixel art style, 8-bit retro aesthetic, 1:1 aspect ratio, centered composition, vibrant colors, playful"
```

**Example 2: Presentation Background**
```
Subject: "abstract geometric shapes"
Context: "presentation slide background"
Style: "modern minimalist design"
Technical: "16:9 aspect ratio, horizontal layout"
Mood: "corporate professional, blue and white color scheme"

Full prompt: "abstract geometric shapes, presentation slide background, modern minimalist design, 16:9 aspect ratio, horizontal layout, corporate professional, blue and white color scheme"
```

### Order of Importance

Gemini Image prioritizes prompt elements in this order:
1. **Subject** (what) — The main focus
2. **Action/Context** (doing what) — Activity or setting
3. **Style** (how) — Visual aesthetic
4. **Technical** (format) — Aspect ratio, composition
5. **Mood** (feel) — Emotional tone, atmosphere

**Tip:** Put the most important details FIRST in your prompt.

---

## Style Keywords Library

### Visual Styles

#### Digital Art
- `digital art` — Generic digital illustration
- `vector art` — Clean, scalable shapes
- `flat design` — No shadows, simple shapes
- `geometric abstract` — Shapes and patterns
- `gradient art` — Smooth color transitions
- `isometric design` — 3D-looking but flat
- `low poly` — Faceted, geometric 3D
- `voxel art` — Minecraft-like blocks

#### Retro & Pixel
- `8-bit pixel art` — Classic NES/Game Boy style
- `16-bit pixel art` — SNES/Genesis style
- `pixel art` — General retro game aesthetic
- `retro wave` — 80s neon aesthetic
- `synthwave` — Neon grids, purple/pink
- `vaporwave` — Pastel colors, glitch aesthetic

#### Photography Styles
- `professional photography` — Realistic, high-quality
- `portrait photography` — Focused on subject
- `product photography` — Clean, commercial
- `macro photography` — Extreme close-up
- `aerial view` — Top-down perspective
- `cinematic lighting` — Movie-like lighting
- `golden hour lighting` — Warm, sunset glow
- `studio lighting` — Professional setup

#### Illustration Styles
- `minimalist illustration` — Simple, few elements
- `line art` — Outlines only
- `watercolor` — Soft, painted look
- `ink drawing` — Bold black lines
- `comic book style` — Bold outlines, halftone
- `manga style` — Japanese comic aesthetic
- `children's book illustration` — Whimsical, simple
- `technical illustration` — Precise, educational

#### 3D & Realistic
- `3D render` — Computer-generated 3D
- `photorealistic` — Looks like a photo
- `hyperrealistic` — Ultra-detailed realism
- `octane render` — High-quality 3D rendering
- `unreal engine` — Game engine quality
- `blender render` — 3D software aesthetic

#### Abstract & Artistic
- `abstract` — Non-representational
- `surrealism` — Dream-like, impossible
- `cubism` — Geometric, fragmented
- `impressionism` — Painterly, loose brushstrokes
- `pop art` — Bold colors, commercial
- `art deco` — Geometric, luxurious
- `bauhaus` — Functional, geometric
- `glitch art` — Digital corruption aesthetic

### Color & Mood Keywords

#### Color Schemes
- `monochrome` — Single color shades
- `black and white` — No color
- `vibrant colors` — Saturated, bold
- `pastel colors` — Soft, light tones
- `muted colors` — Desaturated, subdued
- `neon colors` — Bright, glowing
- `warm colors` — Red, orange, yellow
- `cool colors` — Blue, green, purple
- `gradient [color] to [color]` — Smooth transition

#### Mood & Atmosphere
- `professional` — Business-appropriate
- `playful` — Fun, energetic
- `elegant` — Refined, sophisticated
- `dramatic` — High contrast, intense
- `calm` — Peaceful, serene
- `energetic` — Dynamic, active
- `mysterious` — Dark, enigmatic
- `cheerful` — Happy, bright
- `minimalist` — Simple, clean
- `maximalist` — Busy, complex

### Technical Specifications

#### Composition
- `centered composition` — Subject in center
- `rule of thirds` — Balanced off-center
- `symmetrical` — Mirrored layout
- `negative space` — Lots of empty area
- `tight crop` — Close-up on subject
- `wide shot` — Full scene visible
- `top-down view` — Overhead perspective
- `side view` — Profile angle
- `isometric view` — 45° angle, no perspective

#### Quality Descriptors
- `high quality` — General quality boost
- `detailed` — Intricate, complex
- `sharp focus` — Crisp, clear
- `soft focus` — Slightly blurred
- `clean` — No clutter
- `polished` — Refined, finished
- `professional` — High-end quality

#### Format Hints (for Gemini)
- `16:9 aspect ratio` — Widescreen
- `1:1 aspect ratio` — Square
- `9:16 aspect ratio` — Vertical mobile
- `4:3 aspect ratio` — Classic monitor
- `3:4 aspect ratio` — Portrait
- `horizontal layout` — Wide orientation
- `vertical layout` — Tall orientation

---

## Advanced: Vertex AI Parameters

### ⭐ OPTIMAL SETTINGS (Always Use These)

**Temperature:** 0.5
- Best balance of creativity and accuracy to prompt
- Model performs significantly better with temp 0.5
- More accurate adherence to prompt instructions

**Resolution:** 4K (outputOptions.imageSize)
- Highest quality output
- Better detail and clarity
- Use unless user explicitly needs lower resolution

**Prompt Enhancement:** ALWAYS ON
- Use your skills to improve user prompts before generating
- Add detail, specify style, enhance clarity
- Better prompt = better output
- Never pass through raw user prompts unchanged

---

When using the Python wrapper (`scripts/generate_image.py`) or Vertex AI API directly, you can control generation with these parameters:

### Prompt Enhancement
- **`enhancePrompt`** (boolean, default: true)
  - Uses LLM-based prompt rewriting to improve quality
  - Delivers higher quality images that better reflect intent
  - Disable only if you need exact prompt control
  - **Recommendation:** Keep enabled for best results

### Person/Face Control
- **`personGeneration`** (string)
  - `allow_all` — Generate people including minors (Imagen 4 default)
  - `allow_adult` — Adults only, including celebrities (most models default)
  - `dont_allow` — No people or faces in images
  - **Use case:** Profile pics → `dont_allow`, Product shots → `dont_allow`, Social content → `allow_adult`

### Safety Settings
- **`safetySetting`** (string)
  - `block_low_and_above` — Strictest filtering (most images blocked)
  - `block_medium_and_above` — Balanced (default)
  - `block_only_high` — Minimal filtering (may increase objectionable content)
  - **Recommendation:** Use default unless you have specific needs

### Deterministic Output
- **`seed`** (integer, 1-2147483647)
  - Same seed + same prompt = same output image
  - **Requires:** `addWatermark: false` to work
  - **Use case:** A/B testing, reproducible results, iterative refinement

### Watermarking
- **`addWatermark`** (boolean, default: true)
  - Embeds invisible SynthID digital watermark
  - Verifiable provenance for AI-generated content
  - **Must disable** to use `seed` parameter
  - **Recommendation:** Keep enabled for public/commercial use

### Output Format
- **`aspectRatio`**: `"1:1"` | `"3:4"` | `"4:3"` | `"16:9"` | `"9:16"`
  - 1:1 — Square (default), social media, profile pics
  - 3:4 — Portrait, ads, social media
  - 4:3 — Landscape, TV, photography
  - 16:9 — Widescreen, presentations, YouTube
  - 9:16 — Vertical mobile, Stories, TikTok

- **`mimeType`**: `"image/jpeg"` | `"image/png"` | `"image/webp"`
  - JPEG — Smaller files, good for photos
  - PNG — Lossless, supports transparency
  - WebP — Modern format, smaller than PNG

- **`compressionQuality`** (0-100, default: 75, JPEG only)
  - Higher = better quality, larger file
  - 75-85 recommended for most use cases
  - 90+ for print quality

### Example with Advanced Parameters

```python
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "professional headshot, business executive" \
  --output ./headshot.jpg \
  --model gemini-3-pro-image-preview \
  --aspect-ratio 3:4 \
  --person-generation allow_adult \
  --safety-setting block_medium_and_above \
  --enhance-prompt true
```

## Gemini-Specific Behaviors

### ✅ What Gemini Does Well

1. **Abstract & Geometric Designs**
   - Excellent at patterns, shapes, gradients
   - Perfect for backgrounds, presentations
   - Clean, modern aesthetic

2. **Illustration Styles**
   - Digital art, vector art, flat design
   - Character concepts (when simple)
   - Icon design, logo concepts

3. **Text-Free Compositions**
   - Works best without text overlay
   - Generate image first, add text later

4. **Color Control**
   - Good at following color schemes
   - Responds well to specific color names
   - Handles gradients reliably

5. **Aspect Ratio Adherence**
   - Respects aspect ratio parameters
   - Good for platform-specific formats

### ❌ What Gemini Struggles With

1. **Text in Images**
   - Text often garbled or misspelled
   - Use external tools for text overlay
   - Exception: Sometimes single words work

2. **Complex Human Faces**
   - Photorealistic portraits can be inconsistent
   - Stylized/illustrated faces work better
   - Avoid close-up facial details

3. **Precise Object Counts**
   - "Exactly 5 apples" might give 4 or 6
   - Use "several" or "a few" instead
   - Don't rely on exact quantities

4. **Brand Logo Recreation**
   - Can't perfectly replicate existing brands
   - Good for "inspired by" or original concepts
   - Avoid trademarked imagery requests

5. **Extremely Detailed Scenes**
   - Very complex scenes may lose coherence
   - Break into multiple simpler images
   - Focus on 1-3 main elements

### Gemini vs. Midjourney vs. DALL-E

| Feature | Gemini Image | Midjourney | DALL-E 3 |
|---------|--------------|------------|----------|
| **Best for** | Abstract, geometric, illustrations | Artistic, stylized imagery | Photorealism, text rendering |
| **Text in image** | ❌ Poor | ❌ Poor | ✅ Good |
| **Style flexibility** | ✅ Good | ✅ Excellent | ✅ Good |
| **Speed** | ✅ Fast (flash model) | ⚠️ Medium | ⚠️ Medium |
| **Aspect ratios** | ✅ Multiple options | ✅ Multiple options | ⚠️ Limited |
| **Consistency** | ✅ Good | ✅ Very good | ✅ Good |
| **Price** | ✅ Affordable | 💰 Expensive | 💰 Moderate |

---

## Use Case Patterns

### 1. Profile Pictures

**Goal:** Recognizable, visually distinct, appropriate aspect ratio (1:1)

**Pattern:**
```
[CHARACTER/MASCOT] + [ACTIVITY/POSE] + [STYLE] + "1:1 aspect ratio, centered composition" + [MOOD]
```

**Examples:**

```
"a lobster wearing headphones working at a laptop, pixel art style, 8-bit retro aesthetic, 1:1 aspect ratio, centered composition, vibrant colors, playful"
```

```
"a robot mascot holding a clipboard, minimalist flat design, geometric shapes, 1:1 aspect ratio, centered composition, blue and white color scheme, professional"
```

```
"a stylized brain with circuit patterns, modern tech aesthetic, gradient blue to purple, 1:1 aspect ratio, centered composition, clean and futuristic"
```

**Tips:**
- Use stylized/illustrated characters (not photorealistic)
- Specify centering for profile picture framing
- Vibrant colors stand out in small thumbnails
- Avoid complex backgrounds (keep it simple)

---

### 2. Presentation Backgrounds

**Goal:** Professional, non-distracting, space for text overlay

**Pattern:**
```
[ABSTRACT ELEMENT] + "presentation background" + [STYLE] + "16:9 aspect ratio" + [COLOR SCHEME] + "space for text"
```

**Examples:**

```
"abstract geometric shapes, presentation slide background, modern minimalist design, 16:9 aspect ratio, corporate blue and white gradient, space for centered text"
```

```
"flowing wave patterns, presentation background, elegant professional style, 16:9 aspect ratio, purple to blue gradient, subtle and clean"
```

```
"circuit board pattern in background, tech presentation slide, modern digital aesthetic, 16:9 aspect ratio, dark theme with neon blue accents, space for title text at top"
```

**Tips:**
- Keep backgrounds subtle (text must be readable)
- Use "space for text" to reduce clutter in key areas
- Gradients work well for depth without distraction
- Test readability: white text on dark bg, or inverse

---

### 3. Social Media Posts

**Goal:** Eye-catching, platform-appropriate format, brand-consistent

**Pattern:**
```
[MAIN VISUAL] + "social media post for [PLATFORM]" + [ASPECT RATIO] + [STYLE] + [MOOD] + [COLOR SCHEME]
```

**Examples:**

**Instagram (1:1):**
```
"modern gradient background from blue to purple, Instagram post announcing new AI feature, 1:1 aspect ratio, minimalist tech style, space for text overlay in center, vibrant and energetic"
```

**LinkedIn (1:1 or 16:9):**
```
"professional data visualization background, LinkedIn post about productivity tips, 16:9 aspect ratio, corporate modern style, blue and gray color scheme, clean and trustworthy"
```

**Twitter/X (16:9):**
```
"tech-themed abstract background, Twitter post header image, 16:9 aspect ratio, dynamic geometric shapes, gradient colors, modern and eye-catching"
```

**Tips:**
- Match aspect ratio to platform guidelines
- Instagram: 1:1 (square) or 4:5 (portrait)
- Twitter: 16:9 (landscape)
- LinkedIn: 1:1 or 1.91:1
- Leave space for text (don't fill entire image)

---

### 4. Diagrams & Technical Visuals

**Goal:** Clear, informative, easy to understand

**Pattern:**
```
[DIAGRAM TYPE] + "showing [COMPONENTS]" + "use [VISUAL ELEMENTS]" + [STYLE] + [LAYOUT]
```

**Examples:**

**System Architecture:**
```
"system architecture diagram showing API Gateway, Backend Service, and Database, use boxes and arrows to show connections, modern tech style, clean lines, blue and white color scheme, horizontal layout"
```

**Flowchart:**
```
"flowchart diagram showing user signup process: Email input, Verification, Profile setup, Dashboard, use rounded rectangles and arrows, modern minimalist style, step-by-step flow from left to right"
```

**Data Flow:**
```
"data flow visualization showing User → Frontend → API → Database → Cache, use icons and directional arrows, clean tech aesthetic, gradient blue connections, horizontal layout"
```

**Tips:**
- Gemini struggles with complex diagrams — keep it simple
- Use clear labels in prompt (Gemini may not render text well)
- Consider generating shapes only, add text externally
- "boxes and arrows" language works well
- Horizontal layouts often clearer than vertical

---

### 5. Memes & Humor

**Goal:** Funny, relatable, work-appropriate

**Pattern:**
```
[MEME FORMAT] + "meme template" + [CONTEXT/THEME] + "spaces for text" + [STYLE]
```

**Examples:**

**Original Memes:**
```
"a cat staring at a computer screen looking confused, meme format, tech humor theme, space for text at top and bottom, funny style, simple background"
```

**Meme Templates:**
```
"distracted boyfriend meme format showing person looking at different tech stacks, three characters in scene, spaces for labels, clean background, meme aesthetic"
```

**Celebration Memes:**
```
"person celebrating with confetti and fireworks, success meme format, energetic and joyful, space for victory text overlay, vibrant colors"
```

**Tips:**
- "meme format" helps Gemini understand the goal
- Leave obvious space for text (top/bottom or labeled areas)
- Simple, relatable scenarios work best
- Avoid copyrighted characters — original creations only
- Test for work-appropriateness before sharing

---

### 6. Logos & Branding

**Goal:** Recognizable, scalable, memorable

**Pattern:**
```
"logo for [BRAND/PRODUCT]" + [CONCEPT] + [STYLE] + "simple and clean" + [COLOR SCHEME] + "1:1 aspect ratio"
```

**Examples:**

**Tech Startup:**
```
"logo for AI assistant app named CaioBot, lobster mascot concept, minimalist vector style, geometric shapes, simple and clean, blue and white, 1:1 aspect ratio, professional"
```

**App Icon:**
```
"app icon for productivity tool, checkmark and calendar symbol, flat design style, rounded square format, gradient blue to cyan, simple and modern, 1:1 aspect ratio"
```

**Wordmark Concept:**
```
"abstract symbol forming the letter G, modern tech logo, geometric vector design, single color blue, minimalist and scalable, 1:1 aspect ratio"
```

**Tips:**
- "minimalist" and "simple" prevent over-complication
- Vector style tends to be cleaner than illustrated
- Single or two-color schemes scale better
- Generate multiple variations, then refine
- Avoid text in logo (Gemini's weakness) — add externally

---

### 7. Hero Images & Banners

**Goal:** Engaging, visually striking, professional

**Pattern:**
```
[SCENE/CONCEPT] + "hero image for [PURPOSE]" + [STYLE] + [ASPECT RATIO] + [MOOD] + [COLOR SCHEME]
```

**Examples:**

**Website Hero:**
```
"modern workspace with laptop and coffee, hero image for tech startup landing page, professional photography style, 16:9 aspect ratio, bright and inviting, natural lighting, clean aesthetic"
```

**Event Banner:**
```
"abstract network connections and data flow, hero banner for tech conference, modern digital art style, 16:9 aspect ratio, energetic and futuristic, blue and purple gradient"
```

**Product Launch:**
```
"celebration scene with confetti and light rays, hero image for product launch announcement, vibrant and exciting, 16:9 aspect ratio, dynamic composition, colorful and joyful"
```

**Tips:**
- Use 16:9 for web heroes, 3:1 for banners
- "hero image" tells Gemini it's primary focus
- Photography style works for realistic scenes
- Abstract works for tech/modern brands
- Leave room for text overlay (often center or left-aligned)

---

## What Works / What Doesn't

### ✅ Patterns That Work Reliably

1. **Abstract Backgrounds**
   ```
   "abstract geometric pattern, blue and white gradient, modern minimalist"
   → Consistent, high quality
   ```

2. **Simple Character Concepts**
   ```
   "a robot mascot holding a wrench, flat design style, blue color"
   → Works well for icons, avatars
   ```

3. **Style + Color + Mood Combos**
   ```
   "pixel art style, vibrant colors, playful mood"
   → Clear direction, good results
   ```

4. **Technical Diagrams (Simple)**
   ```
   "3 boxes connected by arrows, horizontal layout, modern style"
   → Clean, usable diagrams
   ```

5. **Specific Aspect Ratios**
   ```
   "16:9 aspect ratio, horizontal layout"
   → Gemini respects format requests
   ```

### ❌ Patterns That Don't Work Well

1. **Text Rendering**
   ```
   ❌ "image with text saying 'Welcome to CaioBot'"
   → Text will be garbled
   ✅ Generate image, add text externally
   ```

2. **Exact Counts**
   ```
   ❌ "exactly 7 stars arranged in a circle"
   → Might get 6 or 8
   ✅ "several stars arranged in a circle"
   ```

3. **Complex Human Faces**
   ```
   ❌ "photorealistic portrait of a business executive"
   → Uncanny valley, inconsistent
   ✅ "stylized illustration of a professional person"
   ```

4. **Trademarked Logos**
   ```
   ❌ "Apple logo on a laptop"
   → Can't reproduce brands
   ✅ "generic laptop with minimalist design"
   ```

5. **Overly Complex Scenes**
   ```
   ❌ "bustling city street with cars, people, buildings, signs, trees, and a sunset"
   → Too much, loses coherence
   ✅ "city skyline at sunset, modern architecture"
   ```

6. **Negative Prompting**
   ```
   ❌ "a forest WITHOUT any animals"
   → Gemini doesn't reliably handle negatives
   ✅ Just describe what you want, not what to avoid
   ```

---

## Quality Checklist

Before finalizing a prompt, check:

### Clarity
- [ ] Is the subject clearly defined?
- [ ] Is the style explicitly mentioned?
- [ ] Are technical specs (aspect ratio) included?

### Specificity
- [ ] Have I specified colors if they matter?
- [ ] Have I included mood/atmosphere keywords?
- [ ] Is the use case clear (profile pic, presentation, etc.)?

### Gemini Compatibility
- [ ] Am I avoiding text in the image?
- [ ] Am I keeping the scene simple (1-3 main elements)?
- [ ] Have I used positive language (what to include, not exclude)?

### Format
- [ ] Does the aspect ratio match the intended use?
- [ ] Have I specified composition (centered, horizontal, etc.)?
- [ ] Is there space for text overlay if needed?

### Iteration Strategy
- [ ] Start with flash model (`gemini-2.5-flash-image`) for testing
- [ ] Refine prompt based on result
- [ ] Use pro model (`gemini-3-pro-image-preview`) for final output

---

## Examples by Category

### Minimalist Style

```
"abstract wave pattern, minimalist design, single color gradient from white to light blue, clean and simple, 16:9 aspect ratio, presentation background"
```

```
"simple lobster icon, minimalist line art style, single color navy blue, 1:1 aspect ratio, centered composition, clean and modern"
```

### Pixel Art / 8-bit

```
"a robot character waving, 8-bit pixel art style, retro gaming aesthetic, vibrant primary colors, 1:1 aspect ratio, centered, nostalgic vibe"
```

```
"cityscape skyline at night, 16-bit pixel art, neon lights, purple and blue color palette, horizontal layout, retro futuristic"
```

### Professional / Corporate

```
"abstract data visualization background, professional corporate style, blue and gray gradient, modern and clean, 16:9 aspect ratio, space for text"
```

```
"handshake silhouette with network connections, professional business illustration, minimal color palette, trustworthy and elegant"
```

### Playful / Vibrant

```
"colorful geometric shapes dancing, playful abstract art, vibrant rainbow colors, energetic and joyful, 1:1 aspect ratio, fun vibe"
```

```
"smiling sun character, cheerful illustration style, bright yellow and orange, playful and friendly, simple background"
```

### Tech / Futuristic

```
"circuit board pattern with glowing pathways, tech aesthetic, dark background with neon blue traces, futuristic and modern, horizontal layout"
```

```
"holographic data streams flowing, cyberpunk tech style, purple and cyan neon colors, dynamic and futuristic, abstract composition"
```

---

## Quick Reference: Common Tasks

### Need a profile pic?
```
[CHARACTER] + [ACTIVITY] + [STYLE: pixel art / minimalist / illustration] + "1:1 aspect ratio, centered, vibrant colors"
```

### Need a presentation background?
```
"abstract [ELEMENT] + presentation background + [STYLE: modern / minimalist / corporate] + 16:9 aspect ratio + [COLOR SCHEME] + space for text"
```

### Need a social media post?
```
[CONCEPT] + "[PLATFORM] post" + [ASPECT RATIO: 1:1 for IG, 16:9 for Twitter] + [STYLE] + [MOOD] + space for text overlay
```

### Need a diagram?
```
"[DIAGRAM TYPE] showing [COMPONENTS], use boxes and arrows, modern style, [LAYOUT: horizontal / vertical], clean and simple"
```

### Need a meme?
```
"[SCENARIO] + meme format + [THEME] + spaces for text + funny style + simple background"
```

### Need a logo concept?
```
"logo for [PRODUCT/BRAND] + [CONCEPT/SYMBOL] + minimalist vector style + simple and clean + [1-2 COLORS] + 1:1 aspect ratio"
```

---

## Advanced Tips

### Model Selection Strategy

1. **Draft Phase:** `gemini-2.5-flash-image`
   - Fast iterations
   - Test prompt variations
   - Explore style options

2. **Final Phase:** `gemini-3-pro-image-preview`
   - Highest quality
   - Production-ready output
   - Worth the extra generation time

### Iterative Refinement

If first result isn't perfect:

1. **Too vague?** → Add style keywords
   ```
   Before: "a workspace"
   After: "a modern workspace, minimalist design, natural lighting, professional photography style"
   ```

2. **Wrong mood?** → Add atmosphere descriptors
   ```
   Before: "a robot"
   After: "a friendly robot, playful and cheerful, vibrant colors, welcoming vibe"
   ```

3. **Composition off?** → Specify layout
   ```
   Before: "geometric shapes"
   After: "geometric shapes, centered composition, symmetrical layout, balanced"
   ```

4. **Colors wrong?** → Be explicit
   ```
   Before: "colorful background"
   After: "gradient background from navy blue to sky blue, smooth transition"
   ```

### Using Reference Images

When you have an example of the style you want:

1. Generate base image with detailed prompt
2. Use `edit_image` with reference + modifications
3. Iterate until style matches

**Example:**
```bash
# First: Generate base
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "abstract tech background, modern style" \
  --output ./base.png

# Then: Edit with reference
mcporter call nano-banana edit_image --params '{
  "prompt": "make this match the style of [reference image], but use blue colors",
  "images": ["./base.png", "./reference.png"]
}'
```

### Combining Multiple Images

For presentations or social posts with multiple visual elements:

1. Generate each element separately
2. Composite in external tool (Figma, Canva, Photoshop)
3. Advantages: precise control, better quality per element

---

## Common Mistakes to Avoid

1. **Too many details in one prompt**
   - ❌ Long paragraph describing every tiny element
   - ✅ Focus on 3-5 key attributes

2. **Expecting perfect text**
   - ❌ "create logo with company name spelled correctly"
   - ✅ Generate logo symbol, add text externally

3. **Not specifying aspect ratio**
   - ❌ Leaving format to chance
   - ✅ Always include aspect ratio for intended use

4. **Vague style descriptions**
   - ❌ "make it look good"
   - ✅ "minimalist modern style, clean lines, professional"

5. **Forgetting color scheme**
   - ❌ Letting Gemini choose randomly
   - ✅ Specify colors when brand consistency matters

6. **Using the wrong model**
   - ❌ Using pro model for all tests (slow, expensive)
   - ✅ Flash for iteration, pro for final

---

## Conclusion

**Key Takeaways:**

1. **Structure matters:** Subject + Action + Style + Technical + Mood
2. **Be specific:** Vague prompts = unpredictable results
3. **Know Gemini's strengths:** Abstract, geometric, illustrations > text, faces, exact counts
4. **Iterate smart:** Flash model for testing, pro model for final
5. **Match the use case:** Profile pics, presentations, diagrams each have patterns
6. **Add text externally:** Don't rely on Gemini for text rendering

**When in doubt:**
- Start simple, add detail incrementally
- Reference this guide's patterns for your use case
- Test with flash model first
- Refine prompt based on what you see
- Finalize with pro model when satisfied

---

**Last updated:** 2026-03-05 by Anton (subagent)
**Related docs:** SKILL.md, examples.md, README.md
