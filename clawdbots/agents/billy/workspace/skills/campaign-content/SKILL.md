# Campaign Content Download & Package Skill

**Get download links for campaign media content with status filtering AND package into shareable Google Sheets.**

## When to Use
- **"baixar conteúdos aprovados da campanha X"**
- **"me manda os links dos conteúdos recusados da campanha Y"**
- **"quero os arquivos pendentes da campanha Z"**
- **"exporta o conteúdo da campanha para uma planilha"**
- **"download all approved content from campaign ABC"**
- **"package campaign X media into Drive"**

## How It Works

### Option 1: Raw URLs (fast, for terminal/scripts)
Query MySQL `db-maestro-prod` to fetch media URLs and return as list.

### Option 2: Google Sheets Package (NEW — recommended for users)
Query MySQL → Format as organized table → Export to Google Sheets → Return shareable link.

**Tables used:**
- `proofread_medias` — moderation records with approval status
- `actions` — submission records linking campaign to media
- `media_content` — actual media files (URLs, thumbnails)
- `campaigns` — campaign info
- `brands` — brand names

## Database Schema

**Relationships:**
- `campaigns` → `proofread_medias` (via `proofread_medias.campaign_id`)
- `media_content` ← `proofread_medias` (via `proofread_medias.media_id = media_content.id`)
- `actions` ← `media_content` (via `media_content.action_id`)

**Key fields:**
- `media_content.media_url` — S3 URL for download
- `media_content.thumb_url` — Thumbnail URL
- `media_content.mime_type` — File type (video/mp4, image/jpeg, etc.)
- `proofread_medias.is_approved` — 1=approved, 0=rejected, NULL=pending

## Query Patterns

### Get all media URLs from a campaign (by campaign ID)

```sql
SELECT 
    mc.id AS media_id,
    mc.media_url AS download_url,
    mc.thumb_url AS thumbnail_url,
    mc.mime_type,
    pm.is_approved,
    pm.created_at AS moderated_at
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = CAMPAIGN_ID
ORDER BY pm.created_at DESC;
```

### Get approved content only

```sql
SELECT 
    mc.id AS media_id,
    mc.media_url AS download_url,
    mc.thumb_url AS thumbnail_url,
    mc.mime_type,
    pm.created_at AS approved_at
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = CAMPAIGN_ID
  AND pm.is_approved = 1
ORDER BY pm.created_at DESC;
```

### Get rejected content only

```sql
SELECT 
    mc.id AS media_id,
    mc.media_url AS download_url,
    mc.thumb_url AS thumbnail_url,
    mc.mime_type,
    pm.created_at AS rejected_at
FROM campaigns c
JOIN proofread_medias pm ON pm.campaign_id = c.id
JOIN media_content mc ON mc.id = pm.media_id
WHERE c.id = CAMPAIGN_ID
  AND pm.is_approved = 0
ORDER BY pm.created_at DESC;
```

### Get pending content (not yet moderated)

Note: Pending content means media_content records that don't have a proofread_medias entry yet.

```sql
SELECT 
    mc.id AS media_id,
    mc.media_url AS download_url,
    mc.thumb_url AS thumbnail_url,
    mc.mime_type,
    mc.created_at AS submitted_at
FROM media_content mc
JOIN actions a ON a.id = mc.action_id
JOIN ads ad ON ad.id = a.ad_id
JOIN moments m ON m.id = ad.moment_id
LEFT JOIN proofread_medias pm ON pm.media_id = mc.id
WHERE m.campaign_id = CAMPAIGN_ID
  AND pm.id IS NULL
  AND mc.deleted_at IS NULL
ORDER BY mc.created_at DESC;
```

### Find campaign by name (if user gives campaign name, not ID)

```sql
SELECT c.id, c.title, c.campaign_state_id,
       COUNT(DISTINCT mc.id) AS total_medias
FROM campaigns c
LEFT JOIN actions a ON a.campaign_id = c.id
LEFT JOIN media_content mc ON mc.action_id = a.id
WHERE c.title LIKE '%SEARCH_TERM%'
GROUP BY c.id, c.title, c.campaign_state_id
ORDER BY c.created_at DESC
LIMIT 10;
```

## Response Format

Return links in a user-friendly format:

