# TOOLS.md - Billy Agent Tools & Data Sources

## MySQL (Production — db-maestro-prod)

**Connection:** Cloud SQL Auth Proxy sidecar on localhost:3306
**Database:** db-maestro-prod
**Access:** READ ONLY

### Key Tables (Simplified)

#### `campaigns` — Marketing campaigns
- `id` — Campaign ID
- `name` — Campaign name
- `brand_id` — Which brand owns it
- `status` — active, completed, draft
- `created_at` — When it was created

#### `actions` — Creator content submissions
- `id` — Action ID
- `campaign_id` → campaigns.id
- `creator_id` — Which creator submitted
- `status` — Submission status
- `created_at` — When submitted

#### `proofread_medias` — Content moderation results
- `id` — Moderation ID
- `brand_id`, `campaign_id`, `moment_id`, `ad_id` — Direct foreign keys (no need to join through actions)
- `action_id` → actions.id
- `media_id` → media_content.id
- `creator_id` — Creator who submitted
- `is_approved` — 1 = approved, 0 = refused (**NOT a status enum**)
- `is_guidelines_approved` — 1 = passed guideline check
- `is_audio_quality_approved` — 1 = passed audio quality check
- `adherence` — Float score of content adherence
- `metadata` — JSON with additional info (e.g., `$.audio_output` for agentic model)
- `created_at` — When moderated

**⚠️ IMPORTANT:** Use `is_approved = 1` for approved, `is_approved = 0` for refused. There is NO `status` column.

#### `creator_payment_history` — Creator payments
- `id` — Payment ID
- `creator_id` — Which creator was paid
- `campaign_id` → campaigns.id
- `value` — Payment amount (net)
- `gross_value` — Gross payment amount
- `value_currency` — BRL or USD
- `payment_status` — partial, complete, in_process
- `date_of_transaction` — When paid

#### `moments` — Campaign phases/moments
- `id`, `campaign_id` → campaigns.id
- `title` — Moment name
- `starts_at`, `ends_at` — Active period
- `status` — draft, published

#### `ads` — Individual ad units within moments
- `id`, `moment_id` → moments.id
- `format_id` — Content format
- `title`, `briefing` — Ad details
- `hashtag` — Required hashtag

#### `creator_groups` — Creator batches invited to campaigns
- `id`, `campaign_id` → campaigns.id
- `title`, `status` — Group info
- `creators_quantity_goal` — Target number of creators

#### `brands` — Brand accounts
- `id`, `name`, `status`

### Common Business Queries

```sql
-- Campaign performance summary (last 30 days)
-- NOTE: proofread_medias has direct campaign_id, no need to join through actions
SELECT c.title AS campanha,
       b.name AS marca,
       COUNT(*) AS total_conteudos,
       SUM(pm.is_approved = 1) AS aprovados,
       SUM(pm.is_approved = 0) AS recusados,
       ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
FROM proofread_medias pm
JOIN campaigns c ON pm.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title, b.name
ORDER BY total_conteudos DESC
LIMIT 20;

-- Daily moderation volume (last 14 days)
SELECT DATE(pm.created_at) AS dia,
       COUNT(*) AS total,
       SUM(pm.is_approved = 1) AS aprovados,
       SUM(pm.is_approved = 0) AS recusados
FROM proofread_medias pm
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
  AND pm.deleted_at IS NULL
GROUP BY DATE(pm.created_at)
ORDER BY dia DESC;

-- Top campaigns by volume (last 7 days)
SELECT c.title AS campanha, b.name AS marca, COUNT(*) AS conteudos
FROM proofread_medias pm
JOIN campaigns c ON pm.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title, b.name
ORDER BY conteudos DESC
LIMIT 10;

-- Contest rate by campaign (last 30 days)
SELECT c.title AS campanha,
       COUNT(DISTINCT pm.id) AS moderados,
       COUNT(DISTINCT pmc.id) AS contestados,
       ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
FROM proofread_medias pm
JOIN campaigns c ON pm.campaign_id = c.id
LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
WHERE pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND pm.deleted_at IS NULL
GROUP BY c.id, c.title
HAVING moderados > 10
ORDER BY taxa_contestacao DESC;

-- Creator payment summary (last 30 days)
SELECT COUNT(DISTINCT cph.creator_id) AS creators_pagos,
       ROUND(SUM(cph.value), 2) AS total_pago,
       ROUND(AVG(cph.value), 2) AS pagamento_medio,
       cph.value_currency
FROM creator_payment_history cph
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY cph.value_currency;
```

