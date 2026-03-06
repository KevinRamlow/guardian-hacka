# Campaign Performance Dashboard

Instant campaign metrics on demand — revenue, engagement, ROI, creator stats, and approval rates.

## When to Use
- "como está performando a campanha X?"
- "quero ver os números da campanha Y"
- "dashboard da campanha Z"
- "performance report campanha..."
- "GMV da campanha..."
- "ROI da campanha..."

## What It Shows

**Core Metrics:**
1. **Revenue/GMV** — Total creator payments (net + gross)
2. **Engagement** — Content count, creator count, approval rate
3. **ROI** — Revenue efficiency (payments / budget × 100)
4. **Creator Stats** — Total creators, avg payment, payment completion rate
5. **Content Stats** — Submissions, approved, refused, approval rate
6. **Approval Rate** — Compared to platform average (last 30d)

## Usage

```bash
# By campaign ID
./campaign-performance.sh --id 1234

# By campaign name (partial match)
./campaign-performance.sh --name "Summer Vibes"

# With Google Sheets export
./campaign-performance.sh --id 1234 --export-sheets

# JSON output (for API/automation)
./campaign-performance.sh --id 1234 --format json
```

## Query Details

### Revenue Query (MySQL)
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  c.budget,
  COUNT(DISTINCT cph.id) AS total_payments,
  COUNT(DISTINCT cph.creator_id) AS paid_creators,
  ROUND(SUM(cph.value), 2) AS total_revenue_net,
  ROUND(SUM(cph.gross_value), 2) AS total_revenue_gross,
  ROUND(AVG(cph.value), 2) AS avg_payment,
  cph.value_currency,
  SUM(cph.payment_status = 'complete') AS payments_complete,
  SUM(cph.payment_status = 'partial') AS payments_partial,
  SUM(cph.payment_status = 'in_process') AS payments_in_process
FROM campaigns c
LEFT JOIN creator_payment_history cph ON cph.campaign_id = c.id
WHERE c.id = ? OR c.title LIKE ?
GROUP BY c.id, c.title, c.budget, cph.value_currency;
```

### Engagement Query (MySQL)
```sql
SELECT 
  c.id AS campaign_id,
  c.title AS campaign_name,
  COUNT(DISTINCT pm.creator_id) AS total_creators,
  COUNT(DISTINCT pm.id) AS total_content,
  SUM(pm.is_approved = 1) AS approved,
  SUM(pm.is_approved = 0) AS refused,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
  COUNT(DISTINCT pmc.id) AS contests,
  ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS contest_rate
FROM campaigns c
LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE c.id = ? OR c.title LIKE ?
GROUP BY c.id, c.title;
```

### Platform Average (for comparison)
```sql
SELECT 
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS platform_avg_approval
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL;
```

## Response Format (Slack)

Example output:
```
📊 Dashboard: Summer Vibes 2026

💰 REVENUE / GMV
• Total Pago: R$ 45.230,00 (net) | R$ 52.100,00 (gross)
• Creators Pagos: 127
• Pagamento Médio: R$ 356,00
• Status: 98 completos, 24 parciais, 5 em processo

📈 ENGAGEMENT
• Conteúdos: 1.234 submetidos
• Aprovação: 82,3% (1.015 aprovados, 219 recusados)
• Contestações: 18 (1,5% do total)
• Creators Ativos: 142

💡 ROI
• Budget: R$ 50.000,00
• Gasto Real: R$ 45.230,00 (90,5% do budget)
• ROI: 115% (revenue/budget)

📊 vs Média da Plataforma
• Aprovação Campanha: 82,3%
• Aprovação Plataforma (30d): 78,1%
• Diferença: +4,2pp ✅

🔗 Ver detalhes: [Google Sheets link se --export-sheets]
```

## Google Sheets Export

When `--export-sheets` is passed:
1. Creates a new Google Sheet with campaign name as title
2. Sheets: Summary, Revenue Details, Content Details, Creator Breakdown
3. Returns shareable link in output

Sheet structure:
- **Summary** — All metrics in a dashboard format
- **Revenue Details** — Payment history table
- **Content Details** — Per-content moderation results
- **Creator Breakdown** — Per-creator stats (content count, payments, approval rate)

## Safety
- READ ONLY queries
- No PII in Slack output (creator names masked in summaries)
- Google Sheets respects workspace permissions (brand team members only)
- Budget data is OK to share (not considered sensitive)

## Comparison to Existing Skills
- **campaign-lookup** → Basic status + approval rate (quick check)
- **campaign-performance** → Full dashboard with revenue, ROI, creator stats (deep dive)
- Use campaign-lookup for quick "how's it going?" questions
- Use campaign-performance for "I need the full picture" requests
