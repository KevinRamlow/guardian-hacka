# Campaign Lookup Skill

Quick campaign status checks and lookups for non-tech team members.

## When to Use
- "qual o status da campanha X?"
- "me mostra as campanhas ativas da marca Y"
- "quantos conteúdos a campanha Z recebeu?"
- "quais campanhas têm mais contestações?"

## Lookup Patterns

### Find campaign by name (partial match)
```sql
SELECT c.id, c.title, c.campaign_state_id, c.created_at,
       b.name AS marca
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
WHERE c.title LIKE '%SEARCH_TERM%'
ORDER BY c.created_at DESC
LIMIT 10;
```

### Campaign status with metrics
```sql
SELECT c.title AS campanha,
       c.campaign_state_id,
       COUNT(DISTINCT a.id) AS total_submissoes,
       COUNT(DISTINCT pm.id) AS total_moderados,
       SUM(pm.is_approved = 1) AS aprovados,
       SUM(pm.is_approved = 0) AS recusados,
       ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id
WHERE c.id = CAMPAIGN_ID
GROUP BY c.id, c.title, c.campaign_state_id;
```

### Active campaigns for a brand
```sql
SELECT c.id, c.title, c.campaign_state_id, c.created_at,
       COUNT(a.id) AS submissoes
FROM campaigns c
JOIN brands b ON c.brand_id = b.id
LEFT JOIN actions a ON a.campaign_id = c.id
WHERE b.name LIKE '%BRAND_NAME%'
  AND c.campaign_state_id = 'active'
GROUP BY c.id, c.title, c.campaign_state_id, c.created_at
ORDER BY submissoes DESC;
```

### Campaign guidelines (what moderators check)
```sql
SELECT pg.id, pg.guideline, pg.type
FROM proofread_guidelines pg
WHERE pg.campaign_id = CAMPAIGN_ID
ORDER BY pg.type, pg.id;
```

### Campaigns with highest contest rate (last 30d)
```sql
SELECT c.title,
       COUNT(DISTINCT pm.id) AS moderados,
       COUNT(DISTINCT pmc.id) AS contestados,
       ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM campaigns c
JOIN actions a ON a.campaign_id = c.id
JOIN proofread_medias pm ON pm.action_id = a.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY c.id, c.title
HAVING moderados >= 10
ORDER BY taxa_contestacao DESC
LIMIT 15;
```

## Response Format

For campaign lookups, always include:
1. **Campaign name and status** (active/completed/draft)
2. **Key numbers** — submissions, approval rate
3. **Brand** it belongs to
4. **Notable info** — high contest rate? very active? new?

Keep it conversational:
> A campanha "Summer Vibes 2026" da marca Natura está **ativa** com 1.234 conteúdos submetidos.
> Taxa de aprovação: 82% — dentro do esperado para campanhas desse porte.
> Contestações: apenas 12 (1,5%), bem abaixo da média.

## Safety
- READ ONLY
- Don't expose internal IDs unless specifically asked
- Mask PII
