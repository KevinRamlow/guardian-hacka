# Creator Profiles - Cross-Platform Unification

Unified view of creator activity across Instagram, TikTok, and YouTube platforms.

## When to Use
- "quantas plataformas o creator X usa?"
- "me mostra o perfil unificado do creator Y"
- "quais creators estão ativos em múltiplas plataformas?"
- "performance do creator Z no Instagram vs TikTok"
- "creators mais ativos no YouTube"
- "qual plataforma o creator prefere?"

## Key Concepts

- **Platform**: Instagram, TikTok, or YouTube (from format_sources)
- **Format**: Content type per platform (Reels, Story, Shorts, etc.)
- **Cross-platform creator**: Active on 2+ platforms
- **Platform preference**: Platform with most posts/best approval rate

## Query Patterns

### Multi-Platform Creators (Top Active)
```sql
SELECT 
  a.creator_id,
  COUNT(DISTINCT fs.name) AS num_platforms,
  GROUP_CONCAT(DISTINCT fs.name ORDER BY fs.name SEPARATOR ', ') AS platforms,
  COUNT(DISTINCT a.id) AS total_posts,
  COUNT(DISTINCT pm.campaign_id) AS campaigns,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  MAX(a.posted_at) AS ultimo_post
FROM actions a
JOIN ads ON a.ad_id = ads.id
JOIN formats f ON ads.format_id = f.id
JOIN format_sources fs ON f.format_source_id = fs.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.posted_at IS NOT NULL
  AND a.deleted_at IS NULL
  AND a.posted_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY a.creator_id
HAVING num_platforms > 1
ORDER BY num_platforms DESC, total_posts DESC
LIMIT 20;
```

### Unified Creator Profile (by creator_id)
```sql
SELECT 
  fs.name AS platform,
  COUNT(DISTINCT f.name) AS formatos_usados,
  GROUP_CONCAT(DISTINCT f.name ORDER BY f.name SEPARATOR ', ') AS formatos,
  COUNT(DISTINCT a.id) AS total_posts,
  COUNT(DISTINCT CASE WHEN a.posted_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS posts_30d,
  COUNT(DISTINCT pm.campaign_id) AS campanhas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  SUM(CASE WHEN pm.is_approved = 0 THEN 1 ELSE 0 END) AS recusados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  MIN(a.created_at) AS primeira_submissao,
  MAX(a.posted_at) AS ultimo_post
FROM actions a
JOIN ads ON a.ad_id = ads.id
JOIN formats f ON ads.format_id = f.id
JOIN format_sources fs ON f.format_source_id = fs.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.creator_id = CREATOR_ID
  AND a.deleted_at IS NULL
GROUP BY fs.name
ORDER BY total_posts DESC;
```

### Platform Distribution (All Creators)
```sql
SELECT 
  fs.name AS platform,
  COUNT(DISTINCT a.creator_id) AS creators_ativos,
  COUNT(DISTINCT CASE WHEN a.posted_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) 
        THEN a.creator_id END) AS creators_ativos_30d,
  COUNT(DISTINCT a.id) AS total_posts,
  COUNT(DISTINCT pm.campaign_id) AS campanhas,
  ROUND(AVG(CASE WHEN pm.id IS NOT NULL 
        THEN (pm.is_approved = 1) * 100 END), 1) AS taxa_aprovacao_media
FROM actions a
JOIN ads ON a.ad_id = ads.id
JOIN formats f ON ads.format_id = f.id
JOIN format_sources fs ON f.format_source_id = fs.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.posted_at IS NOT NULL
  AND a.deleted_at IS NULL
  AND a.posted_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY fs.name
ORDER BY creators_ativos DESC;
```

