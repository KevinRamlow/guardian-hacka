# sheets-export — Google Sheets Export Skill for Billy

Export SQL query results or any tabular data to Google Sheets with one command.

## Quick Start

```bash
# From MySQL query
mysql -e "SELECT * FROM campaigns LIMIT 10" | \
  bash scripts/export-to-sheets.sh --title "Campanhas Ativas"

# From file
bash scripts/export-to-sheets.sh --file data.csv --title "Report"

# From stdin
echo -e "Name\tValue\nTest\t123" | \
  bash scripts/export-to-sheets.sh --title "Test Data"
```

## Files

- `SKILL.md` — Main documentation for Billy agents
- `scripts/export-to-sheets.sh` — Export script (TSV/CSV → Google Sheets)
- `SETUP.md` — One-time OAuth setup instructions
- `README.md` — This file

## How It Works

1. Takes TSV/CSV data from stdin or file
2. Converts to JSON 2D array
3. Creates a new Google Sheet via `gog sheets create`
4. Uploads data via `gog sheets update`
5. Returns shareable URL

## Account

Default: `caio.fonseca@brandlovers.ai`

## Setup Required

Before first use on Billy VM:

```bash
source /root/.openclaw/workspace/.env.gog
gog auth add caio.fonseca@brandlovers.ai --services sheets
```

See `SETUP.md` for details.

## Integration with Other Skills

### data-query → sheets-export
```bash
# Run query, then export
mysql -e "SELECT ..." | bash skills/sheets-export/scripts/export-to-sheets.sh --title "Query Results"
```

### campaign-lookup → sheets-export
```bash
# Get campaign data, export to sheet
mysql -e "SELECT * FROM campaigns WHERE status='active'" | \
  bash skills/sheets-export/scripts/export-to-sheets.sh --title "Active Campaigns"
```

## Example Outputs

**User request:**
> "exporta os dados das campanhas ativas pra uma planilha"

**Billy response:**
> ✅ Planilha criada: **Campanhas Ativas**
>
> 🔗 https://docs.google.com/spreadsheets/d/1a2b3c4d5e6f7g8h9i0j/edit
>
> 📊 47 linhas, 5 colunas (nome, status, conteúdos, aprovação, contestações)
>
> _Fonte: MySQL db-maestro-prod, tabela campaigns_

## Limitations

- Sheets are private by default (need manual sharing via UI)
- No advanced formatting (bold headers, colors) yet
- Max ~10,000 rows for performance
- Requires OAuth setup on Billy VM

## Future Enhancements

- [ ] Auto-share with "anyone with link" permission
- [ ] Advanced formatting (bold headers, freeze rows, column widths)
- [ ] Color coding based on values (red for low approval, green for high)
- [ ] Auto-refresh sheets (link to live data source)
- [ ] Support for multiple tabs
- [ ] Charts and visualizations
