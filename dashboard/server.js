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
const BIND = '127.0.0.1'; // localhost only — no public access
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

// No auth needed — dashboard is localhost only (127.0.0.1)

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

// --- Data Collection (v2 — reads from agent-registry.json) ---
const OPENCLAW_HOME = process.env.HOME ? path.join(process.env.HOME, '.openclaw') : '/Users/fonsecabc/.openclaw';
const REGISTRY_FILE = path.join(OPENCLAW_HOME, 'tasks/agent-registry.json');
const AGENT_LOGS_DIR = path.join(OPENCLAW_HOME, 'tasks/agent-logs');
const WORKSPACE = path.join(OPENCLAW_HOME, 'workspace');
const HEALTH_METRICS = path.join(WORKSPACE, 'metrics/agent-health.json');

function readRegistry() {
  try {
    return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf-8'));
  } catch {
    return { agents: {}, maxConcurrent: 3 };
  }
}

function isProcessAlive(pid) {
  try { process.kill(pid, 0); return true; } catch { return false; }
}

function readAgentLog(taskId) {
  try {
    const logPath = path.join(AGENT_LOGS_DIR, `${taskId}.log`);
    if (fs.existsSync(logPath)) return fs.readFileSync(logPath, 'utf-8');
  } catch {}
  return '';
}

function getOutputSize(taskId) {
  try {
    const p = path.join(AGENT_LOGS_DIR, `${taskId}-output.log`);
    if (fs.existsSync(p)) return fs.statSync(p).size;
  } catch {}
  return 0;
}

function getLastActivity(taskId) {
  try {
    const activityPath = path.join(AGENT_LOGS_DIR, `${taskId}-activity.jsonl`);
    if (!fs.existsSync(activityPath)) return null;
    const lines = fs.readFileSync(activityPath, 'utf-8').trim().split('\n').slice(-10);
    const tools = [];
    let lastSummary = '';
    for (const line of lines) {
      try {
        const e = JSON.parse(line);
        if (e._summary) {
          if (e._summary.startsWith('TOOL_START:')) tools.push(e._summary.replace('TOOL_START: ', ''));
          lastSummary = e._summary;
        }
      } catch {}
    }
    return { tools: [...new Set(tools)], lastEvent: lastSummary, eventCount: lines.length };
  } catch { return null; }
}

function readHealthMetrics() {
  try {
    if (fs.existsSync(HEALTH_METRICS)) return JSON.parse(fs.readFileSync(HEALTH_METRICS, 'utf-8'));
  } catch {}
  return null;
}

// Track completed agents across polls (not just registry snapshots)
const completedAgentsToday = new Map(); // taskId -> { label, runtimeMin, completedAt, outputSize }

