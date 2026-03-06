const express = require('express');
const { WebSocketServer } = require('ws');
const { execSync, exec } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

const PORT = 8765;
const POLL_INTERVAL = 8000; // 8s
const LINEAR_API_KEY = '[REDACTED]';
const STATS_FILE = '/root/.openclaw/workspace/dashboard/stats-history.json';

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
  stats: { totalActive: 0, completedToday: 0, failedToday: 0, totalTokensToday: 0, estimatedCostToday: 0 },
  alerts: [],
  lastUpdated: null,
};

// Persistent stats structure
let persistentStats = {
  date: new Date().toISOString().split('T')[0], // YYYY-MM-DD
  completedToday: 0,
  failedToday: 0,
  totalTokensToday: 0,
  estimatedCostToday: 0,
  recentAgents: [], // Last 20 completed agents
};

// Track historical token data per session
const tokenHistory = new Map();
const toolCallHistory = new Map();

// --- Persistence Helpers ---
function loadStatsFromDisk() {
  try {
    if (fs.existsSync(STATS_FILE)) {
      const data = JSON.parse(fs.readFileSync(STATS_FILE, 'utf-8'));
      const today = new Date().toISOString().split('T')[0];
      
      // If date matches, restore stats. Otherwise, reset for new day.
      if (data.date === today) {
        persistentStats = data;
        console.log('📂 Loaded stats from disk:', data.date);
      } else {
        console.log('📅 New day detected — resetting stats');
        persistentStats.date = today;
        saveStatsToDisk();
      }
    }
  } catch (e) {
    console.error('⚠️ Failed to load stats:', e.message);
  }
}

function saveStatsToDisk() {
  try {
    fs.writeFileSync(STATS_FILE, JSON.stringify(persistentStats, null, 2));
  } catch (e) {
    console.error('⚠️ Failed to save stats:', e.message);
  }
}

