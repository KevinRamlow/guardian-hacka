FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Install OpenClaw
RUN npm install -g openclaw@latest

# Create directories
RUN mkdir -p /workspace /root/.openclaw

# Set working directory
WORKDIR /workspace

# Expose Billy's port (18790)
EXPOSE 18790

# Start Billy's gateway (direct node process, no systemd)
CMD ["sh", "-c", "cd /workspace && node /usr/lib/node_modules/openclaw/dist/gateway/index.js"]
