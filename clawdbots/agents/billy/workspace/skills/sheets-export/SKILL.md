# Google Sheets Export — Export Query Results to Shareable Sheets

Export SQL query results or any tabular data to Google Sheets with auto-formatting and shareable links.

## When to Use
- User asks to export data: "exporta isso pra uma planilha"
- User wants to share results: "manda essa tabela pro Google Sheets"
- User needs formatted data visualization
- Any data query that would benefit from spreadsheet format

## Flow

1. **Get the data** — Run query via data-query skill or other source
2. **Format as TSV/CSV** — Convert results to tabular format
3. **Create Sheet** — Use `export-to-sheets.sh` to create Google Sheet
4. **Return link** — Share the shareable URL with user

## Usage

### From query results (pipe from mysql/bq):
```bash
mysql -e "SELECT * FROM campaigns LIMIT 10" | \
  bash scripts/export-to-sheets.sh --title "Campanhas Ativas"
```

### From TSV/CSV file:
```bash
bash scripts/export-to-sheets.sh \
  --file data.tsv \
  --title "Relatório de Performance"
```

### From stdin (any format):
```bash
echo -e "Nome\tStatus\nCampanha 1\tAtiva\nCampanha 2\tPausada" | \
  bash scripts/export-to-sheets.sh --title "Campanhas"
```

## Output

Returns a shareable Google Sheets URL:
```
✅ Sheet created: Campanhas Ativas
🔗 https://docs.google.com/spreadsheets/d/1a2b3c4d5e6f7g8h9i0j/edit
```

## Features

- ✅ Auto-creates new Google Sheet
- ✅ Auto-formats headers (bold, frozen first row)
- ✅ Sets column widths based on content
- ✅ Makes shareable with link (anyone with link can view)
- ✅ Returns direct URL
- ✅ Supports TSV, CSV, or pipe-delimited input
- ✅ Handles up to 10,000 rows efficiently

## Common Use Cases

### Export campaign data:
```bash
mysql -e "
SELECT c.name AS campanha, c.status,
       COUNT(a.id) AS conteudos
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
WHERE c.status = 'active'
GROUP BY c.id
ORDER BY conteudos DESC
LIMIT 50
" | bash scripts/export-to-sheets.sh --title "Campanhas Ativas"
```

### Export moderation results:
```bash
mysql -e "
SELECT DATE(created_at) AS data,
       COUNT(*) AS total,
       SUM(is_approved = 1) AS aprovados,
       ROUND(SUM(is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at)
ORDER BY data DESC
" | bash scripts/export-to-sheets.sh --title "Moderação - Últimos 30 dias"
```

### Export creator lists:
```bash
mysql -e "
SELECT creator_name, campaign_name,
       COUNT(*) AS conteudos_enviados,
       SUM(is_approved = 1) AS aprovados
FROM proofread_medias pm
JOIN actions a ON a.id = pm.action_id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY creator_name, campaign_name
ORDER BY conteudos_enviados DESC
LIMIT 100
" | bash scripts/export-to-sheets.sh --title "Top Creators - Última Semana"
```

## Response Format

When exporting for users, respond with:
1. **Confirmation** — "Planilha criada!"
2. **Sheet title** — What the sheet contains
3. **Link** — Direct shareable URL
4. **Context** — Row count, columns, data source

Example:
> ✅ Planilha criada: **Moderação - Últimos 30 dias**
>
> 🔗 https://docs.google.com/spreadsheets/d/1a2b3c4d5e6f7g8h9i0j/edit
>
> 📊 30 linhas, 4 colunas (data, total, aprovados, taxa_aprovação)
>
> _Fonte: MySQL db-maestro-prod, tabela proofread_medias_

## Permissions

- Creates sheets with **view access** for anyone with the link
- Owner: caio.fonseca@brandlovrs.com (work account)
- Can be shared directly with specific users if needed

## Safety

- READ ONLY source data (never modifies database)
- Sheets are private by default (shareable link only)
- Masks PII in sheet titles
- Warns before exporting >1000 rows
- Supports data sampling for large exports

## Account

Default account: `caio.fonseca@brandlovers.ai`

Override with `--account` flag if needed. The script sources `/root/.openclaw/workspace/.env.gog` for authentication.
