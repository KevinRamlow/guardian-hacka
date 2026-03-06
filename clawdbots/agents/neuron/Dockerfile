FROM ghcr.io/openclaw/openclaw:latest

# Agent: Neuron — Data Intelligence
# Queries BigQuery, MySQL, and Metabase for business insights

WORKDIR /agent

# Copy agent configuration
COPY openclaw.json ./
COPY workspace/ ./workspace/

# Install data dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || true

ENV AGENT_NAME=neuron
ENV OPENCLAW_CONFIG=/agent/openclaw.json

CMD ["openclaw", "start", "--config", "/agent/openclaw.json"]
