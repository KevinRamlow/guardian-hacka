const express = require('express');
const { WebSocketServer } = require('ws');
const { execSync, exec } = require('child_process');
const http = require('http');
const path = require('path');

const PORT = 8765;
const POLL_INTERVAL = 8000; // 8s
const LINEAR_API_KEY = '[REDACTED]';

// Langfuse config
const LANGFUSE_HOST = 'https://us.cloud.langfuse.com';
const LANGFUSE_PUBLIC_KEY = '[REDACTED]';
const LANGFUSE_SECRET_KEY = '[REDACTED]';
const LANGFUSE_AUTH = Buffer.from(`${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}`).toString('base64');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// --- Data Store ---
let dashboardState = {
  active: [],
  recent: [],
  stats: { totalActive: 0, completedToday: 0, totalTokensToday: 0, estimatedCostToday: 0 },
  alerts: [],
  lastUpdated: null,
};

// Track historical token data per session
const tokenHistory = new Map();
const toolCallHistory = new Map();

// --- Helpers ---
function safeExecSync(cmd, timeout = 15000) {
  try {
    return execSync(cmd, { encoding: 'utf-8', timeout, maxBuffer: 1024 * 1024 });
  } catch (e) {
    return null;
  }
}

function parseRuntime(runtimeStr) {
  if (!runtimeStr) return 0;
  const match = runtimeStr.match(/(\d+)m/);
  return match ? parseInt(match[1]) : 0;
}

function estimateTokenCost(tokens, model) {
  // Approximate costs per 1M tokens (input+output blended)
  const costs = {
    'anthropic/claude-opus-4-6': 0.03,      // ~$30/M blended
    'anthropic/claude-sonnet-4-5': 0.009,    // ~$9/M blended
    'anthropic/claude-sonnet-4-20250514': 0.009,
    'default': 0.015,
  };
  const rate = costs[model] || costs['default'];
  return (tokens * rate).toFixed(4);
}

function getHealthStatus(agent) {
  const runtimeMin = (agent.runtimeMs || 0) / 60000;
  if (agent.status === 'done' || agent.status === 'error') return { status: 'done', color: 'gray' };
  if (runtimeMin > 25) return { status: 'frozen', color: 'red', alert: `Running ${runtimeMin.toFixed(0)}min — likely frozen` };
  if (runtimeMin > 18) return { status: 'warning', color: 'orange', alert: `Running ${runtimeMin.toFixed(0)}min — approaching timeout` };
  if (runtimeMin > 10) return { status: 'aging', color: 'yellow' };
  return { status: 'healthy', color: 'green' };
}

function extractTaskId(label) {
  const match = (label || '').match(/\b(CAI-\d+)\b/);
  return match ? match[1] : null;
}

// --- Linear Integration ---
async function fetchLinearUpdates(taskIds) {
  if (!taskIds.length) return {};
  const results = {};

  for (const taskId of taskIds) {
    try {
      const query = JSON.stringify({
        query: `query {
          issues(filter: { identifier: { eq: "${taskId}" } }) {
            nodes {
              id identifier title state { name color }
              comments(last: 3) { nodes { body createdAt } }
              updatedAt
            }
          }
        }`
      });

      const response = await fetch('https://api.linear.app/graphql', {
        method: 'POST',
        headers: { 'Authorization': LINEAR_API_KEY, 'Content-Type': 'application/json' },
        body: query,
      });

      const data = await response.json();
      const issue = data?.data?.issues?.nodes?.[0];
      if (issue) {
        const lastComment = issue.comments?.nodes?.[issue.comments.nodes.length - 1];
        results[taskId] = {
          title: issue.title,
          state: issue.state?.name,
          stateColor: issue.state?.color,
          lastCommentAt: lastComment?.createdAt,
          lastCommentPreview: lastComment?.body?.substring(0, 120),
          commentCount: issue.comments?.nodes?.length || 0,
          updatedAt: issue.updatedAt,
        };
      }
    } catch (e) {
      // Skip this task
    }
  }
  return results;
}

