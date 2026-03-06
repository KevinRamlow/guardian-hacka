# Billy Agent — Build Report

**Status:** ✅ Workspace complete, locally tested
**Location:** `/root/.openclaw/workspace/clawdbots/agents/billy/`
**Created:** 2026-03-05

---

## What Billy Is

Billy is the **non-tech team helper** — a friendly data assistant for marketing, sales, ops, and leadership at Brandlovrs. He does two things:

1. **Data queries** — Answers business questions in plain language by querying MySQL/BigQuery
2. **Presentations** — Generates branded `.pptx` slides from data (campaign reports, weekly digests, etc.)

**Key trait:** Billy never guesses. When he doesn't know, he admits it and asks humans via `#billy-questions` on Slack — with strict privacy rules for DM conversations.

## What's Built

### Workspace Files
| File | Purpose |
|------|---------|
| `workspace/SOUL.md` | Personality, communication style, uncertainty rules, privacy policy |
| `workspace/TOOLS.md` | Database schemas, query patterns, Slack escalation docs |
| `workspace/AGENTS.md` | Scope definition, safety rules |

### Skills (4)
| Skill | Purpose |
|-------|---------|
| `skills/data-query/` | Translates business questions → SQL → plain-language answers |
| `skills/campaign-lookup/` | Quick campaign status/performance lookups |
| `skills/powerpoint/` | Branded .pptx generation (4 templates) with optional Gemini AI narratives |
| `skills/ask-human/` | **Core capability** — uncertainty detection, privacy-safe Slack escalation, answer logging |

### Presentation Templates (tested ✅)
- `campaign-report` — 5 slides: title, KPIs, daily trend, refusal reasons, next steps
- `weekly-digest` — 4 slides: title, weekly KPIs, top campaigns, highlights
- `brand-review` — 4 slides: title, active campaigns, performance, recommendations
- `executive-summary` — 4 slides: title, platform KPIs, trends, risks

### Infrastructure (ready, not deployed)
- `Dockerfile`, `openclaw.json`, `requirements.txt`
- K8s manifests in `k8s/` (deployment, service account, network policy, GCP SA setup)

## Testing Done

```
✅ PPTX generation — all 4 templates produce valid .pptx files
✅ Graceful degradation — works without Gemini API key (structured data only)
✅ Brand colors — purple/orange/green Brandlovrs palette
✅ python-pptx installed and working on this server
```

## What Needs Caio

### 1. Gemini API Key (for AI-enhanced presentations)
Set as environment variable:
```bash
export GEMINI_API_KEY="your-key-here"
```
Without it, presentations use structured data directly. With it, Billy generates contextual pt-BR narratives per slide.

### 2. Slack Channel Setup
Create `#billy-questions` in the Brandlovrs workspace for human escalation.

### 3. Testing Billy Locally

**Option A — Run with OpenClaw directly:**
```bash
# Point OpenClaw at Billy's workspace
cd /root/.openclaw/workspace/clawdbots/agents/billy
openclaw start --config ./openclaw.json
```

**Option B — Test the PPTX generator standalone:**
```bash
# Create a data file
cat > /tmp/test-data.json << 'EOF'
{
  "campaign_name": "Test Campaign",
  "period": "Março 2026",
  "metrics": [
    {"label": "Total", "value": "1.500", "delta": "↑ 10%"},
    {"label": "Aprovação", "value": "85%", "delta": "↑ 2%"}
  ],
  "daily_highlights": ["Volume estável", "Taxa consistente"],
  "top_refusals": ["Hashtag ausente (40%)", "Fora do briefing (30%)"],
  "next_steps": ["Revisar guidelines", "Acompanhar próxima semana"]
}
EOF

# Generate
python3 workspace/skills/powerpoint/generate.py \
  --template campaign-report \
  --data /tmp/test-data.json \
  --output /tmp/report.pptx
```

**Option C — Test with Gemini AI narratives:**
```bash
export GEMINI_API_KEY="your-key"
pip install google-generativeai
python3 workspace/skills/powerpoint/generate.py \
  --template campaign-report \
  --data /tmp/test-data.json \
  --output /tmp/report-ai.pptx
```

### 4. Deploy When Ready
K8s manifests are pre-built. When ready for GKE:
```bash
python3 cli/clawdbot.py deploy billy --env dev
```

## Privacy Design (ask-human skill)

Billy's escalation system has a strict privacy model:

| Source | Can escalate? | Rules |
|--------|--------------|-------|
| Group channel | ✅ Yes | Redact PII, OK to include business context |
| DM — non-sensitive | ✅ Yes | Don't include requester name |
| DM — sensitive data | ⚠️ Only with permission | Must anonymize: "someone asked about [category]" |
| DM — highly sensitive | ❌ No | Redirect user to ask the right person directly |

Answers from humans get logged to `memory/learned-from-humans.md` so Billy doesn't re-ask the same question.

## Example Interactions

### Data query
> **User:** "Quantos conteúdos foram aprovados essa semana?"
> **Billy:** "Na última semana, 2.847 conteúdos foram moderados com taxa de aprovação de 78,3%. Aprovados: 2.231 | Recusados: 616. A taxa está 3% acima da semana anterior — boa tendência! 📈"

### Presentation
> **User:** "Faz uma apresentação da campanha Summer Vibes pra reunião de amanhã"
> **Billy:** [queries campaign data] → [generates campaign-report .pptx] → shares file

### Uncertainty + escalation
> **User in DM:** "Qual o CPM das campanhas de TikTok no Q3?"
> **Billy:** "Não tenho dados de CPM por plataforma nas minhas fontes. Vou perguntar pro time de forma anônima."
> **Billy → #billy-questions:** "🤔 Onde encontro dados de CPM por plataforma?"
> **[Team answers in thread]**
> **Billy → User:** "Consegui! O pessoal disse que CPM fica no dashboard do Meta/TikTok Ads Manager, não no nosso banco."
