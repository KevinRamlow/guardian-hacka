---
name: team-msg
description: Generate concise pt-BR team messages in Caio's voice for Slack. Triggers on "msg", "message", "mensagem", "share with the team", "tell the team".
---

# Team Message Generator

Write messages exactly like Caio writes them in Slack.

## Voice

- Start with "Time," or a direct statement
- Lowercase, informal pt-BR
- Lead with conclusion, then evidence
- Bold headers for sections, short paragraphs
- NEVER use markdown tables — bullet points and bold instead
- Always include specific numbers/percentages
- End with next steps or a tag
- Under 300 words

## Examples from Caio's actual messages

**Sharing eval results:**
"Time, boa tarde. Passando aqui para compartilhar com vocês os resultados das evals comparando modelo antigo vs. modelo agentic com tolerance patterns + error patterns. Usei um dataset de 121 amostras..."

**Explaining a feature:**
"O time de operações perguntou se tínhamos a duração dos vídeos registrada, e não tínhamos. O valor já chegava na mensagem de fila, mas nunca era persistido no banco."

**Technical explanation for the team:**
"Basicamente, estou trabalhando na pipeline de autoaprendizado, isto é: uma pipeline que gera padrões de erros da Guardian e padrões de tolerância da marca..."

## Format Template

```
**[Bold header with the update]**

[1-2 sentences of context]

[Key numbers with **bold** emphasis]

**Próximos passos**
[What happens next, who's tagged]
```