### Join Path Reference
- `proofread_medias` has direct FKs: `campaign_id`, `brand_id`, `moment_id`, `ad_id`, `action_id`, `creator_id`
- For campaign details: `pm.campaign_id → campaigns.id → brands (via brand_id)`
- For ad/moment details: `pm.ad_id → ads.id → moments (via moment_id)`
- For contest data: `proofread_media_contest.proofread_media_id → proofread_medias.id`
- For payments: `creator_payment_history.campaign_id → campaigns.id`

## BigQuery

**Project:** brandlovers-prod
**Access:** Via Workload Identity (bigquery.dataViewer)

### Key Datasets
- `analytics` — Event tracking, user behavior, funnel metrics
- `guardian` — Moderation traces (for deeper analysis)

### Cost Tips
- Always filter by date partition
- Use `LIMIT` during exploration
- Prefer specific columns over `SELECT *`

## Presentations (nano-banana + Gemini)

**Engine:** nano-banana (Python PPTX generation with AI-powered content)
**AI Model:** Google Gemini (API key required — ask Caio)
**Status:** ⚠️ Gemini API key not yet configured — structure generation works, AI content pending

### Supported Output
- `.pptx` (PowerPoint) — primary format
- Slide types: title, content, chart placeholder, comparison, summary
- Brand template with Brandlovrs colors

### Presentation Templates
1. **Campaign Report** — Performance summary for a specific campaign
2. **Weekly Digest** — Cross-campaign metrics for the week
3. **Brand Review** — Deep dive for a specific brand's campaigns
4. **Executive Summary** — High-level KPIs for leadership

## Slack — Human Escalation

### #billy-questions channel
**Purpose:** Billy posts questions here when he doesn't have the answer.
**Who monitors:** Data team, engineering, and whoever can help.

**Escalation format:**
```
🤔 Billy precisa de ajuda!

**Pergunta:** [redacted/anonymized question — see SOUL.md privacy rules]
**Contexto:** [what Billy already checked and ruled out]
**Fonte original:** [DM / #channel-name]

Responde na thread pfv! 🙏
```

**Privacy rules for escalation:**
- From DMs → ALWAYS anonymize/redact (see SOUL.md "Privacy & Escalation")
- From group channels → OK to include context, still redact PII
- NEVER include: names, revenue, specific account metrics from private chats

**After receiving answer:**
- Deliver to the original requester
- Log to `memory/learned-from-humans.md` for future reference

## Skills Reference

### Available Skills (10 total)
| Skill | Purpose | Trigger phrases |
|-------|---------|-----------------|
| `data-query` | General data questions → SQL → business answers | "quantos...", "qual a taxa...", "me mostra..." |
| `campaign-lookup` | Quick campaign status/performance lookups | "status da campanha X", "campanhas ativas" |
| `campaign-content` | ⭐ **UPDATED** Package campaign media into Google Sheets with download links | "baixar conteúdos da campanha X", "exporta mídia da campanha", "download campaign content" |
| `campaign-comments` | Export campaign moderation comments to Google Sheets | "exporta comentários da campanha X", "feedbacks de moderação", "comentários de recusa" |
| `campaign-performance` | Full campaign dashboard: revenue, ROI, creators, approval vs platform avg | "dashboard da campanha X", "performance da campanha", "GMV/ROI/revenue da campanha" |
| `campaign-compare` | Side-by-side campaign comparison | "compara campanha X vs Y", "qual performou melhor?" |
| `creator-analytics` | Creator participation & payment insights | "quantos creators...", "pagamentos do mês", "creators ativos" |
| `weekly-digest` | Auto-generated weekly platform summary | "resumo da semana", "weekly report" |
| `powerpoint` | Branded .pptx generation (4 templates) | "faz uma apresentação", "cria um report" |
| `ask-human` | Uncertainty escalation to #billy-questions | Auto-triggered when Billy can't answer |

### Weekly Digest Generator
Run standalone: `python3 skills/weekly-digest/generate.py --output slack`
Outputs: Formatted Slack message with volume, top campaigns, contests, payments, anomalies.
JSON output: `python3 skills/weekly-digest/generate.py --output json`

### Campaign Content Packaging ⭐ NEW (CAI-76)
**Purpose:** Package campaign media URLs into shareable Google Sheets organized by brand/campaign structure.

**Usage:**
```bash
cd /root/.openclaw/workspace/clawdbots/agents/billy/workspace
bash skills/campaign-content/scripts/package-campaign-content.sh CAMPAIGN_ID [approved|rejected|pending|all]
```

**Status filters:**
- `approved` — Only approved content
- `rejected` — Only rejected/refused content
- `pending` — Awaiting moderation
- `all` — Everything (default)

**Output:**
- Google Sheet URL (shareable, view-only)
- Columns: Media ID, Tipo (Vídeo/Imagem), Status, URL de Download, Thumbnail, Moderado em
- Auto-titled: `[Brand Name] Campaign Name - Status`
- Statistics: total count, video/image breakdown

