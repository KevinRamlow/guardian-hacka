# TODO: pin to digest for supply chain safety: FROM node:22-bookworm-slim@sha256:<digest>
FROM node:22-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/brandlovers-team/replicants-sentinel"
LABEL org.opencontainers.image.description="Sentinel OpenClaw Gateway — Guardian Agreement Rate Optimizer"

# System tools used by Sentinel's scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl jq git bash coreutils ca-certificates gnupg python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies for few-shot database
RUN pip3 install --break-system-packages sqlite-vec google-generativeai

# Copy build scripts (Slack retry patch) before npm install
COPY scripts/patch-slack-retry.sh /scripts/patch-slack-retry.sh
RUN chmod +x /scripts/patch-slack-retry.sh

# Install latest OpenClaw + mcporter + fix permissions + apply Slack retry patch
RUN npm install -g openclaw@latest mcporter \
    && chown -R node:node /usr/local/lib/node_modules/openclaw/extensions/ \
    && /scripts/patch-slack-retry.sh

# Create directory structure
RUN mkdir -p /home/node/.openclaw/workspace \
             /home/node/.openclaw/workspace/memory \
             /home/node/.openclaw/tasks/agent-logs \
             /home/node/.openclaw/tasks/spawn-tasks \
             /home/node/.openclaw/hooks \
             /home/node/.openclaw/agents/main/sessions \
    && chown -R node:node /home/node/.openclaw

# Copy platform config (secrets come from env vars, NOT baked in)
COPY --chown=node:node openclaw.json /home/node/.openclaw/openclaw.json
COPY --chown=node:node hooks/ /home/node/.openclaw/hooks/
COPY --chown=node:node docker-entrypoint.sh /home/node/docker-entrypoint.sh
RUN chmod +x /home/node/docker-entrypoint.sh

# Copy main workspace (scripts, config, templates, agent definitions)
COPY --chown=node:node workspace/ /home/node/.openclaw/workspace/

# Install dashboard dependencies and build UI
RUN cd /home/node/.openclaw/workspace/dashboard \
    && npm install --production --silent \
    && cd ui && npm install --silent && npm run build && rm -rf node_modules \
    && chown -R node:node /home/node/.openclaw/workspace/dashboard

# Build sub-agent role workspaces from templates
RUN OPENCLAW_HOME=/home/node bash /home/node/.openclaw/workspace/scripts/setup-workspaces.sh \
    && chown -R node:node /home/node/.openclaw/workspace-*

USER node
WORKDIR /home/node

ENV OPENCLAW_HOME=/home/node
ENV NODE_ENV=production
ENV GATEWAY_PORT=18789
ENV GATEWAY_BIND=lan

EXPOSE 18789 8080

ENTRYPOINT ["/home/node/docker-entrypoint.sh"]
CMD ["gateway"]