async function collectData() {
  checkMidnightReset();

  const registry = readRegistry();
  const now = Date.now();
  const nowS = Math.floor(now / 1000);

  // 1. Build active agents from registry
  const active = [];
  for (const [taskId, a] of Object.entries(registry.agents || {})) {
    const alive = isProcessAlive(a.pid);
    const ageMin = (nowS - (a.spawnedEpoch || nowS)) / 60;
    const timeoutMin = a.timeoutMin || 25;
    const outputSize = getOutputSize(taskId);

    if (!alive) {
      // Agent finished — record as completed and skip active
      if (!completedAgentsToday.has(taskId)) {
        completedAgentsToday.set(taskId, {
          taskId,
          label: a.label || taskId,
          runtimeMin: ageMin.toFixed(1),
          completedAt: new Date().toISOString(),
          outputSize,
          status: outputSize > 0 ? 'done' : 'error',
          source: a.source || 'unknown',
        });
        if (outputSize > 0) persistentStats.completedToday++;
        else persistentStats.failedToday++;
        saveStatsToDisk();
      }
      continue;
    }

    active.push({
      sessionKey: `registry:${taskId}`,
      label: a.label || taskId,
      model: 'claude',
      totalTokens: 0,
      runtimeMs: ageMin * 60000,
      status: 'running',
      task: a.label || taskId,
      taskId,
      pid: a.pid,
      source: a.source || 'unknown',
      timeoutMin,
    });
  }

  // 2. Build recent completions from tracked map + master log
  const recent = [];
  const sortedCompleted = [...completedAgentsToday.values()]
    .sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt))
    .slice(0, 20);

  for (const c of sortedCompleted) {
    recent.push({
      sessionKey: `completed:${c.taskId}`,
      label: c.label,
      model: 'claude',
      totalTokens: 0,
      runtimeMs: parseFloat(c.runtimeMin) * 60000,
      status: c.status,
      taskId: c.taskId,
      source: c.source,
    });
  }

  // Also load from persistent stats if we just restarted
  for (const r of (persistentStats.recentAgents || [])) {
    if (!completedAgentsToday.has(r.taskId)) {
      recent.push(r);
    }
  }

  // 3. Fetch Linear data for active agents (lightweight, parallel)
  const taskIds = [...new Set([...active, ...recent].map(a => extractTaskId(a.label) || a.taskId).filter(Boolean))];
  let linearData = {};
  if (LINEAR_API_KEY && taskIds.length > 0 && taskIds.length <= 10) {
    try { linearData = await fetchLinearUpdates(taskIds); } catch {}
  }

  // 4. Enrich active agents
  const enrichedActive = active.map(a => {
    try {
      const health = getHealthStatus(a);
      const taskId = a.taskId || extractTaskId(a.label);
      const linear = taskId ? linearData[taskId] : null;
      const runtimeMin = (a.runtimeMs || 0) / 60000;
      const timeoutMin = a.timeoutMin || 25;
      const etaMin = Math.max(0, timeoutMin - runtimeMin);
      const progress = Math.min(100, (runtimeMin / timeoutMin) * 100);

      const activity = getLastActivity(taskId);
      return { ...a, health, taskId, linear, activity, runtimeMin: runtimeMin.toFixed(1), timeoutMin, etaMin: etaMin.toFixed(1), progress: progress.toFixed(0), cost: '0' };
    } catch {
      return { ...a, health: { status: 'unknown', color: 'gray' }, runtimeMin: '0', cost: '0' };
    }
  });

  // 5. Enrich recent
  const enrichedRecent = recent.slice(0, 20).map(a => {
    try {
      const taskId = a.taskId || extractTaskId(a.label);
      const linear = taskId ? linearData[taskId] : null;
      const runtimeMin = (a.runtimeMs || 0) / 60000;
      return { ...a, taskId, linear, runtimeMin: runtimeMin.toFixed(1), cost: '0', success: a.status === 'done' };
    } catch {
      return { ...a, runtimeMin: '0', cost: '0' };
    }
  });

  // Save recent agents for persistence across restarts
  persistentStats.recentAgents = enrichedRecent.slice(0, 20);
  saveStatsToDisk();

  // 6. Alerts
  const alerts = enrichedActive
    .filter(a => a.health?.alert)
    .map(a => ({ level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING', agent: a.label, taskId: a.taskId, message: a.health.alert, timestamp: new Date().toISOString() }));

  // 7. Langfuse metrics (re-enabled)
  let langfuseData = null;
  try { langfuseData = await fetchLangfuseMetrics(); } catch {}

  // 8. Read health metrics from watchdog (single source of truth)
  const healthMetrics = readHealthMetrics();

  dashboardState = {
    active: enrichedActive,
    recent: enrichedRecent,
    langfuse: langfuseData,
    health: healthMetrics?.summary || null,
    stats: {
      totalActive: enrichedActive.length,
      maxConcurrent: registry.maxConcurrent || 3,
      completedToday: persistentStats.completedToday,
      failedToday: persistentStats.failedToday,
      totalTokensToday: persistentStats.totalTokensToday,
      estimatedCostToday: persistentStats.estimatedCostToday.toFixed(4),
      avgRuntimeMin: enrichedRecent.length > 0 ? (enrichedRecent.reduce((s, a) => s + parseFloat(a.runtimeMin || 0), 0) / enrichedRecent.length).toFixed(1) : '0',
      successRate7d: healthMetrics?.summary?.success_rate_pct ?? 'N/A',
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
        // Extract taskId from sessionKey (format: registry:CAI-XX)
        const taskId = msg.sessionKey.replace('registry:', '').replace('completed:', '');
        const reg = readRegistry();
        const agent = reg.agents?.[taskId];
        if (agent?.pid) {
          try { process.kill(agent.pid, 9); } catch {}
        }
        safeExecSync(`bash ${WORKSPACE}/scripts/agent-registry.sh remove "${taskId}" 2>/dev/null`);
        await pollAndBroadcast();
      }

      if (msg.action === 'steer' && msg.sessionKey && msg.message) {
        // Steer not supported for direct CLI agents — log the message instead
        const taskId = msg.sessionKey.replace('registry:', '');
        safeExecSync(`bash ${WORKSPACE}/skills/task-manager/scripts/linear-log.sh "${taskId}" "Steer: ${msg.message.replace(/"/g, '\\"')}" 2>/dev/null`);
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

// --- API endpoints ---
app.get('/api/state', (req, res) => res.json(dashboardState));

// Stream live activity log for a specific agent via SSE
app.get('/api/stream/:taskId', (req, res) => {
  const taskId = req.params.taskId;
  const activityPath = path.join(AGENT_LOGS_DIR, `${taskId}-activity.jsonl`);
  const sessionDir = path.join(process.env.HOME || '/Users/fonsecabc', '.claude/projects/-Users-fonsecabc--openclaw-workspace');

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  // Send existing activity first
  if (fs.existsSync(activityPath)) {
    const existing = fs.readFileSync(activityPath, 'utf-8').trim().split('\n');
    for (const line of existing.slice(-50)) { // last 50 events
      try {
        const e = JSON.parse(line);
        if (e._summary) res.write(`data: ${JSON.stringify({ ts: e._ts, event: e._summary })}\n\n`);
      } catch {}
    }
  }

  // Watch for new events
  let watcher = null;
  let lastSize = 0;

  function checkForNewLines(filePath) {
    try {
      const stat = fs.statSync(filePath);
      if (stat.size > lastSize) {
        const fd = fs.openSync(filePath, 'r');
        const buf = Buffer.alloc(stat.size - lastSize);
        fs.readSync(fd, buf, 0, buf.length, lastSize);
        fs.closeSync(fd);
        lastSize = stat.size;

        const newLines = buf.toString('utf-8').trim().split('\n');
        for (const line of newLines) {
          try {
            const e = JSON.parse(line);
            if (e._summary) res.write(`data: ${JSON.stringify({ ts: e._ts, event: e._summary })}\n\n`);
            else if (e.type) res.write(`data: ${JSON.stringify({ ts: e._ts || '', event: e.type })}\n\n`);
          } catch {}
        }
      }
    } catch {}
  }

  // Also try to find the Claude session file for richer data
  let sessionWatcher = null;
  try {
    const sessionFiles = fs.readdirSync(sessionDir).filter(f => f.endsWith('.jsonl')).sort((a, b) => {
      return fs.statSync(path.join(sessionDir, b)).mtimeMs - fs.statSync(path.join(sessionDir, a)).mtimeMs;
    });
    // Watch the most recent session file
    if (sessionFiles.length > 0) {
      const sessionPath = path.join(sessionDir, sessionFiles[0]);
      let sessionLastSize = fs.existsSync(sessionPath) ? fs.statSync(sessionPath).size : 0;

      sessionWatcher = setInterval(() => {
        try {
          const stat = fs.statSync(sessionPath);
          if (stat.size > sessionLastSize) {
            const fd = fs.openSync(sessionPath, 'r');
            const buf = Buffer.alloc(Math.min(stat.size - sessionLastSize, 10000)); // max 10KB per read
            fs.readSync(fd, buf, 0, buf.length, sessionLastSize);
            fs.closeSync(fd);
            sessionLastSize = stat.size;

            for (const line of buf.toString('utf-8').trim().split('\n')) {
              try {
                const e = JSON.parse(line);
                const msg = e.message || {};
                const role = msg.role || '';
                if (role === 'assistant') {
                  const content = msg.content || [];
                  if (Array.isArray(content)) {
                    for (const p of content) {
                      if (p?.type === 'text' && p.text) {
                        res.write(`data: ${JSON.stringify({ ts: '', event: `ASSISTANT: ${p.text.substring(0, 200)}` })}\n\n`);
                      } else if (p?.type === 'toolCall') {
                        res.write(`data: ${JSON.stringify({ ts: '', event: `TOOL: ${p.toolName || p.name || '?'}` })}\n\n`);
                      }
                    }
                  }
                }
              } catch {}
            }
          }
        } catch {}
      }, 2000);
    }
  } catch {}

  // Watch activity file
  if (fs.existsSync(activityPath)) {
    lastSize = fs.statSync(activityPath).size;
    watcher = setInterval(() => checkForNewLines(activityPath), 1000);
  } else {
    // File doesn't exist yet — poll until it does
    watcher = setInterval(() => {
      if (fs.existsSync(activityPath)) {
        lastSize = 0;
        checkForNewLines(activityPath);
      }
    }, 2000);
  }

  // Cleanup on disconnect
  req.on('close', () => {
    if (watcher) clearInterval(watcher);
    if (sessionWatcher) clearInterval(sessionWatcher);
  });
});

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
