# Presentation Prompt Templates

## Base Style (Always Include)

All slides should include this base styling unless overridden:

```
Visual Style: High-end AI SaaS product design aesthetic.
Features: black presentation background (#000000), neon accent colors (purple #a855f7, blue #3b82f6, teal #06b6d4), clean modern UI cards, minimal icons, strong typography hierarchy (Inter/SF Pro style), subtle depth and shadows, Apple keynote / AI startup presentation style.
Rendering: ultra clean layout, perfectly readable text, professional infographic design, balanced spacing, high contrast white text on black, minimal visual clutter.
Output: High-resolution 16:9 presentation slide, premium design quality, presentation ready.
```

## Template 1: SaaS Circular Process Diagram

Use for: process flows, cycles, feedback loops, system architectures

```
Create a premium SaaS-style presentation slide with a circular process diagram.

Composition: 16:9 presentation slide with solid black background (#000000).

Top center contains a clean presentation header:
Small label: {BRAND_NAME}
Large title: {TITLE}
Subtitle below: {SUBTITLE}
Typography: modern tech SaaS style (Inter / SF Pro) with strong hierarchy and generous spacing.

Main Diagram: In the center, a perfect circular process diagram with {N} steps arranged clockwise. Smooth curved arrows forming a continuous loop with subtle neon gradient glow (blue → purple → teal). Looks like a system architecture graphic from a SaaS product keynote.

Step Cards: Floating rounded cards positioned around the circle. Dark UI panels, soft glow edges, subtle glassmorphism, rounded corners, minimal line icons, clean spacing.

{STEPS}

{BASE_STYLE}
```

### Steps Format:
```
Step {N} — {POSITION}:
Title: {STEP_TITLE}
Icon: {ICON_DESCRIPTION}
Caption: {CAPTION_TEXT}
```

Positions for 5 steps: Top, Top Right, Bottom Right, Bottom Left, Top Left
Positions for 4 steps: Top, Right, Bottom, Left
Positions for 3 steps: Top, Bottom Right, Bottom Left

## Template 2: Metrics Dashboard Slide

Use for: KPIs, performance reports, before/after comparisons

```
Create a premium SaaS-style presentation slide showing key metrics.

Composition: 16:9 slide with solid black background (#000000).

Header:
Small label: {BRAND_NAME}
Large title: {TITLE}
Subtitle: {SUBTITLE}

Layout: Grid of {N} metric cards arranged in a clean dashboard layout.

Each metric card shows:
- Large number/percentage in accent color
- Small label below in muted white
- Subtle trend arrow (up green, down red)
- Glassmorphism card with dark background and glow border

Metrics:
{METRICS_LIST}

{BASE_STYLE}
```

### Metrics Format:
```
Card {N}: Value: {VALUE} | Label: {LABEL} | Trend: {up/down/neutral}
```

## Template 3: Architecture / Flow Diagram

Use for: system architecture, data flows, tech stack diagrams

```
Create a premium SaaS-style presentation slide showing a system architecture diagram.

Composition: 16:9 slide with solid black background (#000000).

Header:
Small label: {BRAND_NAME}
Large title: {TITLE}
Subtitle: {SUBTITLE}

Diagram: {FLOW_DIRECTION} flow diagram showing {N} components connected by glowing arrows.

Components:
{COMPONENTS_LIST}

Connections shown as glowing gradient lines (blue → purple → teal) with small arrow indicators.
Each component is a glassmorphism card with icon, title, and brief description.

{BASE_STYLE}
```

## Template 4: Title / Cover Slide

Use for: presentation covers, section dividers

```
Create a premium SaaS-style title slide.

Composition: 16:9 slide with solid black background (#000000).

Center of slide:
Small label above in muted color: {BRAND_NAME}
Very large title: {TITLE}
Subtitle below: {SUBTITLE}
{OPTIONAL: date or presenter name in small text below}

Background: subtle abstract gradient mesh or geometric pattern in very low opacity (purple/blue/teal), barely visible. Clean and minimal.

Typography: bold, modern, centered, with strong hierarchy. Title should be the dominant visual element.

{BASE_STYLE}
```

## Template 5: Comparison / Before-After

Use for: improvement results, A/B test results, before/after metrics

```
Create a premium SaaS-style comparison slide.

Composition: 16:9 slide with solid black background (#000000).

Header:
Small label: {BRAND_NAME}
Large title: {TITLE}
Subtitle: {SUBTITLE}

Layout: Split into two columns — LEFT (Before) and RIGHT (After).

Left column header: {BEFORE_LABEL} (muted/dimmed style)
Right column header: {AFTER_LABEL} (bright accent style)

Comparison items:
{COMPARISON_LIST}

Visual: Left side darker/muted, right side brighter with accent glow. Arrow or transition effect between columns.

{BASE_STYLE}
```

## Usage Notes

- **Always use gemini-3-pro-image-preview** for final slides
- **Always 16:9 aspect ratio**
- **Always enhance** the user's content into these templates
- **Iterate if needed** — generate 2-3 variations, pick best
- **Portuguese text** is fine — Gemini handles pt-BR well
- **Keep text short** — slides should be visual, not walls of text