### Example 1: Approved content
> ✅ **56 conteúdos aprovados** da campanha "Summer Vibes 2026"
>
> **Download links:**
> 1. https://s3.amazonaws.com/brandlovers/media/12345.mp4 (vídeo)
> 2. https://s3.amazonaws.com/brandlovers/media/12346.jpg (imagem)
> 3. https://s3.amazonaws.com/brandlovers/media/12347.mp4 (vídeo)
> ... (primeiros 20 mostrados)
>
> 💡 **Tip:** Use um downloader como `wget` ou `curl` para baixar em lote.
> 💡 Posso gerar um script shell para download automático se quiser!

### Example 2: Rejected content
> ❌ **12 conteúdos recusados** da campanha "Summer Vibes 2026"
>
> **Download links:**
> 1. https://s3.amazonaws.com/brandlovers/media/67890.jpg (contestado)
> 2. https://s3.amazonaws.com/brandlovers/media/67891.mp4
> 3. https://s3.amazonaws.com/brandlovers/media/67892.jpg
>
> ⚠️ Atenção: 5 contestações pendentes de revisão

### Example 3: Pending content
> ⏳ **23 conteúdos pendentes** de moderação na campanha "Summer Vibes 2026"
>
> **Download links:**
> 1. https://s3.amazonaws.com/brandlovers/media/55555.mp4 (submetido há 2h)
> 2. https://s3.amazonaws.com/brandlovers/media/55556.jpg (submetido há 3h)
> ...

### Example 4: Generate download script

If user asks for bulk download or there are many files (>10), offer to generate a shell script:

```bash
#!/bin/bash
# Download approved content from campaign "Summer Vibes 2026"
# Generated by Billy on 2026-03-06

mkdir -p summer-vibes-approved
cd summer-vibes-approved

# Download 56 files
wget "https://s3.amazonaws.com/brandlovers/media/12345.mp4" -O "media-12345.mp4"
wget "https://s3.amazonaws.com/brandlovers/media/12346.jpg" -O "media-12346.jpg"
wget "https://s3.amazonaws.com/brandlovers/media/12347.mp4" -O "media-12347.mp4"
# ... (all URLs)

echo "✅ Downloaded 56 files to $(pwd)"
```

## Implementation

### Step 1: Find campaign

If user gives campaign name instead of ID:
```bash
mysql -e "SELECT c.id, c.title FROM campaigns c WHERE c.title LIKE '%$SEARCH%' LIMIT 5;"
```

Ask user to confirm which campaign if multiple matches.

### Step 2: Query media URLs with status filter

```bash
STATUS_FILTER=""
case "$1" in
  "approved"|"aprovados")
    STATUS_FILTER="AND pm.is_approved = 1"
    ;;
  "rejected"|"recusados")
    STATUS_FILTER="AND pm.is_approved = 0"
    ;;
  "pending"|"pendentes")
    STATUS_FILTER="AND pm.id IS NULL"
    ;;
esac

mysql -e "
SELECT mc.s3_url, mc.media_type, pm.is_approved
FROM campaigns c
JOIN actions a ON a.campaign_id = c.id
JOIN media_content mc ON mc.action_id = a.id
LEFT JOIN proofread_medias pm ON pm.action_id = a.id
WHERE c.id = $CAMPAIGN_ID $STATUS_FILTER
ORDER BY pm.created_at DESC;
"
```

### Step 3: Format response

- Count total URLs
- Show first 10-20 links inline
- If >20, offer download script
- Include media type (video/image) and status context

## Safety & Best Practices

- ✅ **READ ONLY** — no database modifications
- ✅ **S3 URLs are public** — safe to share with authorized users
- ✅ **Add campaign context** — always show campaign name + status summary
- ✅ **Respect privacy** — don't expose creator names/emails
- ✅ **Limit results** — default to first 100 URLs, ask before fetching thousands
- ⚠️ **Large downloads** — warn if >100 files, suggest batch processing

## Use Cases

### Use Case 1: Marketing team needs approved content for social media ⭐ NEW
**User:** "Billy, me manda os conteúdos aprovados da campanha Verão 2026"
**Billy:** Creates Google Sheet with organized table, returns shareable link
- Columns: Media ID, Tipo (Vídeo/Imagem), Status, URL de Download, Thumbnail, Moderado em
- Auto-organized by brand/campaign
- Shareable with anyone (view-only)
- User can download files directly from URLs in sheet

### Use Case 2: Review rejected content
**User:** "Show me rejected content from Natura Q1"
**Billy:** Creates sheet with rejected URLs, includes thumbnails for quick review

### Use Case 3: Check pending moderation queue
**User:** "Quantos conteúdos pendentes tem na campanha X?"
**Billy:** Creates sheet showing pending submissions with submission timestamps

