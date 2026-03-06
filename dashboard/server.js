const express = require('express');
const { WebSocketServer } = require('ws');
const { execSync, exec } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

// Load .env file
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf-8').split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const [key, ...rest] = trimmed.split('=');
      if (key && rest.length) process.env[key.trim()] = rest.join('=').trim();
    }
  }
}

const PORT = 8765;
const BIND = '0.0.0.0'; // protected by token auth
const POLL_INTERVAL = 8000; // 8s
const LINEAR_API_KEY = process.env.LINEAR_API_KEY || '';
const STATS_FILE = path.join(__dirname, 'stats-history.json');

// Langfuse config
const LANGFUSE_HOST = 'https://us.cloud.langfuse.com';
const LANGFUSE_PUBLIC_KEY = process.env.LANGFUSE_PUBLIC_KEY || '';
const LANGFUSE_SECRET_KEY = process.env.LANGFUSE_SECRET_KEY || '';
const LANGFUSE_AUTH = Buffer.from(`${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}`).toString('base64');

const DASHBOARD_TOKEN = process.env.DASHBOARD_TOKEN || 'anton-dash-2026';

const app = express();

// Auth middleware
app.use((req, res, next) => {
  // Allow static files if token is in query param
  const token = req.query.token || req.headers['x-dashboard-token'] || 
    (req.headers.authorization || '').replace('Bearer ', '');
  if (token === DASHBOARD_TOKEN || req.path === '/login') {
    return next();
  }
  // Serve login page
  res.send(`<html><body style="background:#0a0e17;color:#e2e8f0;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh">
    <form onsubmit="location.href='/?token='+document.getElementById('t').value;return false">
      <h2>🦞 Anton Cockpit</h2>
      <input id="t" type="password" placeholder="Token" style="padding:8px;background:#111827;color:#e2e8f0;border:1px solid #333;border-radius:4px;width:250px">
      <button style="padding:8px 16px;background:#3b82f6;color:white;border:none;border-radius:4px;cursor:pointer;margin-left:8px">Enter</button>
    </form></body></html>`);
});

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
  checkMidnightReset();

  // 1. Get session data from openclaw CLI (the correct command)
  const raw = safeExecSync('openclaw sessions --active 120 --json --all-agents 2>/dev/null');
  let sessions = [];
  try {
    const parsed = raw ? JSON.parse(raw) : {};
    sessions = (parsed.sessions || []);
  } catch { sessions = []; }

  // Classify sessions: active subagents vs recent completed vs cron/main
  const now = Date.now();
  const active = [];
  const recent = [];

  for (const s of sessions) {
    // Skip main session and cron sessions
    if (s.key === 'agent:main:main' || s.kind === 'direct') continue;
    
    const runtimeMs = s.ageMs ? (now - (s.updatedAt - s.ageMs)) : 0;
    const isSubagent = s.kind === 'subagent' || s.kind === 'acp' || s.key.includes('spawn');
    const isCron = s.key.includes('cron');
    
    if (isCron && !isSubagent) continue; // Skip pure cron sessions
    
    const agent = {
      sessionKey: s.key,
      sessionId: s.sessionId,
      label: s.label || s.key.split(':').pop() || 'unnamed',
      model: s.model || 'unknown',
      status: s.abortedLastRun ? 'error' : (s.ageMs < 60000 ? 'running' : 'done'),
      totalTokens: s.totalTokens || 0,
      runtimeMs: s.ageMs || 0,
      kind: s.kind,
      task: s.label || '',
    };

    // Sessions updated in last 5 min are likely still active
    if (s.ageMs < 300000 && !s.abortedLastRun) {
      agent.status = 'running';
      active.push(agent);
    } else {
      agent.status = s.abortedLastRun ? 'error' : 'done';
      recent.push(agent);
    }
  }

  // 2. Merge with persisted recent agents
  const seenKeys = new Set();
  const mergedRecent = [];
  for (const a of [...recent, ...persistentStats.recentAgents]) {
    if (!seenKeys.has(a.sessionKey)) {
      seenKeys.add(a.sessionKey);
      mergedRecent.push(a);
    }
  }
  const finalRecent = mergedRecent.slice(0, 20);

  // 3. Get Linear updates for all task IDs
  const allAgents = [...active, ...finalRecent];
  const taskIds = [...new Set(allAgents.map(a => extractTaskId(a.label)).filter(Boolean))];
  const linearData = await fetchLinearUpdates(taskIds);

  // 4. Enrich active agents
  const enrichedActive = active.map(a => {
    const health = getHealthStatus(a);
    const taskId = extractTaskId(a.label);
    const linear = taskId ? linearData[taskId] : null;
    const runtimeMin = (a.runtimeMs || 0) / 60000;
    let timeoutMin = 25;
    const timeoutMatch = (a.task || '').match(/Timeout:\s*(\d+)\s*min/i);
    if (timeoutMatch) timeoutMin = parseInt(timeoutMatch[1]);
    const etaMin = Math.max(0, timeoutMin - runtimeMin);
    const progress = Math.min(100, (runtimeMin / timeoutMin) * 100);
    const cost = estimateTokenCost(a.totalTokens || 0, a.model);

    return { ...a, health, taskId, linear, runtimeMin: runtimeMin.toFixed(1), timeoutMin, etaMin: etaMin.toFixed(1), progress: progress.toFixed(0), cost, taskShort: (a.task || '').substring(0, 100) };
  });

  // 5. Enrich recent agents
  const enrichedRecent = finalRecent.map(a => {
    const taskId = extractTaskId(a.label);
    const linear = taskId ? linearData[taskId] : null;
    const runtimeMin = (a.runtimeMs || 0) / 60000;
    const cost = estimateTokenCost(a.totalTokens || 0, a.model);
    return { ...a, taskId, linear, runtimeMin: runtimeMin.toFixed(1), cost, success: a.status === 'done' };
  });

  // 6. Update persistent stats
  const newCompletions = recent.filter(a => !persistentStats.recentAgents.some(r => r.sessionKey === a.sessionKey));
  for (const agent of newCompletions) {
    if (agent.status === 'done') persistentStats.completedToday++;
    else if (agent.status === 'error') persistentStats.failedToday++;
    const tokens = agent.totalTokens || 0;
    persistentStats.totalTokensToday += tokens;
    persistentStats.estimatedCostToday += parseFloat(estimateTokenCost(tokens, agent.model));
  }
  persistentStats.recentAgents = finalRecent.slice(0, 20);
  saveStatsToDisk();

  // 7. Build alerts
  const alerts = enrichedActive
    .filter(a => a.health.alert)
    .map(a => ({ level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING', agent: a.label, taskId: a.taskId, message: a.health.alert, timestamp: new Date().toISOString() }));

  // 8. Fetch Langfuse metrics
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
      avgRuntimeMin: enrichedRecent.length > 0 ? (enrichedRecent.reduce((s, a) => s + parseFloat(a.runtimeMin), 0) / enrichedRecent.length).toFixed(1) : '0',
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

// Global error handlers
process.on('uncaughtException', (e) => { console.error('UNCAUGHT:', e.message); });
process.on('unhandledRejection', (e) => { console.error('UNHANDLED REJECTION:', e?.message || e); });

// Poll and broadcast
async function pollAndBroadcast() {
  try {
    const data = await collectData();
    if (data) broadcast({ type: 'update', data });
  } catch (e) {
    console.error('Poll error:', e.message, e.stack);
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

server.listen(PORT, BIND, () => {
  console.log(`🦞 Anton Dashboard running on http://${BIND}:${PORT}`);
  console.log(`📊 Stats loaded: ${persistentStats.completedToday} completed, ${persistentStats.totalTokensToday} tokens`);
  // Initial poll
  pollAndBroadcast();
  // Start polling loop
  setInterval(pollAndBroadcast, POLL_INTERVAL);
});
