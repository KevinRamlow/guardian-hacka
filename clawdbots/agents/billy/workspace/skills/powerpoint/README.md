# Billy Presentation Generator - Quick Start

## ✅ DEPLOYED & READY
**Location:** `/root/.openclaw/workspace/skills/powerpoint/`  
**Billy VM:** 89.167.64.183  
**Status:** Tested & working

## How to Use

### 1. Prepare data (JSON format)
```json
{
  "campaign_name": "Nome da Campanha",
  "period": "Última semana",
  "metrics": [
    {"label": "Total de Conteúdos", "value": "1,234", "delta": "+12%"},
    {"label": "Taxa de Aprovação", "value": "87.5%", "delta": "+2.3pp"}
  ],
  "daily_highlights": ["Highlight 1", "Highlight 2"],
  "top_refusals": ["Motivo 1", "Motivo 2"],
  "next_steps": ["Ação 1", "Ação 2"]
}
```

### 2. Generate presentation
```bash
python /root/.openclaw/workspace/skills/powerpoint/generate.py \
  --template campaign-report \
  --data data.json \
  --output report.md
```

### 3. Output
- **Markdown file** with formatted sections
- **Images** (nano-banana charts) in same directory
- Clean, shareable format

## Available Templates
- `campaign-report` — Campaign performance report
- `weekly-digest` — Weekly summary  
- `brand-review` — Brand performance review
- `executive-summary` — Platform-wide summary

## What Billy Returns
```
Apresentação gerada: /path/to/report.md
[Markdown content with sections and embedded charts]
```

## Example Output
```markdown
# 📊 Relatório: Campanha X
**Período:** Última semana

## 📈 Métricas Principais
- **Total de Conteúdos:** 1,234 +12%
- **Taxa de Aprovação:** 87.5% +2.3pp

![Métricas](metrics_chart.png)
```

## Next: Google Slides API
Future enhancement will create actual Google Slides presentations with shareable URLs.  
Current solution unblocks immediate needs.

## Dependencies
- `nano-banana` skill (for chart generation)
- Python 3.x
- Gemini API key (for nano-banana)

## Test Run
```bash
# Test on Billy VM
ssh root@89.167.64.183
cd /root/.openclaw/workspace/skills/powerpoint
python3 generate.py --template campaign-report --data /tmp/test_pres_data.json --output /tmp/test.md
```

**Status:** ✅ All tests passing on Billy VM
