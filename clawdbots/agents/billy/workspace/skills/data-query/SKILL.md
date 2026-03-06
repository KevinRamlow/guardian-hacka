# Data Query Skill — Simplified BI Queries

Translate plain-language business questions into SQL queries, execute them, and return results in human-readable format.

## When to Use
- User asks a data question: "quantos conteúdos foram aprovados essa semana?"
- User wants a comparison: "como está a taxa de aprovação vs mês passado?"
- User needs a list: "quais campanhas estão ativas?"

## Flow

1. **Understand the question** — What metric? What time range? What filters?
2. **Pick the data source** — MySQL for operational data, BigQuery for analytics
3. **Write the query** — Use the patterns in TOOLS.md, always add date filters and LIMIT
4. **Execute** — Run via mysql CLI or bq CLI
5. **Translate results** — Convert to business language with context

## Query Patterns

### "How many?" → COUNT with filters
```sql
SELECT COUNT(*) AS total
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND is_approved = 1;
```

### "What's the rate?" → COUNT with ratios
```sql
SELECT
  ROUND(SUM(is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY);
```

### "Compare periods" → Two subqueries or window functions
```sql
SELECT
  CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 'esta_semana'
       ELSE 'semana_passada' END AS periodo,
  COUNT(*) AS total,
  ROUND(SUM(is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
GROUP BY periodo;
```

### "List/show me" → SELECT with readable columns
```sql
SELECT c.name AS campanha, c.status,
       COUNT(a.id) AS conteudos_submetidos
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
  AND a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
WHERE c.status = 'active'
GROUP BY c.id, c.name, c.status
ORDER BY conteudos_submetidos DESC
LIMIT 20;
```

## Response Format

Always respond with:
1. **The answer** in one sentence (plain language)
2. **Key numbers** as a bullet list
3. **Context** — "compared to last week..." or "this is normal for this campaign"
4. **Source note** — which table/database the data came from

Example:
> Na última semana, 2.847 conteúdos foram moderados com taxa de aprovação de 78,3%.
>
> - Aprovados: 2.231
> - Recusados: 616
> - Contestações: 42 (6,8% das recusas)
>
> A taxa está 3% acima da semana anterior — boa tendência!
>
> _Fonte: MySQL db-maestro-prod, tabela proofread_medias_

## Safety
- READ ONLY — never modify data
- Always add LIMIT (default 100)
- Mask PII (creator names, emails)
- Warn before expensive BigQuery scans
