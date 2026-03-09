# Billy Intelligence Report — Slack Analysis (Jan-Mar 2026)

**Generated:** 2026-03-05
**Source:** 10,501 messages from 39 public Slack channels (60-day window)
**Task:** CAI-73

---

## Executive Summary

Billy has a massive opportunity to become the central productivity tool at Brandlovrs. Analysis of 10,501 messages across 39 channels reveals:

- **227 manual solicitations** in the `solicitacoes-cs-ops-e-boost` channel alone (≈4/day)
- **Ops team** generates 2,830+ messages, most of which involve data requests or manual processes
- **Metabase** (175 mentions), **HubSpot** (172), **planilha/sheets** (72) — tools people rely on that Billy can replace
- **Revenue/GMV** (106 mentions) and **OKR tracking** (308 mentions) are the most asked-about metrics
- Teams currently use **n8n workflows** for automation — Billy could absorb these

---

## 1. What People Discuss

### Top Topics by Volume
| Topic | Mentions | Key Channels |
|-------|----------|--------------|
| OKRs / Targets / Goals | 308 | tech-metrics, ops, sales, go-to-market |
| Revenue / GMV | 106 | revenue, sales, campaign_posts_alerts |
| Engagement metrics | 54 | ops, product_releases |
| ROI / Returns | 47 | ops, revenue |
| Budget / Spend | 38 | cx-fin-ops-campanhas |
| Churn / Retention | 25 | contact-center-backoffice |
| Cost metrics (CPM/CPC) | 25 | solicitacoes-cs-ops-e-boost |
| Campaign results | 20 | campaign_posts_alerts |
| Creator performance | 7 | ops, aquisição-creators |

### Key Discussion Themes
1. **Campaign lifecycle** — from setup → matching → content creation → Guardian review → posting → results
2. **Creator management** — acquisition, retention, performance, payments, education
3. **Brand relationships** — HubSpot deals, account strategy, budget violations
4. **Content moderation** — Guardian alerts, refusal contests, agreement rates
5. **Operational processes** — solicitations, boost, brand creation, data exports

---

## 2. What People Need (Unmet Demands)

### 2a. Manual Solicitations (227 in 60 days)
The `solicitacoes-cs-ops-e-boost` channel is a goldmine of unmet demand:

| Request Type | Count | Frequency |
|-------------|-------|-----------|
| Campaign comment base export | 92 | ~1.5/day |
| New brand creation in CreatorAds | 73 | ~1.2/day |
| Content request/download | 40 | ~0.7/day |
| Boost spreadsheet creation | 14 | ~0.2/day |
| Screen time / view time report | 8 | ~0.1/day |
| **TOTAL** | **227** | **~3.8/day** |

**All of these are currently manual processes** where ops people fill out Slack workflows and wait for someone to process them.

### 2b. Data Requests People Make
- "Quantos creators estão na campanha X?"
- "Qual a taxa de aprovação da campanha Y?"
- "Preciso da planilha de boost para marca Z"
- "Base de comentários da campanha W"
- Campaign performance metrics for client presentations
- Weekly OKR status tracking
- Creator engagement/screen time data

### 2c. Reports Currently Automated (via n8n)
- CSAT evaluations (testes-do-billy-cx) — multiple n8n workflows
- Whisper insights — escalated ticket reports by category
- Campaign post alerts — identification issues
- Guardian reports — high rejection rate alerts

### 2d. Information Gaps
- People frequently ask about campaign status in Slack instead of checking a system
- Cross-referencing HubSpot deals with campaign data requires manual work
- OKR tracking is manual — reported in Slack as text updates
- Creator performance data across platforms (IG, TikTok, YouTube) is fragmented

---

## 3. What Metrics People Care About

### Critical Business Metrics
1. **GMV / Revenue** — most discussed financial metric
2. **Approval rates** — campaign content approval/rejection
3. **Guardian agreement rate** — AI moderation accuracy
4. **Contest rates** — creators contesting rejections
5. **Campaign ROI** — return on campaign investment
6. **CPM / CPC / CPA** — cost efficiency metrics
7. **Engagement rates** — views, likes, comments on content
8. **Creator retention / churn** — keeping creators active
9. **CSAT scores** — customer satisfaction
10. **OKR progress** — quarterly goal tracking

### Metrics by Team
- **Sales:** Deal pipeline, faturamento, account strategy, geo-location data
- **Ops:** Campaign status, creator counts, approval rates, content delivery
- **CS/CX:** CSAT, ticket escalation, support topics, creator complaints
- **Product:** Feature adoption, release impact, matchmaking quality
- **Revenue:** GMV targets, take rates, revenue per campaign

---

## 4. Processes People Follow

### Campaign Lifecycle (most common workflow)
1. Sales closes deal in HubSpot → campaign created in CreatorAds
2. Matchmaking finds creators → brand reviews
3. Creators produce content → uploaded to platform
4. Guardian AI reviews content → approve/reject
5. Ops handles rejections/contests → manual review
6. Content posted → social metrics collected
7. Results compiled → presentation for client

### Recurring Operational Processes
1. **Boost spreadsheets** — ops creates manual boost reports per brand
2. **Comment base exports** — extracting campaign comments for brands (92 requests/2 months!)
3. **Brand onboarding** — creating new brands in CreatorAds (73 requests/2 months)
4. **Content downloads** — gathering creator content for brand review
5. **Screen time reports** — video view/retention data for clients
6. **Weekly OKR reports** — manual status updates posted in Slack
7. **Guardian case review** — daily notification of pending cases
8. **HubSpot campaign checks** — monitoring for campaign setup issues

### Tools & Integration Points
| Tool | Mentions | Role |
|------|----------|------|
| Linear | 218 | Task management (eng + product) |
| Metabase | 175 | Dashboards/BI (everyone queries) |
| HubSpot | 172 | CRM/deal management (sales + ops) |
| Notion | 97 | Documentation/PRDs |
| Resend | 86 | Email communications |
| Zendesk | 78 | Customer support tickets |
| Planilha/Sheets | 72 | Manual data exports |
| n8n | 41 | Workflow automation |

---

## 5. Billy Improvement Opportunities

### Tier 1: High-Impact Automations (replace manual Slack workflows)
These directly replace the 227 manual solicitations/2 months:
- **Campaign comment base export** — automate the 92 requests
- **Brand creation assistance** — streamline the 73 new brand requests
- **Content download/collection** — automate 40 content requests
- **Boost spreadsheet generation** — replace manual creation
- **Screen time/retention reports** — on-demand generation

### Tier 2: Data Access (replace Metabase for common queries)
- Campaign performance dashboards (approval rates, engagement, ROI)
- Creator analytics (performance, retention, payment status)
- Revenue/GMV tracking and forecasting
- OKR progress reporting
- HubSpot deal pipeline queries

### Tier 3: Proactive Intelligence
- Campaign health monitoring (flag issues before they escalate)
- Creator churn prediction
- Guardian accuracy anomaly detection
- Budget violation alerts
- Weekly automated reports (replace n8n workflows)

### Tier 4: Cross-Team Value
- Sales enablement (campaign results for pitches)
- Client presentation generation
- Go-to-market intelligence
- Brand safety reporting

---

## Raw Data

- **Channels scraped:** 39 active channels (5+ members)
- **Total messages analyzed:** 7,686 (excluding bot/join/leave)
- **Questions identified:** 623
- **Data request patterns:** 598
- **Pain point indicators:** 1,001
- **Manual process indicators:** 159
- **Billy mentions:** 11 (low awareness — opportunity for growth)

**Data stored at:** `/root/.openclaw/workspace/data/slack-analysis/`