### Use Case 4: Bulk export for analysis
**User:** "I need all content (approved + rejected) from campaign 5678"
**Billy:** Creates sheet with ALL content grouped by status, easy filtering

## Helper Scripts

### 1. `fetch-campaign-content.sh` — Raw URLs
Returns URLs as list (terminal-friendly)
```bash
./skills/campaign-content/scripts/fetch-campaign-content.sh CAMPAIGN_ID [approved|rejected|pending|all] [--script]
```
- With `--script` flag: generates download bash script
- Outputs URLs to stdout

### 2. `package-campaign-content.sh` — Google Sheets Export ⭐ NEW
Creates organized Google Sheet with media links
```bash
./skills/campaign-content/scripts/package-campaign-content.sh CAMPAIGN_ID [approved|rejected|pending|all]
```
- Creates shareable Google Sheet
- Columns: Media ID, Tipo, Status, URL de Download, Thumbnail, Moderado em
- Auto-titled: `[Brand Name] Campaign Name - Status`
- Returns shareable URL
- View-only access for anyone with link

### When to use which?
- **User asks for "download" or "links"** → Use package-campaign-content.sh (Google Sheets)
- **Script/automation needed** → Use fetch-campaign-content.sh
- **User explicitly asks for "bash script"** → Use fetch-campaign-content.sh with --script flag

## Billy Implementation Guide

### Step 1: Identify campaign
If user gives campaign name (not ID), search first:
```bash
mysql -e "SELECT c.id, c.title, b.name FROM campaigns c JOIN brands b ON b.id = c.brand_id WHERE c.title LIKE '%SEARCH_TERM%' ORDER BY c.created_at DESC LIMIT 5;"
```

If multiple matches, ask user to confirm which one.

### Step 2: Determine status filter
Parse user intent:
- "aprovados", "approved", "conteúdo aprovado" → `approved`
- "recusados", "rejected", "refused" → `rejected`
- "pendentes", "pending", "aguardando moderação" → `pending`
- No status mentioned or "todos", "all", "tudo" → `all`

### Step 3: Call package script
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace
bash skills/campaign-content/scripts/package-campaign-content.sh CAMPAIGN_ID STATUS
```

### Step 4: Format response for user
The script outputs the Google Sheets URL. Billy should respond with:

**Example response (pt-BR):**
> ✅ Prontinho! Criei uma planilha com os conteúdos **aprovados** da campanha **Verão 2026**
> 
> 🔗 https://docs.google.com/spreadsheets/d/ABC123/edit
> 
> 📊 **56 conteúdos** organizados por tipo e data
> - 🎥 32 vídeos
> - 🖼️ 24 imagens
> 
> 💡 **Como usar:**
> - Você pode baixar os arquivos diretamente pelos links na coluna "URL de Download"
> - Use a coluna "Thumbnail" para visualizar antes de baixar
> - A planilha é compartilhável com qualquer pessoa que tenha o link
> 
> Precisa de mais alguma coisa?

**Example response (English):**
> ✅ Done! Created a spreadsheet with **approved** content from campaign **Summer 2026**
> 
> 🔗 https://docs.google.com/spreadsheets/d/ABC123/edit
> 
> 📊 **56 items** organized by type and date
> - 🎥 32 videos
> - 🖼️ 24 images
> 
> 💡 **How to use:**
> - Download files directly from the "URL de Download" column
> - Use the "Thumbnail" column to preview before downloading
> - Sheet is shareable with anyone who has the link
> 
> Need anything else?

### Error Handling
- Campaign not found → "Não encontrei uma campanha com esse ID/nome. Pode conferir?"
- No content found → "Essa campanha não tem conteúdos [aprovados/recusados/pendentes] ainda."
- Sheets export failed → "Algo deu errado ao criar a planilha. Posso te mandar os links diretos?"

## Testing Locally

```bash
# Test with a real campaign
mysql -e "SELECT id, title FROM campaigns ORDER BY created_at DESC LIMIT 5;"

# Pick a campaign ID and test package script
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace
bash skills/campaign-content/scripts/package-campaign-content.sh 501014 approved

# Should output Google Sheets URL
```

## Future Enhancements

### Phase 2: Direct ZIP download
- Generate temporary zip file with all media
- Upload to S3 bucket
- Return single download link (expires in 24h)

### Phase 3: Filtering by media type
- "Only show videos" or "Only images"
- Filter by date range

### Phase 4: Creator context
- Show which creator submitted each media
- Group by creator for reporting

---

**Linear Task:** CAI-76  
**Created:** 2026-03-06 02:36 UTC  
**Status:** Ready for testing