### Top Creators by Platform (last 30 days)
```sql
SELECT 
  a.creator_id,
  COUNT(DISTINCT a.id) AS posts,
  COUNT(DISTINCT pm.campaign_id) AS campanhas,
  SUM(CASE WHEN pm.is_approved = 1 THEN 1 ELSE 0 END) AS aprovados,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao,
  MAX(a.posted_at) AS ultimo_post
FROM actions a
JOIN ads ON a.ad_id = ads.id
JOIN formats f ON ads.format_id = f.id
JOIN format_sources fs ON f.format_source_id = fs.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE fs.name = 'PLATFORM_NAME'
  AND a.posted_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND a.deleted_at IS NULL
GROUP BY a.creator_id
ORDER BY posts DESC
LIMIT 15;
```

### Creator Platform Preference Analysis
```sql
WITH creator_platforms AS (
  SELECT 
    a.creator_id,
    fs.name AS platform,
    COUNT(DISTINCT a.id) AS posts,
    ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
  FROM actions a
  JOIN ads ON a.ad_id = ads.id
  JOIN formats f ON ads.format_id = f.id
  JOIN format_sources fs ON f.format_source_id = fs.id
  LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
  WHERE a.creator_id = CREATOR_ID
    AND a.posted_at IS NOT NULL
    AND a.deleted_at IS NULL
  GROUP BY a.creator_id, fs.name
)
SELECT 
  platform,
  posts,
  taxa_aprovacao,
  CASE 
    WHEN posts = (SELECT MAX(posts) FROM creator_platforms) THEN 'Preferida (mais posts)'
    WHEN taxa_aprovacao = (SELECT MAX(taxa_aprovacao) FROM creator_platforms) THEN 'Melhor performance'
    ELSE '-'
  END AS destaque
FROM creator_platforms
ORDER BY posts DESC;
```

### Multi-Platform Activity Summary
```sql
SELECT 
  CASE 
    WHEN num_platforms = 1 THEN '1 plataforma'
    WHEN num_platforms = 2 THEN '2 plataformas'
    ELSE '3 plataformas'
  END AS categoria,
  COUNT(DISTINCT creator_id) AS num_creators,
  ROUND(AVG(total_posts), 1) AS media_posts,
  ROUND(AVG(taxa_aprovacao), 1) AS taxa_aprovacao_media
FROM (
  SELECT 
    a.creator_id,
    COUNT(DISTINCT fs.name) AS num_platforms,
    COUNT(DISTINCT a.id) AS total_posts,
    ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
  FROM actions a
  JOIN ads ON a.ad_id = ads.id
  JOIN formats f ON ads.format_id = f.id
  JOIN format_sources fs ON f.format_source_id = fs.id
  LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
  WHERE a.posted_at IS NOT NULL
    AND a.deleted_at IS NULL
    AND a.posted_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
  GROUP BY a.creator_id
) AS creator_stats
GROUP BY categoria
ORDER BY num_platforms;
```

### Format Popularity by Platform
```sql
SELECT 
  fs.name AS platform,
  f.name AS formato,
  COUNT(DISTINCT a.id) AS total_posts,
  COUNT(DISTINCT a.creator_id) AS creators,
  ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
FROM actions a
JOIN ads ON a.ad_id = ads.id
JOIN formats f ON ads.format_id = f.id
JOIN format_sources fs ON f.format_source_id = fs.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
WHERE a.posted_at IS NOT NULL
  AND a.deleted_at IS NULL
  AND a.posted_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY fs.name, f.name
ORDER BY fs.name, total_posts DESC;
```

## Response Format

### Unified Creator Profile
```
🌐 *Perfil Cross-Platform — Creator #XXXXX*

*Instagram*
• Posts: XXX (XX nos últimos 30 dias)
• Campanhas: XX
• Taxa de aprovação: XX,X%
• Formatos: Reels, Story, Publicação
• Ativo desde: DD/MM/YYYY

*TikTok*
• Posts: XX (X nos últimos 30 dias)
• Campanhas: X
• Taxa de aprovação: XX,X%
• Formatos: Vídeo
• Ativo desde: DD/MM/YYYY

*YouTube*
• Posts: XX (X nos últimos 30 dias)
• Campanhas: X
• Taxa de aprovação: XX,X%
• Formatos: Shorts
• Ativo desde: DD/MM/YYYY

*Resumo Geral*
• Total de plataformas: 3
• Plataforma preferida: Instagram (XXX posts)
• Melhor performance: YouTube (XX,X% aprovação)
• Última atividade: DD/MM/YYYY

_Fonte: MySQL db-maestro-prod_
```

