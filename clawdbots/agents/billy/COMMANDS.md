# Billy Commands & Capabilities

**Last Updated:** 2026-03-05

Billy responds to natural language in **pt-BR** (Portuguese). These are example phrases that trigger each skill.

---

## 📊 Data Queries (General)

**Skill:** `data-query`
**What it does:** Answers business questions by querying MySQL and translating results to plain language.

### Examples:

```
"Quantos conteúdos foram moderados essa semana?"
"Qual a taxa de aprovação dos últimos 30 dias?"
"Me mostra os dados de moderação de ontem"
"Quantos conteúdos foram recusados no último mês?"
"Taxa de aprovação por dia nos últimos 7 dias"
"Quais marcas tiveram mais conteúdo moderado esse mês?"
```

**What Billy returns:**
- Plain-language summary with numbers
- Percentages, totals, and comparisons
- Context ("a taxa está 3% acima da semana anterior")
- Charts/tables when appropriate

---

## 🎯 Campaign Lookup

**Skill:** `campaign-lookup`
**What it does:** Quick status and performance checks for specific campaigns.

### Examples:

```
"Status da campanha Summer Vibes"
"Me mostra a performance da campanha X"
"Quantas campanhas estão ativas agora?"
"Campanhas publicadas essa semana"
"Quais campanhas da marca Renault estão ativas?"
"Campanha X teve quantos conteúdos aprovados?"
```

**What Billy returns:**
- Campaign status (active/draft/completed)
- Volume (total moderated)
- Approval rate
- Contest rate
- Date ranges
- Brand info

---

## ⚖️ Campaign Comparison

**Skill:** `campaign-compare`
**What it does:** Side-by-side comparison of campaign performance.

### Examples:

```
"Compara campanha X vs campanha Y"
"Qual campanha performou melhor: A ou B?"
"Compara todas as campanhas da marca McDonald's"
"Campanha X vs média da plataforma"
"Performance de [campanha] comparada com o resto"
```

**What Billy returns:**
- Side-by-side metrics (volume, approval, contest, creators)
- Budget efficiency (content per R$)
- Refusal reason comparison
- "Veredito" with insights (which performed better and why)

---

## 👥 Creator & Payment Analytics

**Skill:** `creator-analytics`
**What it does:** Insights into creator participation and payment activity.

### Examples:

```
"Quantos creators ativos temos?"
"Creators que participaram da campanha X"
"Total de pagamentos do mês"
"Quanto foi pago em fevereiro?"
"Pagamentos por campanha nos últimos 30 dias"
"Status dos pagamentos da campanha Y"
"Creators mais ativos da plataforma"
"Quantos creators foram pagos essa semana?"
```

**What Billy returns:**
- Creator counts (active by time period)
- Payment totals (by month, by campaign)
- Payment status breakdown (complete/partial/in_process)
- Currency conversions (BRL/USD)
- Creator participation stats
- **Privacy-safe:** Creator IDs are anonymized in group channels

**Important:** Billy NEVER exposes creator names, emails, or payment details in group channels. DMs only.

---

## 📅 Weekly Digest

**Skill:** `weekly-digest`
**What it does:** Comprehensive weekly platform summary with 7 data sections + anomaly detection.

### Examples:

```
"Gera o resumo semanal"
"Weekly report da plataforma"
"Como foi a semana passada?"
"Resumo da última semana"
"Digest semanal"
```

**What Billy returns:**
- **Volume Overview:** Week-over-week comparison (total moderated, approved, refused)
- **Top Campaigns:** 10 campaigns with most volume
- **New Campaigns:** Published this week
- **Contest Activity:** Overall contest rate + most contested campaigns
- **Payment Activity:** Creators paid, total amounts
- **Daily Trends:** Day-by-day volume/approval/contests
- **Anomalies:** Flags for drops/spikes (⚠️ for issues, 🎉 for wins)

**Delivery:** Formatted Slack message (bullet lists, no tables)

---

## 📊 PowerPoint Generation

**Skill:** `powerpoint`
**What it does:** Creates branded `.pptx` presentations from data.

### Examples:

```
"Faz uma apresentação da campanha [nome]"
"Cria um report semanal em PowerPoint"
"Gera um brand review da [marca]"
"Apresentação executiva da plataforma"
"Report da campanha X pra reunião de amanhã"
```

### Templates Available:

| Template | Slides | Use Case |
|----------|--------|----------|
| `campaign-report` | 5 slides | Performance summary for a specific campaign |
| `weekly-digest` | 4 slides | Cross-campaign metrics for the week |
| `brand-review` | 4 slides | Deep dive for a specific brand's campaigns |
| `executive-summary` | 4 slides | High-level KPIs for leadership |

**What Billy returns:**
- Uploads `.pptx` file to Slack
- Branded with Brandlovrs colors (purple/orange/green)
- Charts and visual data (when Gemini API is configured)
- pt-BR narratives (when Gemini API is configured)
- Structured data only (without Gemini API)

**Slide Structure:**
- Title slide with campaign/brand name
- KPI summary with metrics
- Charts (volume trends, approval rates)
- Refusal reason breakdown
- Next steps / recommendations

---

## 🤔 Uncertainty Handling

**Skill:** `ask-human`
**What it does:** When Billy doesn't have the answer, he admits it and escalates to humans.

### What triggers this:

```
"Qual o CPM das campanhas?"
"Quantas visualizações teve a campanha X?"
"ROI das campanhas de TikTok"
"Dados de conversão por plataforma"
```