**Response template:**
> ✅ Prontinho! Criei uma planilha com os conteúdos **[STATUS]** da campanha **[CAMPAIGN]**
> 
> 🔗 [GOOGLE_SHEETS_URL]
> 
> 📊 **[COUNT] conteúdos** organizados por tipo e data
> - 🎥 [N] vídeos
> - 🖼️ [N] imagens
> 
> 💡 **Como usar:**
> - Você pode baixar os arquivos diretamente pelos links na coluna "URL de Download"
> - Use a coluna "Thumbnail" para visualizar antes de baixar
> - A planilha é compartilhável com qualquer pessoa que tenha o link

**Finding campaigns:**
If user gives campaign name (not ID):
```bash
mysql -e "SELECT c.id, c.title, b.name FROM campaigns c JOIN brands b ON b.id = c.brand_id WHERE c.title LIKE '%SEARCH%' ORDER BY c.created_at DESC LIMIT 5;"
```

**Integration status:**
- ✅ MySQL queries working
- ✅ Google Sheets export via `sheets-export` skill
- ✅ Auto-organization by brand/campaign
- ⚠️ Requires gog auth configured (use Anton's keyring)
- 🔄 Future: Direct Drive folder creation with file uploads

## Query Safety Rules

1. **READ ONLY** — Never run DDL or DML
2. **LIMIT everything** — Default LIMIT 100
3. **No PII in responses** — Mask creator names, emails
4. **Time-bound queries** — Always add date filters
5. **Simplify output** — Billy translates SQL results to business language

## Audio Transcription (Gemini API)

**Engine:** Google Gemini 2.5 Flash (native audio support)
**Input:** Audio files (M4A, MP3, WAV, FLAC, OGG, AAC)
**Output:** Text transcription (auto-detects language)
**Accuracy:** High for clear audio, automatic punctuation

### Quick Command
```bash
# Transcribe audio file
./workspace/skills/audio-transcription/transcribe.sh <audio-file-path>

# Example
./workspace/skills/audio-transcription/transcribe.sh /tmp/voice-message.m4a

# Save to file
./workspace/skills/audio-transcription/transcribe.sh audio.m4a --output transcription.txt
```

### When to Use
- Voice messages in Slack DMs
- Audio files shared by users
- Meeting recordings needing text summaries
- Any audio content that needs to be searchable/readable

### Common Flow
1. User sends voice message via Slack
2. Billy downloads the file to `/tmp/` or OpenClaw media inbound
3. Run transcription script
4. Respond with transcribed text (and optionally summarize)

### API Key
Already configured in Billy's .env as `GEMINI_API_KEY`

## Linear — Task Progress Logging

**Workspace:** caio-tests (same as Anton)
**Team:** CAI (Caio-tests)
**API Key:** Configured in .env
**Default team:** CAI

### Purpose
Log Billy's task progress, experiments, and results to Linear task comments — matching Anton's workflow.

### Quick Commands
```bash
# Source env first
source /root/.openclaw/workspace/clawdbots/agents/billy/.env

# Log progress to a task
./workspace/skills/linear/scripts/linear.sh comment <TASK-ID> "Progress update text"

# Check task details
./workspace/skills/linear/scripts/linear.sh issue <TASK-ID>

# Update task status
./workspace/skills/linear/scripts/linear.sh status <TASK-ID> <todo|progress|blocked|done>
```

### When to Log
- **Start of work:** Update status to `progress`
- **Key milestones:** Comment with results/findings
- **Blockers:** Update status to `blocked` with explanation
- **Completion:** Update status to `done` with summary

### Comment Format
```markdown
**[Billy] Progress Update**

**What:** Brief description of work done
**Results:** Key findings or outcomes
**Next:** What's coming next (if applicable)
```

### Workspace Isolation
Billy's workspace: `/root/.openclaw/workspace/clawdbots/agents/billy/workspace/`
Anton's workspace: `/root/.openclaw/workspace/`

**NEVER** read from or write to Anton's workspace. All Billy's work stays in his isolated directory.

## CRITICAL: API-First Rule (2026-03-06)

**NEVER do direct DB inserts/updates/deletes. ALWAYS use CreatorAds API.**

- READ (SELECT) from MySQL → OK
- WRITE operations → MUST go through campaign-manager-api endpoints
- If no endpoint exists → mark as blocked, request API endpoint
- Campaign Manager API base: campaign-manager-api (Go/Gin, /v1 routes)
- Auth: Bearer token + role-based access (Admin, Editor, Approver, Viewer)

Key endpoints:
- POST /v1/campaigns — create
- GET /v1/campaigns — list
- POST /v1/campaigns/:id/groups — create groups
- POST /v1/campaigns/:id/creators/:id/payments — payments
- GET /v1/brands/:id/boost/configuration — boost config