### Multi-Platform Creators
```
🌟 *Top Creators Cross-Platform (últimos 90 dias)*

1. Creator #XXXXX
   • Plataformas: Instagram, TikTok, YouTube
   • Posts: XXX | Campanhas: XX
   • Taxa aprovação: XX,X%
   • Última atividade: DD/MM/YYYY

2. Creator #YYYYY
   • Plataformas: Instagram, TikTok
   • Posts: YY | Campanhas: Y
   • Taxa aprovação: YY,Y%
   • Última atividade: DD/MM/YYYY

[...]

_Fonte: MySQL db-maestro-prod_
```

### Platform Distribution
```
📊 *Distribuição por Plataforma (últimos 90 dias)*

*Instagram*
• Creators ativos: X.XXX (XXX nos últimos 30 dias)
• Posts: XX.XXX
• Campanhas: XXX
• Taxa aprovação média: XX,X%

*TikTok*
• Creators ativos: XXX (XX nos últimos 30 dias)
• Posts: X.XXX
• Campanhas: XX
• Taxa aprovação média: XX,X%

*YouTube*
• Creators ativos: XXX (XX nos últimos 30 dias)
• Posts: XXX
• Campanhas: XX
• Taxa aprovação média: XX,X%

_Fonte: MySQL db-maestro-prod_
```

### Platform Preference Analysis
```
📈 *Análise de Preferência — Creator #XXXXX*

*Instagram* (Preferida - mais posts)
• XXX posts | Taxa: XX,X%

*TikTok*
• XX posts | Taxa: XX,X%

*YouTube* (Melhor performance)
• XX posts | Taxa: XX,X% ⭐

Este creator é mais ativo no Instagram, mas tem melhor taxa de aprovação no YouTube.

_Fonte: MySQL db-maestro-prod_
```

### Multi-Platform Activity Summary
```
🎯 *Resumo Cross-Platform*

*1 plataforma apenas*
• XXX creators
• Média: XX,X posts por creator
• Taxa aprovação: XX,X%

*2 plataformas*
• XX creators
• Média: XX,X posts por creator
• Taxa aprovação: XX,X%

*3 plataformas (Instagram + TikTok + YouTube)*
• XX creators
• Média: XXX,X posts por creator
• Taxa aprovação: XX,X%

Creators ativos em múltiplas plataformas tendem a ter maior volume de posts.

_Fonte: MySQL db-maestro-prod_
```

### Top Creators by Platform
```
🏆 *Top Creators — Instagram (últimos 30 dias)*

1. Creator #XXXXX — XXX posts
   • Campanhas: XX | Aprovação: XX,X%
   • Última atividade: DD/MM

2. Creator #YYYYY — YY posts
   • Campanhas: Y | Aprovação: YY,Y%
   • Última atividade: DD/MM

[...]

_Fonte: MySQL db-maestro-prod_
```

## Privacy Rules — CRITICAL
- **NEVER expose creator names, emails, or any PII**
- Use creator_id only (e.g., "Creator #12345")
- In group channels, anonymize even creator_ids if discussing sensitive data
- Platform usernames extracted from post_url should NEVER be shown
- Aggregate statistics are always safe to share

## Safety
- READ ONLY — no modifications to database
- Always use LIMIT in queries to prevent large result sets
- Date-bound queries (default: last 90 days for cross-platform analysis)
- Mask individual creator identities in group contexts
- Platform-specific handles/usernames are internal data — don't expose

## Technical Notes
- Platform data comes from `format_sources` table (Instagram=1, TikTok=2, Youtube=3)
- Post URLs in `actions.post_url` contain platform handles but should not be extracted/shown
- Join path: actions → ads → formats → format_sources
- Use `posted_at` for actual published content (not just submitted)
- Filter `deleted_at IS NULL` to exclude deleted actions
