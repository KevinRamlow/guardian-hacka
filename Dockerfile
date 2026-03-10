FROM node:22-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/fonsecabc/replicants-anton"
LABEL org.opencontainers.image.description="Anton OpenClaw Gateway — AI Orchestrator"

# System tools used by Anton's scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl jq git bash coreutils ca-certificates gnupg python3 \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw
RUN npm install -g openclaw@2026.3.8

# Create directory structure
RUN mkdir -p /home/node/.openclaw/workspace \
             /home/node/.openclaw/tasks/agent-logs \
             /home/node/.openclaw/tasks/spawn-tasks \
             /home/node/.openclaw/hooks \
    && chown -R node:node /home/node/.openclaw

# Copy platform config (secrets come from env vars, NOT baked in)
COPY --chown=node:node openclaw.json /home/node/.openclaw/openclaw.json
COPY --chown=node:node hooks/ /home/node/.openclaw/hooks/
COPY --chown=node:node docker-entrypoint.sh /home/node/docker-entrypoint.sh
RUN chmod +x /home/node/docker-entrypoint.sh

# Copy main workspace (scripts, config, templates, agent definitions)
COPY --chown=node:node workspace/ /home/node/.openclaw/workspace/

# Build sub-agent role workspaces from templates
RUN bash /home/node/.openclaw/workspace/scripts/setup-workspaces.sh

USER node
WORKDIR /home/node

ENV OPENCLAW_HOME=/home/node/.openclaw
ENV NODE_ENV=production
ENV GATEWAY_PORT=18789
ENV GATEWAY_BIND=lan

EXPOSE 18789

ENTRYPOINT ["/home/node/docker-entrypoint.sh"]
CMD ["gateway"]