function checkMidnightReset() {
  const today = new Date().toISOString().split('T')[0];
  if (persistentStats.date !== today) {
    console.log('🌅 Midnight UTC passed — resetting daily stats');
    persistentStats = {
      date: today,
      completedToday: 0,
      failedToday: 0,
      totalTokensToday: 0,
      estimatedCostToday: 0,
      recentAgents: persistentStats.recentAgents, // Keep recent agents across days
    };
    saveStatsToDisk();
  }
}

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
    // ✅ Query GENERATIONS (LLM calls) instead of traces for better Guardian data
    // Fetch recent generations (last 24h) to capture Guardian LLM activity
    const url = `${LANGFUSE_HOST}/api/public/observations?limit=100&type=GENERATION`;

    const resp = await fetch(url, {
      headers: { 'Authorization': `Basic ${LANGFUSE_AUTH}` },
    });

    if (!resp.ok) {
      console.error('Langfuse API error:', resp.status);
      return null;
    }

    const body = await resp.json();
    const allGenerations = body.data || [];

    // ✅ FILTER: Only Guardian/moderation OR generations with totalTokens > 0
    const generations = allGenerations.filter(g => {
      const name = (g.name || '').toLowerCase();
      const hasTokens = (g.usage?.total || g.totalTokens || 0) > 0;
      const isGuardian = name.includes('guardian') || name.includes('moderation') || 
                        name.includes('content') || name.includes('severity');
      return isGuardian || hasTokens;
    });

    // Calculate aggregated metrics
    let totalTokens = 0, totalCost = 0, totalLatency = 0, errors = 0;
    const recentTraces = [];

    for (const g of generations) {
      const latency = g.latency ? Math.round(g.latency * 1000) : null;
      const tokens = g.usage?.total || g.totalTokens || 0;
      const cost = g.calculatedTotalCost || 0;

      totalTokens += tokens;
      totalCost += cost;
      if (latency) totalLatency += latency;
      if (g.level === 'ERROR') errors++;

      if (recentTraces.length < 5) {
        recentTraces.push({
          id: g.id?.substring(0, 12) || 'N/A',
          name: g.name || 'LLM Call',
          latency,
          totalTokens: tokens,
          cost: cost.toFixed(4),
          status: g.level || 'DEFAULT',
          timestamp: g.startTime || g.createdAt,
          model: g.model || 'N/A',
        });
      }
    }

    const result = {
      totalTraces: generations.length,
      avgLatency: generations.length > 0 ? Math.round(totalLatency / generations.filter(g => g.latency).length) || 0 : 0,
      errorRate: generations.length > 0 ? ((errors / generations.length) * 100).toFixed(1) : '0',
      totalCost: totalCost.toFixed(4),
      totalTokens,
      recentTraces,
      message: generations.length === 0 ? 'No recent Guardian LLM traces (last 24h)' : null,
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
  // Check if we need to reset stats (midnight UTC)
  checkMidnightReset();

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
  const cliRecent = ((parsed && parsed.recent) || []).slice(0, 10);

  // 2. Merge CLI recent with persisted recent agents (dedup by sessionKey)
  const seenKeys = new Set();
  const mergedRecent = [];
  
  for (const agent of [...cliRecent, ...persistentStats.recentAgents]) {
    if (!seenKeys.has(agent.sessionKey)) {
      seenKeys.add(agent.sessionKey);
      mergedRecent.push(agent);
    }
  }
  
  const recent = mergedRecent.slice(0, 20); // Keep last 20

  // 3. Get Linear updates for all task IDs
  const allAgents = [...active, ...recent];
  const taskIds = [...new Set(allAgents.map(a => extractTaskId(a.label)).filter(Boolean))];
  const linearData = await fetchLinearUpdates(taskIds);

  // 4. Enrich agents with health, ETA, Linear data
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

  // 5. Update persistent stats with new completions
  const newCompletions = cliRecent.filter(a => !persistentStats.recentAgents.some(r => r.sessionKey === a.sessionKey));
  for (const agent of newCompletions) {
    if (agent.status === 'done') {
      persistentStats.completedToday++;
    } else if (agent.status === 'error' || agent.status === 'timeout') {
      persistentStats.failedToday++;
    }
    
    const tokens = agent.totalTokens || 0;
    const cost = parseFloat(estimateTokenCost(tokens, agent.model));
    persistentStats.totalTokensToday += tokens;
    persistentStats.estimatedCostToday += cost;
  }

  // Update recent agents list (keep last 20)
  persistentStats.recentAgents = recent.slice(0, 20);

  // Save stats to disk on every poll cycle
  saveStatsToDisk();

  // 6. Build alerts
  const alerts = enrichedActive
    .filter(a => a.health.alert)
    .map(a => ({
      level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING',
      agent: a.label,
      taskId: a.taskId,
      message: a.health.alert,
      timestamp: new Date().toISOString(),
    }));

  // 7. Fetch Langfuse metrics
  const langfuseData = await fetchLangfuseMetrics();

  dashboardState = {
    active: enrichedActive,
    recent: enrichedRecent,
    langfuse: langfuseData,
    stats: {
      totalActive: enrichedActive.length,
      completedToday: persistentStats.completedToday,
      failedToday: persistentStats.failedToday,
      totalTokensToday: persistentStats.totalTokensToday,
      estimatedCostToday: persistentStats.estimatedCostToday.toFixed(4),
      avgRuntimeMin: enrichedRecent.length > 0
        ? (enrichedRecent.reduce((s, a) => s + parseFloat(a.runtimeMin), 0) / enrichedRecent.length).toFixed(1)
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
loadStatsFromDisk(); // Load stats on startup

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🦞 Anton Dashboard running on http://0.0.0.0:${PORT}`);
  console.log(`📊 Stats loaded: ${persistentStats.completedToday} completed, ${persistentStats.totalTokensToday} tokens`);
  // Initial poll
  pollAndBroadcast();
  // Start polling loop
  setInterval(pollAndBroadcast, POLL_INTERVAL);
});