// --- Langfuse Integration ---
let langfuseCache = { data: null, lastFetch: 0 };
const LANGFUSE_CACHE_TTL = 30000; // 30s cache

async function fetchLangfuseMetrics() {
  // Rate-limit Langfuse calls
  if (Date.now() - langfuseCache.lastFetch < LANGFUSE_CACHE_TTL && langfuseCache.data) {
    return langfuseCache.data;
  }

  try {
    // Fetch recent traces (last 1h)
    const since = new Date(Date.now() - 3600000).toISOString();
    const url = `${LANGFUSE_HOST}/api/public/traces?limit=20&orderBy=timestamp.desc`;

    const resp = await fetch(url, {
      headers: { 'Authorization': `Basic ${LANGFUSE_AUTH}` },
    });

    if (!resp.ok) {
      console.error('Langfuse API error:', resp.status);
      return null;
    }

    const body = await resp.json();
    const traces = body.data || [];

    // Calculate aggregated metrics
    let totalTokens = 0, totalCost = 0, totalLatency = 0, errors = 0;
    const recentTraces = [];

    for (const t of traces) {
      const latency = t.latency ? Math.round(t.latency * 1000) : null;
      const tokens = (t.totalTokens || t.usage?.totalTokens || 0);
      const cost = t.calculatedTotalCost || 0;

      totalTokens += tokens;
      totalCost += cost;
      if (latency) totalLatency += latency;
      if (t.level === 'ERROR') errors++;

      if (recentTraces.length < 5) {
        recentTraces.push({
          id: t.id,
          name: t.name || t.id?.substring(0, 8),
          latency,
          totalTokens: tokens,
          cost: cost.toFixed(4),
          status: t.level || 'DEFAULT',
          timestamp: t.timestamp,
        });
      }
    }

    const result = {
      totalTraces: traces.length,
      avgLatency: traces.length > 0 ? Math.round(totalLatency / traces.filter(t => t.latency).length) || 0 : 0,
      errorRate: traces.length > 0 ? ((errors / traces.length) * 100).toFixed(1) : '0',
      totalCost: totalCost.toFixed(4),
      totalTokens,
      recentTraces,
    };

    langfuseCache = { data: result, lastFetch: Date.now() };
    return result;
  } catch (e) {
    console.error('Langfuse fetch error:', e.message);
    return langfuseCache.data; // Return stale data on error
  }
}

