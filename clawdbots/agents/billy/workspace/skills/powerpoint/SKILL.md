# Presentation Generator (Markdown + Images)

Generate polished presentation content as markdown + nano-banana images.

**Output format:**
- ✅ Markdown text with formatted sections
- ✅ nano-banana generated charts/images
- ✅ Clean, shareable format
- 📝 Google Slides integration = future enhancement

## Dependencies
- `nano-banana` skill — Image/chart generation via Gemini

## Usage

```bash
python generate.py --template <template> --data <data.json> --output <output.md>
```

**Templates:**
- `campaign-report` — Campaign performance report
- `weekly-digest` — Weekly summary
- `brand-review` — Brand performance review
- `executive-summary` — Platform-wide executive summary

## Workflow

When asked to create a presentation:

1. **Gather data** — Run queries (data-query, campaign-lookup)
2. **Format as JSON** — Structure data according to template
3. **Generate** — Run generate.py with template + data
4. **Share** — Return markdown content (images auto-generated)

## Templates

### campaign-report
- Title + campaign name + date range
- Key metrics (total content, approval rate, contest rate)
- Daily volume highlights
- Top refusal reasons
- Recommendations / next steps
- **Chart:** Metrics bar chart (nano-banana)

### weekly-digest
- Title + week range
- Overall KPIs vs previous week
- Top 5 campaigns by volume
- Highlights & action items
- **Chart:** Top campaigns bar chart (nano-banana)

### brand-review
- Title + brand name
- Active campaigns overview
- Performance per campaign
- Contest analysis
- Recommendations

### executive-summary
- Title + period
- Platform-wide KPIs
- Month-over-month trends
- Top performing brands/campaigns
- Risks & opportunities

## Data Format

```json
{
  "campaign_name": "Nome da Campanha",
  "period": "Última semana",
  "metrics": [
    {"label": "Total de Conteúdos", "value": "1,234", "delta": "+12%"},
    {"label": "Taxa de Aprovação", "value": "87.5%", "delta": "+2.3pp"}
  ],
  "daily_highlights": ["Item 1", "Item 2"],
  "top_refusals": ["Motivo 1", "Motivo 2"],
  "next_steps": ["Ação 1", "Ação 2"]
}
```

## Brand Colors
- Primary: #6C2BD9 (purple)
- Secondary: #FF6B35 (orange)
- Background: #FFFFFF
- Text: #1A1A2E
- Accent: #16C79A (green)

## Output Example

```markdown
# 📊 Relatório: Campanha X
**Período:** Última semana

## 📈 Métricas Principais
- **Total de Conteúdos:** 1,234 +12%
- **Taxa de Aprovação:** 87.5% +2.3pp

![Métricas](metrics_chart.png)

## 📅 Tendência Diária
- Volume diário estável
- Pico na segunda-feira
```

## Future: Google Slides API
Google Slides integration planned for automated slide deck creation with shareable URLs.
