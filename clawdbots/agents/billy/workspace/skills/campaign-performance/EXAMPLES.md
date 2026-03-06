# Usage Examples — Campaign Performance Dashboard

## Example 1: High-Volume Campaign (Pantene)

**Request:** "Me mostra o dashboard da campanha Pantene"

**Billy's action:**
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance
bash campaign-performance.sh --name "Pantene"
```

**Output:**
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

**Interpretation:**
- High-budget campaign with R$ 1.7M budget
- 2000 creators paid, avg R$ 701,75 each
- **Low approval rate** (15.7% vs platform avg 34.9%) — indicates strict guidelines or content quality issues
- ROI 70% = spent 70% of budget so far
- No contests = decisions not challenged by creators

---

## Example 2: High-Approval Campaign (La Roche-Posay)

**Request:** "Quero ver a performance da campanha 500751"

**Billy's action:**
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance
bash campaign-performance.sh --id 500751
```

**Output:**
```
📊 *Dashboard: La Roche-Posay | CONVITE EXCLUSIVO <3*
_Marca: L'Oréal LBD_

💰 *REVENUE / GMV*
• Total Pago: R$ 6,13 (net) | R$ 6,13 (gross)
• Creators Pagos: 613
• Pagamento Médio: R$ 0,01
• Status Pagamentos: 613 completos, 0 parciais, 0 em processo

📈 *ENGAGEMENT*
• Conteúdos: 2149 submetidos
• Aprovação: 73.5% (1580 aprovados, 569 recusados)
• Contestações: 0 (0.0% do total)
• Creators Ativos: 1094

💡 *ROI*
• Budget: R$ 60,00
• Gasto Real: R$ 6,13 (10.0% do budget)
• ROI: 10.0%

📊 *vs Média da Plataforma (30d)*
• Aprovação Campanha: 73.5%
• Aprovação Plataforma: 34.9%
• Diferença: +38.6pp ✅
```

**Interpretation:**
- Low-budget campaign (R$ 60), likely invitation-only or test
- Very low payment (R$ 0,01 avg) — probably participation-based, not performance-based
- **Excellent approval rate** (73.5% vs 34.9% platform avg) — clear guidelines or lenient moderation
- High engagement (2149 submissions from 1094 creators = ~2 submissions per creator)

---

## Example 3: JSON Output for Automation

**Request:** "Preciso dos dados da campanha 501014 em JSON"

**Billy's action:**
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance
bash campaign-performance.sh --id 501014 --format json
```

**Output:**
```json
{
  "campaign_id": 501014,
  "campaign_name": "Pantene - Molecular Bond Repair",
  "brand_name": "Grupo P&G | Pantene",
  "revenue": {
    "net": 1403500.00,
    "gross": 1754380.00,
    "currency": "BRL",
    "paid_creators": 2000,
    "avg_payment": 701.75,
    "total_payments": 2000,
    "payments_complete": 2000,
    "payments_partial": 0,
    "payments_in_process": 0
  },
  "engagement": {
    "total_creators": 2010,
    "total_content": 3204,
    "approved": 504,
    "refused": 2700,
    "approval_rate": 15.7,
    "contests": 0,
    "contest_rate": 0.0
  },
  "roi": {
    "budget": 1754386.00,
    "roi_percentage": "70.0",
    "budget_used_percentage": "70.0"
  },
  "platform_comparison": {
    "platform_avg_approval": 34.9,
    "difference": -19.2
  }
}
```

---

## Example 4: Google Sheets Export

**Request:** "Exporta o dashboard da campanha Bet MGM para Google Sheets"

**Billy's action:**
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance
bash campaign-performance.sh --name "Bet MGM" --export-sheets
```

**Output:**
```
📊 *Dashboard: Bet MGM | Lançamento 2026*
_Marca: BetMGM_

[... full dashboard output ...]

🔗 *Exportando para Google Sheets...*
📄 Ver detalhes: https://docs.google.com/spreadsheets/d/1a2b3c4d5e6f7g8h9i0j/edit
```

**Sheets structure:**
1. **Summary** — Key metrics table
2. **Revenue Details** — Payment history per creator
3. **Content Details** — Per-content moderation results (up to 1000 rows)
4. **Creator Breakdown** — Per-creator stats (submissions, approval rate, payments)

---

## Trigger Phrases to Watch For

Billy should invoke `campaign-performance` when users say:
- "dashboard da campanha X"
- "performance da campanha Y"
- "como está performando a campanha Z"
- "GMV da campanha..."
- "revenue da campanha..."
- "ROI da campanha..."
- "números completos da campanha..."
- "quero ver tudo da campanha..."

**Don't confuse with `campaign-lookup`:**
- "status da campanha X" → campaign-lookup (quick check)
- "campanhas ativas" → campaign-lookup (list view)
- "dashboard completo" → campaign-performance (full metrics)

---

## Integration Notes for Billy

1. **When to use this skill:**
   - User asks for detailed campaign metrics
   - User mentions "dashboard", "performance", "GMV", "ROI", "revenue"
   - User needs comparison to platform average

2. **Before running:**
   - Extract campaign ID or name from user message
   - If ambiguous, ask: "Qual campanha? Por nome ou ID?"

3. **After running:**
   - Share the formatted output directly in Slack
   - If approval rate is significantly different from platform avg (±10pp), highlight it
   - Suggest export to Sheets if user might need detailed data

4. **Error handling:**
   - If campaign not found: "Não encontrei a campanha [X]. Quer que eu busque campanhas similares?"
   - If MySQL fails: Fall back to asking human via `ask-human` skill
