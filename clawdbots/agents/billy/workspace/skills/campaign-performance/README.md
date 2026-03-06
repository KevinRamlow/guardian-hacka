# Campaign Performance Dashboard

**Purpose:** Instant campaign metrics on demand — revenue, engagement, ROI, creator stats, approval rates.

## Quick Start

```bash
# By campaign ID
./campaign-performance.sh --id 501014

# By campaign name (partial match)
./campaign-performance.sh --name "Pantene"

# JSON output
./campaign-performance.sh --id 501014 --format json

# With Google Sheets export
./campaign-performance.sh --id 501014 --export-sheets
```

## Output Example

```
📊 *Dashboard: Pantene - Molecular Bond Repair*
_Marca: Grupo P&G | Pantene_

💰 *REVENUE / GMV*
• Total Pago: R$ 1.403.500,00 (net) | R$ 1.754.380,00 (gross)
• Creators Pagos: 2000
• Pagamento Médio: R$ 701,75
• Status Pagamentos: 2000 completos, 0 parciais, 0 em processo

📈 *ENGAGEMENT*
• Conteúdos: 3204 submetidos
• Aprovação: 15.7% (504 aprovados, 2700 recusados)
• Contestações: 0 (0.0% do total)
• Creators Ativos: 2010

💡 *ROI*
• Budget: R$ 1.754.386,00
• Gasto Real: R$ 1.403.500,00 (70.0% do budget)
• ROI: 70.0%

📊 *vs Média da Plataforma (30d)*
• Aprovação Campanha: 15.7%
• Aprovação Plataforma: 34.9%
• Diferença: -19.2pp ⚠️
```

## Files

- `campaign-performance.sh` — Main script (queries MySQL, formats output)
- `export-sheets.sh` — Google Sheets exporter (4 sheets: summary, revenue, content, creators)
- `SKILL.md` — Detailed documentation
- `README.md` — This file

## Integration with Billy

Billy should trigger this skill when users ask:
- "como está performando a campanha X?"
- "dashboard da campanha Y"
- "números da campanha Z"
- "GMV / ROI / revenue da campanha..."

## Comparison to campaign-lookup

| Skill | Use Case | Data Shown |
|-------|----------|------------|
| `campaign-lookup` | Quick status check | Basic approval rate, submission count |
| `campaign-performance` | Full dashboard | Revenue, ROI, payments, creators, approval vs platform avg |

Use `campaign-lookup` for "how's it going?" — use `campaign-performance` for "I need the full picture."

## Data Sources

- **MySQL** (db-maestro-prod):
  - `campaigns` — Campaign metadata
  - `creator_payment_history` — Revenue/GMV data
  - `proofread_medias` — Content moderation results
  - `proofread_media_contest` — Contest tracking
  - `brands` — Brand names

- **BigQuery** (not yet used, auth pending):
  - Reserved for deeper analytics when available

## Requirements

- MySQL access (configured in ~/.my.cnf)
- `bc` for ROI calculations
- `gog` CLI for Google Sheets export (optional)

## Testing

```bash
# Test with high-volume campaign
./campaign-performance.sh --id 501014

# Test with campaign name
./campaign-performance.sh --name "Pantene"

# Test JSON output
./campaign-performance.sh --id 501014 --format json
```

## Future Enhancements

- [ ] BigQuery integration for moderation trace analysis
- [ ] Historical trends (performance over time)
- [ ] Comparison mode (campaign A vs B)
- [ ] Export to PDF report
- [ ] Scheduled weekly digests
