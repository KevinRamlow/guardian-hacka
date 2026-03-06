# Billy Integration Guide — Campaign Performance Dashboard

## Quick Reference

**Skill location:** `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance/`

**Main script:** `campaign-performance.sh`

**Trigger phrases:**
- "dashboard da campanha X"
- "performance da campanha Y"  
- "GMV/ROI/revenue da campanha Z"
- "números completos da campanha..."

## How Billy Should Use This

### Step 1: Detect Intent

When user message contains:
- `(dashboard|performance|números|métricas)` + `campanha` + `[campaign name/ID]`
- `(GMV|ROI|revenue)` + `campanha`
- `"como está performando"` + campaign reference

→ Use `campaign-performance` skill

### Step 2: Extract Campaign Identifier

**From message:**
- Look for campaign ID (numeric, 6 digits): `501014`, `500751`
- Look for campaign name: `"Pantene"`, `"Bet MGM"`, `"La Roche-Posay"`

**If ambiguous:**
- Ask user: "Qual campanha? Você pode me passar o ID ou o nome?"

### Step 3: Run Script

```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance

# If user provided ID
bash campaign-performance.sh --id <CAMPAIGN_ID>

# If user provided name
bash campaign-performance.sh --name "<CAMPAIGN_NAME>"

# If user wants Google Sheets
bash campaign-performance.sh --id <CAMPAIGN_ID> --export-sheets

# If automation/API needs JSON
bash campaign-performance.sh --id <CAMPAIGN_ID> --format json
```

### Step 4: Share Output

**Default (Slack format):**
- Share the full dashboard output directly
- No need to summarize — the output is already formatted for Slack

**Highlight noteworthy items:**
- If approval rate differs from platform avg by ±10pp, mention it
- If ROI is very low (<30%) or very high (>90%), call it out
- If contest rate is high (>5%), note it

**Example commentary:**
```
[Dashboard output here]

📌 *Nota:* A taxa de aprovação está 19pp abaixo da média da plataforma — vale revisar as diretrizes dessa campanha.
```

### Step 5: Offer Next Steps

After sharing dashboard, Billy can:
- "Quer que eu exporte para Google Sheets com mais detalhes?"
- "Posso comparar com outra campanha se quiser"
- "Precisa de alguma análise específica desses números?"

## Example Conversation

**User:** "Me mostra o dashboard da campanha Pantene"

**Billy thinks:**
- Intent: campaign performance dashboard
- Campaign identifier: "Pantene" (name)
- Action: Run campaign-performance.sh --name "Pantene"

**Billy responds:**
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

📌 *Nota:* A taxa de aprovação está bem abaixo da média da plataforma. Pode indicar guidelines muito restritivas ou problemas de qualidade do conteúdo.

Quer que eu exporte esses dados para Google Sheets? 📄
```

## Error Handling

### Campaign Not Found
```bash
Error: Campaign not found with search: Pantene
```

**Billy's response:**
"Não encontrei a campanha 'Pantene'. Quer que eu busque por nome similar ou você pode me passar o ID?"

### MySQL Connection Error
**Billy's action:**
- Try one more time
- If still fails, escalate to `ask-human` skill
- Message: "Tive um problema acessando os dados. Já avisei o time técnico!"

### Empty Results (Campaign Exists but No Data)
**Billy's response:**
"Encontrei a campanha [Name], mas ainda não há dados de performance. Ela pode estar em fase de draft ou sem conteúdos submetidos ainda."

## Comparison to Other Skills

| Situation | Skill to Use |
|-----------|--------------|
| "Status da campanha X?" | `campaign-lookup` |
| "Campanhas ativas da marca Y?" | `campaign-lookup` |
| "Dashboard completo da campanha Z" | `campaign-performance` ✓ |
| "Compara campanha A vs B" | `campaign-compare` |
| "Dados de creators dessa semana" | `creator-analytics` |
| "Resumo da semana" | `weekly-digest` |

**Rule of thumb:**
- `campaign-lookup` = quick, single metric
- `campaign-performance` = full picture, all metrics
- If user says "tudo", "completo", "dashboard", "performance" → use `campaign-performance`

## Testing Checklist

Before deploying to Billy:
- [x] Test with high-volume campaign (501014 — Pantene)
- [x] Test with low-volume campaign (500751 — La Roche-Posay)
- [x] Test with campaign name search
- [x] Test with campaign ID
- [x] Test JSON output format
- [x] Verify BRL currency formatting (R$ 1.403.500,00)
- [ ] Test Google Sheets export (requires gog auth)
- [ ] Test with campaign that has no payments yet
- [ ] Test with USD currency campaign (if exists)

## Deployment

1. ✅ Skill files created in `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/skills/campaign-performance/`
2. ✅ TOOLS.md updated with new skill entry
3. ✅ Executable permissions set on scripts
4. ⏳ Billy needs to be taught to recognize trigger phrases
5. ⏳ Billy needs context: when to use this vs `campaign-lookup`

**Next step:** Update Billy's prompt/instructions to include this skill in decision tree.