**What Billy does:**
1. Searches his tools and schemas first
2. If no data found: "Não tenho essa informação nos dados que acesso."
3. Posts to `#billy-questions` with an anonymized question
4. When someone answers in the thread, Billy delivers the answer to the original requester
5. Logs the answer to `memory/learned-from-humans.md` for future reference

**Privacy rules:**
- From DMs → ALWAYS anonymize/redact sensitive info
- From group channels → OK to include context, still redact PII
- NEVER include: names, revenue, specific metrics from private chats

---

## 📋 Query Capabilities Summary

### MySQL Tables Billy Can Query:

| Table | What's Inside |
|-------|---------------|
| `proofread_medias` | Content moderation results (approved/refused, guidelines, audio quality) |
| `campaigns` | Campaign details (name, brand, status, dates) |
| `actions` | Creator content submissions |
| `media_content` | Raw media files and metadata |
| `creator_payment_history` | Payment records (amounts, dates, status) |
| `brands` | Brand accounts |
| `moments` | Campaign phases/moments |
| `ads` | Individual ad units within moments |
| `creator_groups` | Creator batches invited to campaigns |
| `proofread_guidelines` | Moderation guidelines |
| `proofread_media_contest` | Contest/appeal records |

**Access level:** READ ONLY (SELECT queries only)

### BigQuery Datasets Billy Can Query:

| Dataset | What's Inside |
|---------|---------------|
| `analytics` | Event tracking, user behavior, funnel metrics |
| `guardian` | Moderation traces for deeper analysis |

**Access level:** `bigquery.dataViewer` + `bigquery.jobUser`

---

## 🛡️ Safety & Privacy Rules

### What Billy NEVER Does:
- ❌ Modify data (INSERT/UPDATE/DELETE)
- ❌ Expose creator PII (names, emails, phone numbers)
- ❌ Share payment details in group channels
- ❌ Guess or hallucinate data
- ❌ Make up numbers when unsure
- ❌ Run queries without `deleted_at IS NULL` filters

### What Billy ALWAYS Does:
- ✅ Admits when he doesn't know
- ✅ Cites data sources ("Dados do MySQL, tabela campaigns")
- ✅ Explains context, not just raw numbers
- ✅ Anonymizes sensitive info in public channels
- ✅ Asks clarifying questions when requests are ambiguous
- ✅ Simplifies SQL results to business language

---

## 🎭 Communication Style

- **Language:** pt-BR by default (English for code/technical docs)
- **Tone:** Warm, approachable, never condescending
- **Format:** Lead with insight, then numbers
- **Analogies:** Uses plain language explanations
- **Emojis:** Sparingly but naturally (📊 📈 ✅ 🎉)
- **Numbers:** Rounded ("~12 mil" not "12,347")
- **Tables:** Avoid in Slack — use bullet lists instead

### Example Responses:

**Good:**
> "Na última semana, 2.847 conteúdos foram moderados com taxa de aprovação de 78,3%. Aprovados: 2.231 | Recusados: 616. A taxa está 3% acima da semana anterior — boa tendência! 📈"

**Bad:**
> "SELECT COUNT(*) FROM proofread_medias WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) returns 2847 rows"

---

## 🔧 Advanced Usage

### Combining Multiple Questions:

```
"Me mostra o volume da campanha X nos últimos 7 dias e compara com a campanha Y"
```

Billy will:
1. Query both campaigns
2. Compare metrics
3. Provide side-by-side analysis

### Time Filters:

Billy understands:
- "hoje", "ontem", "essa semana", "último mês"
- "últimos 7 dias", "últimos 30 dias"
- "fevereiro", "Q1 2026"
- Specific dates: "1 de março até hoje"

### Aggregations:

```
"Taxa de aprovação por marca nos últimos 30 dias"
"Top 5 campanhas com mais conteúdo esse mês"
"Pagamentos agrupados por moeda"
```

---

## 📞 How to Interact with Billy

### In DMs (Private):
- Full access to creator/payment data
- Detailed responses
- Can share sensitive metrics
- Billy won't post your questions to #billy-questions if they contain PII

### In Channels (Team):
- Mention Billy: `@Billy quantos creators ativos temos?`
- Billy will respond publicly
- Creator data is anonymized
- No payment details in group channels

### Expected Response Time:
- **Data queries:** 2-10 seconds
- **PowerPoint generation:** 10-30 seconds
- **Weekly digest:** 15-30 seconds (7 queries)
- **Uncertainty escalation:** Instant reply + human thread response (variable)

---

## 🐛 What to Do if Billy Doesn't Work

### Billy Not Responding:
1. Check he's online (green dot in Slack)
2. Try mentioning: `@Billy hello`
3. Check logs: `docker logs -f billy` (or K8s equivalent)

### Wrong Data / Errors:
1. Tell Billy: "Isso parece errado" — he'll re-check
2. Ask for the source: "De onde você tirou esse dado?"
3. Report to #billy-questions with details

### Billy Says "I Don't Know" but You Think He Should:
1. Check if the data exists in his tables (see Query Capabilities above)
2. If yes, ask more specifically: include table/column names
3. If no, that's correct behavior — Billy won't guess

---

## 📚 Learn More

- **Full deployment docs:** `DEPLOYMENT.md`
- **Agent personality:** `workspace/SOUL.md`
- **Data schemas:** `workspace/TOOLS.md`
- **Skill details:** `workspace/skills/*/SKILL.md`

---

**Billy is ready to help! Just ping him in Slack.** 🤖✨
