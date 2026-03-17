---
name: skill-creator
description: >
  Create or update skills for your own workspace. Use when Caio asks to add a new skill,
  improve an existing one, or when you identify a recurring workflow that should be a skill.
  Triggers: "create skill", "new skill", "add skill", "update skill", "improve skill".
---

# Skill Creator

You create skills for YOUR OWN workspace (`~/.openclaw/workspace/skills/`).
Skills are specialized instruction sets that make you better at specific tasks.

---

## Skill Structure

```
skills/<name>/
├── SKILL.md          — Required. Frontmatter (name, description) + instructions
├── scripts/          — Optional. Executable code (bash/python)
├── references/       — Optional. Documentation loaded as needed
└── assets/           — Optional. Files used in output
```

## When to Create a Skill

- Caio explicitly asks for one
- You identify a recurring workflow (3+ times) with specific domain knowledge
- A task requires tool-specific instructions that don't belong in SOUL.md

## Creation Process

1. **Understand the use case** — What triggers this skill? What does success look like?
2. **Check for existing skills** — `ls skills/` — don't duplicate
3. **Create the directory** — `mkdir -p skills/<name>`
4. **Write SKILL.md** with:
   - YAML frontmatter: `name` and `description` (description = primary trigger mechanism)
   - Body: concise instructions, not essays. Claude is smart — only add what's non-obvious
5. **Add resources** if needed — scripts for deterministic tasks, references for domain knowledge
6. **Test it** — Invoke the skill mentally and check if the instructions are sufficient

## SKILL.md Template

```markdown
---
name: <slug>
description: >
  <What the skill does and when to use it. Include trigger phrases.>
---

# <Title>

<Role statement — what you become when this skill activates>

---

## Instructions

<Step-by-step procedure, decision rules, output format>

---

## Guardrails

<What NOT to do, edge cases, confirmation gates>

---

## Your Task

$ARGUMENTS
```

## Key Principles

- **Concise over verbose.** Context window is shared. Only add what Claude doesn't already know.
- **Progressive disclosure.** Keep SKILL.md under 500 lines. Split details into `references/`.
- **Match freedom to fragility.** Fragile operations need specific scripts. Open-ended tasks need guidelines.
- **No README, CHANGELOG, or docs files.** Skills are for AI agents, not humans.
- **Description is the trigger.** Put all "when to use" info in the YAML description, not the body.
- **Test scripts by running them.** Don't ship untested code.

## Your Task

$ARGUMENTS
