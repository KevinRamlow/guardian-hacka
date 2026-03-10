# Workspace Directory Layout

```
~/.openclaw/                          # OpenClaw root (managed by framework)
├── openclaw.json                     # Gateway config (hot-reloaded)
├── start.sh / stop.sh                # Lifecycle
├── tasks/                            # SINGLE SOURCE OF TRUTH for all task state
│   ├── state.json                    #   Central state machine (task-manager.sh owns this)
│   ├── process-registry.json         #   Long-running process tracking
│   ├── agent-logs/                   #   Per-agent: output.log, stderr.log, activity.jsonl, exit-code
│   ├── spawn-tasks/                  #   Task prompt files injected to agents
│   ├── backlog/                      #   Auto-queue backlog
│   ├── dedup/                        #   Deduplication cache
│   └── checkpoints/                  #   Checkpoint state
├── workspace/                        # MAIN WORKSPACE (git-tracked)
│   ├── SOUL.md                       #   Identity + rules
│   ├── AGENTS.md                     #   Boot sequence for all agents
│   ├── MEMORY.md                     #   Long-term curated knowledge
│   ├── HEARTBEAT.md                  #   Proactive task checklist
│   ├── IDENTITY.md / USER.md / TOOLS.md / README.md
│   ├── scripts/                      #   All management scripts (single source)
│   │   └── .archive/                 #   Deprecated scripts (never delete, archive)
│   ├── config/                       #   JSON configs (auto-queue, timeout-rules, review-config)
│   ├── skills/                       #   Skill modules (each has SKILL.md)
│   ├── knowledge/                    #   Codemaps, patterns, best practices (shared via symlink)
│   ├── templates/                    #   PRD, TASK, VALIDATION templates + claude-md/
│   ├── memory/                       #   Daily notes: YYYY-MM-DD.md + state files
│   ├── dashboard/                    #   Web cockpit (Express + WS, port 8765)
│   ├── workflows/                    #   YAML workflow definitions
│   ├── self-improvement/             #   Auto-loop infrastructure
│   ├── docs/                         #   Architecture docs, setup guides
│   ├── metrics/                      #   Performance metrics JSON
│   ├── presentations/                #   Generated images, slides, org charts
│   │   └── slides/                   #   Individual slide images
│   ├── guardian-agents-api-real/     #   Guardian repo clone (gitignored, has own .git)
│   ├── clawdbots/                    #   Billy, Neuron configs (gitignored, has own .git)
│   ├── billy-workspace/              #   Billy bot workspace (gitignored)
│   └── son-of-anton-workspace/       #   Son of Anton workspace (gitignored)
├── workspace-developer/              # Role workspace (symlinks to workspace/)
├── workspace-reviewer/               # Role workspace (symlinks to workspace/)
├── workspace-architect/              # Role workspace (symlinks to workspace/)
├── workspace-guardian-tuner/         # Role workspace (symlinks to workspace/)
├── workspace-debugger/               # Role workspace (symlinks to workspace/)
├── agents/                           # OpenClaw sub-agent infrastructure (framework-managed)
├── hooks/                            # Gateway hooks (linear-logger.js, etc.)
└── memory/ / logs/ / skills/         # OpenClaw framework dirs (don't touch)
```
