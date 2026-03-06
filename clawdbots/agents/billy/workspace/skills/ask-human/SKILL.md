# Ask Human — Uncertainty Escalation Skill

Post questions to `#billy-questions` when Billy can't answer from his data sources. This is a **core capability**, not a fallback — knowing when you don't know is as important as knowing.

## When to Trigger

Escalate when ANY of these are true:
- Database query returns empty/null for the requested metric
- The question is about data outside Billy's schemas (CPM, revenue, external platform metrics, etc.)
- You'd need to guess or assume to answer
- You catch yourself thinking "probably" or "I think"
- The user asks about a process/policy, not data (e.g., "what's the approval workflow?")

## Flow

### Step 1: Confirm you can't answer
Run through this checklist first:
- [ ] Checked TOOLS.md for relevant tables/schemas
- [ ] Checked skills/ for query patterns
- [ ] Ran a database query (if applicable)
- [ ] Checked `memory/learned-from-humans.md` for previous answers

If all fail → proceed to escalation.

### Step 2: Classify the source context

| Source | Privacy Level | Action |
|--------|--------------|--------|
| Group channel (#marketing, #sales) | Semi-public | Can escalate with context (redact PII) |
| DM (private conversation) | Private | **MUST anonymize or ask permission** |

### Step 3: Handle DM privacy (CRITICAL)

If the question came from a DM, check if it contains sensitive info:
- Names, companies, specific campaigns → **SENSITIVE**
- Revenue, budget, financial numbers → **SENSITIVE**
- Performance tied to specific accounts → **SENSITIVE**
- Generic "how do I find X data?" → **NOT SENSITIVE**

**If SENSITIVE, choose one:**

**Option A — Anonymize and escalate:**
```
🤔 Billy precisa de ajuda!

**Pergunta:** Alguém perguntou sobre [tipo de dado genérico] para [categoria genérica]. Onde encontro esses dados?
**Já verifiquei:** [o que Billy checou]
**Fonte:** conversa privada

Responde na thread pfv! 🙏
```

**Option B — Can't escalate, redirect:**
Tell the user directly:
> "Não tenho esse dado e como veio de uma conversa privada, não posso perguntar no canal público sem expor contexto sensível. Sugiro perguntar diretamente para [pessoa relevante]."

**Option C — Ask permission:**
> "Essa pergunta tem contexto sensível. Posso perguntar pro time de forma anônima? Tipo: 'alguém perguntou sobre [categoria] — onde encontro esses dados?'"

Wait for user confirmation before posting.

**If NOT SENSITIVE:**
Proceed with normal escalation (still don't include the person's name).

### Step 4: Post to #billy-questions

Format for the Slack message:
```
🤔 Billy precisa de ajuda!

**Pergunta:** [question — anonymized if from DM]
**Contexto:** [what sources Billy checked, what he found/didn't find]
**Fonte:** [#channel-name or "conversa privada"]

Responde na thread pfv! 🙏
```

### Step 5: Tell the requester

> "Não tenho esse dado nas minhas fontes. Postei uma pergunta no #billy-questions — te aviso quando alguém responder! 🔍"

### Step 6: Capture the answer

When a human replies in the thread:
1. Deliver the answer to the original requester
2. Log to `memory/learned-from-humans.md`:

```markdown
## [DATE] — [Topic]
**Question:** [original question]
**Answer:** [human's answer]
**Answered by:** [who replied]
**Source tip:** [where to find this data in the future]
```

3. If the answer reveals a new data source or query pattern → consider updating TOOLS.md or creating a new skill query pattern.

## Example Interactions

### Example 1: Data outside schemas (from group channel)
> **User in #marketing:** "Qual o CPM das campanhas de TikTok no Q3?"
>
> **Billy:** [checks MySQL — no CPM column, no platform column]
> **Billy:** "Não tenho dados de CPM por plataforma nas minhas fontes (MySQL/BigQuery). Vou perguntar pro time onde encontro isso."
> **Billy → #billy-questions:**
> "🤔 Billy precisa de ajuda!
> **Pergunta:** Onde encontro dados de CPM por plataforma (ex: TikTok)?
> **Já verifiquei:** MySQL db-maestro-prod (tabelas campaigns, actions, proofread_medias) — nenhuma tem CPM ou plataforma.
> **Fonte:** #marketing
> Responde na thread pfv! 🙏"

### Example 2: Sensitive DM question
> **User in DM:** "Quanto a Natura gastou na campanha Summer Vibes?"
>
> **Billy:** [checks DB — no spend/budget data]
> **Billy → user:** "Não tenho dados de investimento/gasto por campanha. Isso é sensível — posso perguntar pro time de forma anônima? Tipo: 'onde encontro dados de budget por campanha?'"
> **User:** "pode sim"
> **Billy → #billy-questions:**
> "🤔 Billy precisa de ajuda!
> **Pergunta:** Onde encontro dados de budget/investimento por campanha?
> **Já verifiquei:** MySQL db-maestro-prod — nenhuma tabela tem coluna de budget/spend.
> **Fonte:** conversa privada
> Responde na thread pfv! 🙏"

### Example 3: Can't escalate
> **User in DM:** "A taxa de aprovação da campanha X da empresa Y tá muito baixa, o que tá acontecendo?"
>
> **Billy:** [runs query, finds the data in DB]
> **Billy:** "Encontrei! A campanha X teve taxa de aprovação de 62% nos últimos 7 dias..."
> *(No escalation needed — Billy found the data)*

### Example 4: Process question
> **User:** "Como funciona o fluxo de contestação?"
>
> **Billy:** "Isso é uma pergunta sobre processo, não sobre dados — não tenho documentação sobre fluxos internos. Sugiro perguntar no #tech-gua-ma-internal ou para o Manoel que conhece o sistema de contestação."
> *(Direct redirect, no #billy-questions post needed for process questions)*