// --- Data Collection ---
async function collectData() {
  // 1. Get subagent data from openclaw CLI
  const raw = safeExecSync('openclaw subagents list --json 2>/dev/null');
  let parsed;
  try {
    parsed = raw ? JSON.parse(raw) : { active: [], recent: [] };
  } catch {
    parsed = { active: [], recent: [] };
  }
  if (!parsed) parsed = { active: [], recent: [] };

  const active = (parsed && parsed.active) || [];
  const recent = ((parsed && parsed.recent) || []).slice(0, 10);

  // 2. Get Linear updates for all task IDs
  const allAgents = [...active, ...recent];
  const taskIds = [...new Set(allAgents.map(a => extractTaskId(a.label)).filter(Boolean))];
  const linearData = await fetchLinearUpdates(taskIds);

  // 3. Enrich agents with health, ETA, Linear data
  const enrichedActive = active.map(a => {
    const health = getHealthStatus(a);
    const taskId = extractTaskId(a.label);
    const linear = taskId ? linearData[taskId] : null;
    const runtimeMin = (a.runtimeMs || 0) / 60000;

    // Parse timeout from task description
    let timeoutMin = 25; // default
    const timeoutMatch = (a.task || '').match(/Timeout:\s*(\d+)\s*min/i);
    if (timeoutMatch) timeoutMin = parseInt(timeoutMatch[1]);

    const etaMin = Math.max(0, timeoutMin - runtimeMin);
    const progress = Math.min(100, (runtimeMin / timeoutMin) * 100);

    // Token tracking
    const cost = estimateTokenCost(a.totalTokens || 0, a.model);

    return {
      ...a,
      health,
      taskId,
      linear,
      runtimeMin: runtimeMin.toFixed(1),
      timeoutMin,
      etaMin: etaMin.toFixed(1),
      progress: progress.toFixed(0),
      cost,
      taskShort: (a.task || '').substring(0, 100),
    };
  });

  const enrichedRecent = recent.map(a => {
    const taskId = extractTaskId(a.label);
    const linear = taskId ? linearData[taskId] : null;
    const runtimeMin = (a.runtimeMs || 0) / 60000;
    const cost = estimateTokenCost(a.totalTokens || 0, a.model);

    return {
      ...a,
      taskId,
      linear,
      runtimeMin: runtimeMin.toFixed(1),
      cost,
      success: a.status === 'done',
    };
  });

  // 4. Calculate stats
  const allRecent = enrichedRecent;
  const completedToday = allRecent.filter(a => a.status === 'done').length;
  const failedToday = allRecent.filter(a => a.status === 'error' || a.status === 'timeout').length;
  const totalTokensToday = allAgents.reduce((sum, a) => sum + (a.totalTokens || 0), 0);
  const estimatedCostToday = allAgents.reduce((sum, a) => sum + parseFloat(estimateTokenCost(a.totalTokens || 0, a.model)), 0);

  // 5. Build alerts
  const alerts = enrichedActive
    .filter(a => a.health.alert)
    .map(a => ({
      level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING',
      agent: a.label,
      taskId: a.taskId,
      message: a.health.alert,
      timestamp: new Date().toISOString(),
    }));

  // 6. Fetch Langfuse metrics
  const langfuseData = await fetchLangfuseMetrics();

  dashboardState = {
    active: enrichedActive,
    recent: enrichedRecent,
    langfuse: langfuseData,
    stats: {
      totalActive: enrichedActive.length,
      completedToday,
      failedToday,
      totalTokensToday,
      estimatedCostToday: estimatedCostToday.toFixed(4),
      avgRuntimeMin: allRecent.length > 0
        ? (allRecent.reduce((s, a) => s + parseFloat(a.runtimeMin), 0) / allRecent.length).toFixed(1)
        : '0',
    },
    alerts,
    lastUpdated: new Date().toISOString(),
  };

  return dashboardState;
}

// --- WebSocket Broadcast ---
function broadcast(data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(msg);
  });
}

// Poll and broadcast
async function pollAndBroadcast() {
  try {
    const data = await collectData();
    if (data) broadcast({ type: 'update', data });
  } catch (e) {
    console.error('Poll error:', e.message);
    // Broadcast last known good state
    if (dashboardState.lastUpdated) broadcast({ type: 'update', data: dashboardState });
  }
}

// --- WebSocket Handlers ---
wss.on('connection', (ws) => {
  // Send current state immediately
  ws.send(JSON.stringify({ type: 'update', data: dashboardState }));

  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw);

      if (msg.action === 'kill' && msg.sessionKey) {
        safeExecSync(`openclaw subagents kill "${msg.sessionKey}" 2>/dev/null`);
        await pollAndBroadcast();
      }

      if (msg.action === 'steer' && msg.sessionKey && msg.message) {
        safeExecSync(`openclaw subagents steer "${msg.sessionKey}" "${msg.message.replace(/"/g, '\\"')}" 2>/dev/null`);
        await pollAndBroadcast();
      }

      if (msg.action === 'refresh') {
        await pollAndBroadcast();
      }
    } catch (e) {
      ws.send(JSON.stringify({ type: 'error', message: e.message }));
    }
  });
});

// --- Static Files ---
app.use(express.static(path.join(__dirname, 'public')));

// --- API endpoints (fallback for non-WS) ---
app.get('/api/state', (req, res) => res.json(dashboardState));

// --- Start ---
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🦞 Anton Dashboard running on http://0.0.0.0:${PORT}`);
  // Initial poll
  pollAndBroadcast();
  // Start polling loop
  setInterval(pollAndBroadcast, POLL_INTERVAL);
});
