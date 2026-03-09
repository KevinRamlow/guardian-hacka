# Billy Improvement — Worker Instructions

**Generated:** 2026-03-05 from Slack analysis (CAI-73)
**Full analysis:** `/root/.openclaw/workspace/docs/billy-intelligence-report.md`
**Linear backlog:** CAI-74 through CAI-96 (23 tasks)

---

## Deployment Rules (Full Autonomy)

- Billy is **private** (only Caio's testers can use)
- **No approval checkpoints** — analyze → implement → test → deploy
- Deploy directly to Billy VM
- Only escalate for technical blockers (not design decisions)
- Pick next task immediately after completing one

---

## Top 3 Priority Tasks (Start Here)

### 🔴 P0-1: CAI-74 — Campaign Comment Base Export
**Impact:** 92 manual Slack requests in 2 months (~1.5/day)  
**What:** User asks "base de comentários da campanha [brand]" → Billy returns Google Sheets link

**Implementation:**
1. Parse campaign/brand name from user message
2. Query MySQL: `campaigns → actions → media_content` to find all posts
3. Fetch comments via social APIs (IG Graph API, TikTok) for each post URL
4. Format: post_url, creator_name, comment_text, comment_date, sentiment_score
5. Export to Google Sheets via `gog` integration
6. Return shareable link in Slack

**Tables:** campaigns, actions, media_content, proofread_medias  
**Effort:** 4-6 hours

---

### 🔴 P0-2: CAI-75 — Brand Creation in CreatorAds
**Impact:** 73 manual requests in 2 months (~1.2/day)  
**What:** User asks "criar marca [name]" → Billy creates brand and confirms

**Implementation:**
1. Parse brand name from request
2. Check MySQL `brands` table for duplicates (exact + fuzzy match)
3. If new: INSERT into brands table (name, slug, status='active')
4. If exists: return existing brand info
5. Confirm with brand ID and CreatorAds link

**Effort:** 2-3 hours

---

### 🔴 P0-3: CAI-79 — Campaign Performance Dashboard
**Impact:** Revenue/GMV = 106 mentions, ROI = 47, engagement = 54 in Slack  
**What:** User asks "como está a campanha [name]?" → Billy returns full performance snapshot

**Implementation:**
1. Find campaign by name in MySQL (support fuzzy matching)
2. Query metrics:
   - Creator stats: total matched, accepted, rejected
   - Content: submitted, approved, rejected, contest rate
   - Engagement: views, likes, comments (from social APIs)
   - Budget: spent vs allocated
   - Timeline: start, end, % complete
3. Format as clean Slack bullets (NO tables in Slack!)
4. Optional: compare with similar campaigns

**Key queries:**
```sql
-- Creator stats
SELECT COUNT(*) as total, 
  SUM(CASE WHEN status='approved' THEN 1 ELSE 0 END) as approved
FROM actions WHERE campaign_id = ?

-- Content stats  
SELECT COUNT(*) as total,
  SUM(CASE WHEN status='approved' THEN 1 ELSE 0 END) as approved,
  SUM(CASE WHEN status='rejected' THEN 1 ELSE 0 END) as rejected
FROM proofread_medias pm
JOIN actions a ON pm.action_id = a.id
WHERE a.campaign_id = ?
```

**Effort:** 3-4 hours

---

## Full Backlog (Priority Order)

### P0 — Urgent (Start immediately)
| Task | Title | Impact | Effort |
|------|-------|--------|--------|
| CAI-74 | Campaign comment base export | 92 requests/2mo | Medium |
| CAI-75 | Brand creation automation | 73 requests/2mo | Small |
| CAI-79 | Campaign performance dashboard | Most asked metric | Medium |

### P1 — High (Next batch)
| Task | Title | Impact | Effort |
|------|-------|--------|--------|
| CAI-76 | Content download & collection | 40 requests/2mo | Medium-Large |
| CAI-82 | Creator performance analytics | Fragmented data | Medium |
| CAI-93 | Google Sheets export for all queries | 72 planilha mentions | Small |
| CAI-95 | Campaign lifecycle status tracker | Common question | Medium |
| CAI-88 | Metabase query replacement | 175 Metabase mentions | Large |

### P2 — Medium (Backlog)
| Task | Title | Impact | Effort |
|------|-------|--------|--------|
| CAI-77 | Boost spreadsheet generation | 14 requests/2mo | Small |
| CAI-78 | Screen time/retention reports | 8 requests/2mo | Medium |
| CAI-80 | OKR progress tracker | 308 OKR mentions | Medium |
| CAI-81 | HubSpot deal pipeline queries | 172 HubSpot mentions | Large |
| CAI-83 | Guardian agreement rate monitor | Team critical | Medium |
| CAI-84 | Automated weekly campaign reports | Replace n8n | Medium |
| CAI-85 | Campaign health alerts | 1000+ alert msgs | Medium |
| CAI-86 | Zendesk ticket analytics | 78 Zendesk mentions | Medium |
| CAI-87 | Revenue forecasting | 106 revenue mentions | Large |
| CAI-89 | Creator churn prediction | 25 churn mentions | Large |
| CAI-90 | Sales enablement data | Sales team need | Medium |
| CAI-91 | Budget violation detection | Compliance critical | Medium |
| CAI-92 | Cross-platform creator profiles | Data unification | Large |
| CAI-94 | Refusal contest analysis | 802 contest alerts | Medium |
| CAI-96 | Proactive daily Slack digest | Replace alert channels | Medium |

---

## Technical Context

### Billy's Current Stack
- MySQL queries (campaigns, creators, actions, media)
- Presentation generation (markdown + nano-banana)
- Image generation (nano-banana)
- Linear integration
- Gmail watching
- Audio transcription
- Google Workspace (gog) integration

### Key Data Sources
- **MySQL** (db-maestro-prod): campaigns, actions, media_content, proofread_medias, brands
- **HubSpot**: deals, contacts, pipeline (API key needed)
- **Zendesk**: tickets, agents, categories
- **Social APIs**: IG Graph, TikTok, YouTube (for engagement data)
- **BigQuery**: analytics, larger aggregations

### Slack Formatting Rules
- NO markdown tables in Slack (use bullet lists)
- Wrap multiple links in `<>` to suppress embeds
- Bold for headers, short paragraphs
- Always in pt-BR for user-facing messages

---

## Key Insight

**The #solicitacoes-cs-ops-e-boost channel alone has 227 manual requests in 2 months.** That's the single biggest opportunity for Billy. Every request type there maps directly to a Billy feature. Automating just the top 3 request types (comment bases, brand creation, content downloads) would save ~3 manual processes per day.

**Billy awareness is LOW** (only 11 mentions across all channels). Once these automations are in place, Billy needs visibility — consider posting in #ops and #only-ops-team about new capabilities.
