const express = require('express');
const { WebSocketServer } = require('ws');
const { execSync } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

// Load env files
const WORKSPACE_ROOT = path.join(__dirname, '..');
for (const envFile of [
  path.join(__dirname, '.env'),
  path.join(WORKSPACE_ROOT, '.env.linear'),
  path.join(WORKSPACE_ROOT, '.env.secrets'),
]) {
  if (fs.existsSync(envFile)) {
    for (const line of fs.readFileSync(envFile, 'utf-8').split('\n')) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#')) {
        const noExport = trimmed.replace(/^export\s+/, '');
        const [key, ...rest] = noExport.split('=');
        if (key && rest.length) {
          let val = rest.join('=').trim();
          if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
            val = val.slice(1, -1);
          }
          process.env[key.trim()] = val;
        }
      }
    }
  }
}

const PORT = 8765;
const BIND = '127.0.0.1';
const POLL_INTERVAL = 8000;
const LINEAR_API_KEY = process.env.LINEAR_API_KEY || '';
if (!LINEAR_API_KEY) console.log('WARNING: No LINEAR_API_KEY — Linear disabled');
const STATS_FILE = path.join(__dirname, 'stats-history.json');

// Langfuse config
const LANGFUSE_HOST = 'https://us.cloud.langfuse.com';
const LANGFUSE_PUBLIC_KEY = process.env.LANGFUSE_PUBLIC_KEY || '';
const LANGFUSE_SECRET_KEY = process.env.LANGFUSE_SECRET_KEY || '';
const LANGFUSE_AUTH = Buffer.from(`${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}`).toString('base64');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// --- Paths ---
const OPENCLAW_HOME = process.env.HOME ? path.join(process.env.HOME, '.openclaw') : '/Users/fonsecabc/.openclaw';
const REGISTRY_FILE = path.join(OPENCLAW_HOME, 'tasks/agent-registry.json');
const AGENT_LOGS_DIR = path.join(OPENCLAW_HOME, 'tasks/agent-logs');
const WORKSPACE = path.join(OPENCLAW_HOME, 'workspace');

// --- Data Store ---
let dashboardState = {
  active: [],
  recent: [],
  stats: { totalActive: 0, completedToday: 0, failedToday: 0 },
  alerts: [],
  system: {},
  langfuse: null,
  lastUpdated: null,
};

// Persistent stats — only tracks what we can actually measure
let persistentStats = {
  date: new Date().toISOString().split('T')[0],
  completedToday: 0,
  failedToday: 0,
  recentAgents: [],
};

// --- Persistence ---
function loadStatsFromDisk() {
  try {
    if (!fs.existsSync(STATS_FILE)) return;
    const data = JSON.parse(fs.readFileSync(STATS_FILE, 'utf-8'));
    const today = new Date().toISOString().split('T')[0];

    if (data.date === today) {
      persistentStats = {
        date: data.date,
        completedToday: data.completedToday || 0,
        failedToday: data.failedToday || 0,
        recentAgents: data.recentAgents || [],
      };
      // Replay recentAgents to rebuild completedToday counter on restart
      // (fixes the bug where counters reset to 0 after server restart)
      const todayAgents = persistentStats.recentAgents.filter(a => {
        if (!a.completedAt) return false;
        return a.completedAt.startsWith(today);
      });
      const completed = todayAgents.filter(a => a.status === 'done').length;
      const failed = todayAgents.filter(a => a.status === 'error').length;
      // Use the max of persisted counter vs replayed count (handles partial restarts)
      persistentStats.completedToday = Math.max(persistentStats.completedToday, completed);
      persistentStats.failedToday = Math.max(persistentStats.failedToday, failed);
      console.log(`Loaded stats: ${persistentStats.completedToday} completed, ${persistentStats.failedToday} failed`);
    } else {
      console.log('New day — resetting counters, keeping recent agents');
      persistentStats.date = today;
      persistentStats.completedToday = 0;
      persistentStats.failedToday = 0;
      // Keep recent agents for history but don't count them in today's stats
      persistentStats.recentAgents = (data.recentAgents || []).slice(0, 20);
      saveStatsToDisk();
    }
  } catch (e) {
    console.error('Failed to load stats:', e.message);
  }
}

function saveStatsToDisk() {
  try {
    fs.writeFileSync(STATS_FILE, JSON.stringify(persistentStats, null, 2));
  } catch (e) {
    console.error('Failed to save stats:', e.message);
  }
}

function checkMidnightReset() {
  const today = new Date().toISOString().split('T')[0];
  if (persistentStats.date !== today) {
    persistentStats = {
      date: today,
      completedToday: 0,
      failedToday: 0,
      recentAgents: persistentStats.recentAgents,
    };
    saveStatsToDisk();
  }
}

// --- Helpers ---
function safeExecSync(cmd, timeout = 15000) {
  try {
    return execSync(cmd, { encoding: 'utf-8', timeout, maxBuffer: 1024 * 1024 });
  } catch {
    return null;
  }
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
    const stat = fs.statSync(activityPath);
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
    return {
      tools: [...new Set(tools)],
      lastEvent: lastSummary,
      eventCount: lines.length,
      fileSize: stat.size,
      lastModified: stat.mtimeMs,
    };
  } catch { return null; }
}

// --- System Health Check ---
// Checks real infrastructure: gateway, mysql proxy, launchd jobs
function checkSystemHealth() {
  const checks = {};

  // Gateway
  try {
    const result = safeExecSync('curl -s -o /dev/null -w "%{http_code}" http://localhost:18789/ 2>/dev/null', 3000);
    checks.gateway = result?.trim() === '200' ? 'ok' : 'down';
  } catch {
    checks.gateway = 'down';
  }

  // MySQL (Cloud SQL Proxy)
  try {
    const result = safeExecSync('mysql -e "SELECT 1" 2>/dev/null', 5000);
    checks.mysql = result !== null ? 'ok' : 'down';
  } catch {
    checks.mysql = 'down';
  }

  // Launchd jobs
  try {
    const result = safeExecSync('launchctl list 2>/dev/null | grep -c "com.anton"', 3000);
    const count = parseInt(result?.trim() || '0');
    checks.launchd = count >= 4 ? 'ok' : count > 0 ? 'partial' : 'down';
    checks.launchdCount = count;
  } catch {
    checks.launchd = 'unknown';
    checks.launchdCount = 0;
  }

  // Queue status
  try {
    const queueStatus = safeExecSync(`bash ${WORKSPACE}/scripts/queue-control.sh status 2>/dev/null`, 3000);
    checks.queue = queueStatus?.includes('PAUSED') ? 'paused' : 'active';
  } catch {
    checks.queue = 'unknown';
  }

  return checks;
}

// Cache system health (expensive checks, run every 30s not every 8s)
let systemHealthCache = { data: {}, lastCheck: 0 };
const HEALTH_CHECK_INTERVAL = 30000;

function getCachedSystemHealth() {
  if (Date.now() - systemHealthCache.lastCheck > HEALTH_CHECK_INTERVAL) {
    systemHealthCache.data = checkSystemHealth();
    systemHealthCache.lastCheck = Date.now();
  }
  return systemHealthCache.data;
}

// --- Linear Integration ---
async function fetchLinearUpdates(taskIds) {
  if (!taskIds.length) return {};
  const results = {};

  // Batch query — fetch up to 15 tasks in a single request
  try {
    const filters = taskIds.map(id => {
      const match = id.match(/^([A-Z]+)-(\d+)$/);
      if (!match) return null;
      return { team: match[1], num: parseInt(match[2]), id };
    }).filter(Boolean);

    if (!filters.length) return results;

    // Build OR filter for all tasks
    const orClauses = filters.map(f =>
      `{ number: { eq: ${f.num} }, team: { key: { eq: "${f.team}" } } }`
    ).join(', ');

    const query = JSON.stringify({
      query: `{ issues(filter: { or: [${orClauses}] }, first: 20) { nodes { id identifier title state { name color } comments(last: 1) { nodes { body createdAt } } updatedAt } } }`
    });

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);

    const response = await fetch('https://api.linear.app/graphql', {
      method: 'POST',
      headers: { 'Authorization': LINEAR_API_KEY, 'Content-Type': 'application/json' },
      body: query,
      signal: controller.signal,
    });
    clearTimeout(timeout);

    const data = await response.json();
    if (data?.errors) console.log('[Linear] errors:', JSON.stringify(data.errors).substring(0, 200));

    for (const issue of (data?.data?.issues?.nodes || [])) {
      const tid = issue.identifier;
      const lastComment = issue.comments?.nodes?.[0];
      results[tid] = {
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
    console.log('[Linear] Batch fetch error:', e.message);
  }
  return results;
}

// --- Langfuse Integration ---
let langfuseCache = { data: null, lastFetch: 0 };
const LANGFUSE_CACHE_TTL = 60000; // 60s cache (was 30s — too aggressive)

async function fetchLangfuseMetrics() {
  if (Date.now() - langfuseCache.lastFetch < LANGFUSE_CACHE_TTL && langfuseCache.data) {
    return langfuseCache.data;
  }

  if (!LANGFUSE_PUBLIC_KEY || !LANGFUSE_SECRET_KEY) return null;

  try {
    const url = `${LANGFUSE_HOST}/api/public/observations?limit=50&type=GENERATION`;

    const resp = await fetch(url, {
      headers: { 'Authorization': `Basic ${LANGFUSE_AUTH}` },
    });

    if (!resp.ok) {
      console.error('Langfuse API error:', resp.status);
      return null;
    }

    const body = await resp.json();
    const generations = (body.data || []).filter(g => {
      return (g.usage?.total || g.totalTokens || 0) > 0;
    });

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
          name: g.name || 'LLM Call',
          latency,
          totalTokens: tokens,
          cost: cost.toFixed(4),
          status: g.level || 'DEFAULT',
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
    };

    langfuseCache = { data: result, lastFetch: Date.now() };
    return result;
  } catch (e) {
    console.error('Langfuse fetch error:', e.message);
    return langfuseCache.data;
  }
}

// --- Data Collection ---
const completedAgentsToday = new Map();

async function collectData() {
  checkMidnightReset();

  const registry = readRegistry();
  const nowS = Math.floor(Date.now() / 1000);

  // 1. Build active agents from registry
  const active = [];
  for (const [taskId, a] of Object.entries(registry.agents || {})) {
    const alive = isProcessAlive(a.pid);
    const ageMin = (nowS - (a.spawnedEpoch || nowS)) / 60;
    const timeoutMin = a.timeoutMin || 25;
    const outputSize = getOutputSize(taskId);

    if (!alive) {
      if (!completedAgentsToday.has(taskId)) {
        const completedAgent = {
          taskId,
          label: a.label || taskId,
          runtimeMin: ageMin.toFixed(1),
          completedAt: new Date().toISOString(),
          outputSize,
          status: outputSize > 0 ? 'done' : 'error',
          source: a.source || 'unknown',
        };
        completedAgentsToday.set(taskId, completedAgent);
        if (outputSize > 0) persistentStats.completedToday++;
        else persistentStats.failedToday++;
        saveStatsToDisk();
      }
      continue;
    }

    active.push({
      sessionKey: `registry:${taskId}`,
      label: a.label || taskId,
      runtimeMs: ageMin * 60000,
      status: 'running',
      taskId,
      pid: a.pid,
      source: a.source || 'unknown',
      timeoutMin,
    });
  }

  // 2. Build recent completions
  const recent = [];
  const sortedCompleted = [...completedAgentsToday.values()]
    .sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt))
    .slice(0, 20);

  for (const c of sortedCompleted) {
    recent.push({
      sessionKey: `completed:${c.taskId}`,
      label: c.label,
      runtimeMs: parseFloat(c.runtimeMin) * 60000,
      status: c.status,
      taskId: c.taskId,
      source: c.source,
      completedAt: c.completedAt,
    });
  }

  // Also load from persistent stats (survives restarts)
  for (const r of (persistentStats.recentAgents || [])) {
    if (!completedAgentsToday.has(r.taskId)) {
      recent.push(r);
    }
  }

  // 3. Fetch Linear data for agents with CAI-IDs
  const taskIds = [...new Set(
    [...active, ...recent]
      .map(a => extractTaskId(a.label) || a.taskId)
      .filter(id => id && /^CAI-\d+$/.test(id))
  )];
  let linearData = {};
  const limitedTaskIds = taskIds.slice(0, 15);
  if (LINEAR_API_KEY && limitedTaskIds.length > 0) {
    try { linearData = await fetchLinearUpdates(limitedTaskIds); } catch (e) { console.error('Linear fetch error:', e.message); }
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

      return {
        ...a, health, taskId, linear, activity,
        runtimeMin: runtimeMin.toFixed(1),
        timeoutMin,
        etaMin: etaMin.toFixed(1),
        progress: progress.toFixed(0),
      };
    } catch {
      return { ...a, health: { status: 'unknown', color: 'gray' }, runtimeMin: '0' };
    }
  });

  // 5. Enrich recent
  const enrichedRecent = recent.slice(0, 20).map(a => {
    try {
      const taskId = a.taskId || extractTaskId(a.label);
      const linear = taskId ? linearData[taskId] : null;
      const runtimeMin = (a.runtimeMs || 0) / 60000;
      return { ...a, taskId, linear, runtimeMin: runtimeMin.toFixed(1), success: a.status === 'done' };
    } catch {
      return { ...a, runtimeMin: '0' };
    }
  });

  // Save recent agents for persistence
  persistentStats.recentAgents = enrichedRecent.slice(0, 20);
  saveStatsToDisk();

  // 6. Alerts
  const alerts = enrichedActive
    .filter(a => a.health?.alert)
    .map(a => ({
      level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING',
      agent: a.label,
      taskId: a.taskId,
      message: a.health.alert,
      timestamp: new Date().toISOString(),
    }));

  // 7. Langfuse (best-effort)
  let langfuseData = null;
  try { langfuseData = await fetchLangfuseMetrics(); } catch {}

  // 8. System health
  const system = getCachedSystemHealth();

  // 9. Compute avg runtime from recent completed agents
  const completedRecent = enrichedRecent.filter(a => a.runtimeMin && parseFloat(a.runtimeMin) > 0);
  const avgRuntimeMin = completedRecent.length > 0
    ? (completedRecent.reduce((s, a) => s + parseFloat(a.runtimeMin), 0) / completedRecent.length).toFixed(1)
    : '0';

  dashboardState = {
    active: enrichedActive,
    recent: enrichedRecent,
    langfuse: langfuseData,
    system,
    stats: {
      totalActive: enrichedActive.length,
      maxConcurrent: registry.maxConcurrent || 3,
      completedToday: persistentStats.completedToday,
      failedToday: persistentStats.failedToday,
      avgRuntimeMin,
      recentTotal: enrichedRecent.length,
    },
    alerts,
    lastUpdated: new Date().toISOString(),
  };

  return dashboardState;
}

// --- WebSocket ---
function broadcast(data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(msg);
  });
}

process.on('uncaughtException', (e) => { console.error('UNCAUGHT:', e.message); });
process.on('unhandledRejection', (e) => { console.error('UNHANDLED REJECTION:', e?.message || e); });

async function pollAndBroadcast() {
  try {
    const data = await collectData();
    if (data) broadcast({ type: 'update', data });
  } catch (e) {
    console.error('Poll error:', e.message);
    if (dashboardState.lastUpdated) broadcast({ type: 'update', data: dashboardState });
  }
}

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'update', data: dashboardState }));

  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw);

      if (msg.action === 'kill' && msg.sessionKey) {
        const taskId = msg.sessionKey.replace('registry:', '').replace('completed:', '');
        const reg = readRegistry();
        const agent = reg.agents?.[taskId];
        if (agent?.pid) {
          try { process.kill(agent.pid, 9); } catch {}
        }
        safeExecSync(`bash ${WORKSPACE}/scripts/agent-registry.sh remove "${taskId}" 2>/dev/null`);
        await pollAndBroadcast();
      }

      if (msg.action === 'note' && msg.sessionKey && msg.message) {
        const taskId = msg.sessionKey.replace('registry:', '');
        safeExecSync(`bash ${WORKSPACE}/skills/task-manager/scripts/linear-log.sh "${taskId}" "${msg.message.replace(/"/g, '\\"')}" 2>/dev/null`);
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

// --- API ---
app.get('/api/state', (req, res) => res.json(dashboardState));

// Guardian eval data endpoint
app.get('/api/eval', (req, res) => {
  try {
    const { execSync } = require('child_process');
    const data = execSync('bash ' + path.join(WORKSPACE, 'scripts/cockpit-eval-data.sh'), {
      timeout: 10000,
      encoding: 'utf-8',
    });
    res.json(JSON.parse(data));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Stream live agent activity via SSE
app.get('/api/stream/:taskId', (req, res) => {
  const taskId = req.params.taskId;
  const activityPath = path.join(AGENT_LOGS_DIR, `${taskId}-activity.jsonl`);
  const sessionDir = path.join(process.env.HOME || '/Users/fonsecabc', '.claude/projects/-Users-fonsecabc--openclaw-workspace');

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  function parseSessionLine(line) {
    try {
      const e = JSON.parse(line);
      const msg = e.message || {};
      const role = msg.role || '';
      const content = msg.content;

      if (role === 'assistant' && Array.isArray(content)) {
        const events = [];
        for (const p of content) {
          if (p?.type === 'text' && p.text) events.push({ event: `[text] ${p.text.substring(0, 300)}` });
          else if (p?.type === 'toolCall') events.push({ event: `[tool] ${p.toolName || p.name || '?'}(${JSON.stringify(p.arguments || {}).substring(0, 100)})` });
          else if (p?.type === 'thinking') events.push({ event: `[think] ...` });
        }
        if (msg.model) events.push({ event: `[meta] model=${msg.model} tokens=${msg.usage?.totalTokens || '?'}` });
        return events;
      }
      if (role === 'toolResult') {
        const c = typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content || '');
        return [{ event: `[result] ${c.substring(0, 150)}` }];
      }
    } catch {}
    return [];
  }

  function parseActivityLine(line) {
    try {
      const e = JSON.parse(line);
      if (e._summary) return [{ ts: e._ts, event: e._summary }];
      if (e.type === 'content_block_start') {
        const block = e.content_block || {};
        if (block.type === 'tool_use') return [{ ts: e._ts, event: `[tool] ${block.name}` }];
      }
      if (e.type === 'result') return [{ ts: e._ts, event: `[done] result received` }];
      if (e.type === 'error') return [{ ts: e._ts, event: `[error] ${JSON.stringify(e.error).substring(0, 150)}` }];
    } catch {}
    return [];
  }

  // Find session file
  let sessionPath = null;
  try {
    const files = fs.readdirSync(sessionDir)
      .filter(f => f.endsWith('.jsonl') && !f.includes('.deleted'))
      .map(f => ({ name: f, mtime: fs.statSync(path.join(sessionDir, f)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
    if (files.length > 0) sessionPath = path.join(sessionDir, files[0].name);
  } catch {}

  // Backfill from session file
  if (sessionPath && fs.existsSync(sessionPath)) {
    try {
      const lines = fs.readFileSync(sessionPath, 'utf-8').trim().split('\n').slice(-60);
      const events = [];
      for (const line of lines) {
        for (const ev of parseSessionLine(line)) events.push(ev);
      }
      for (const ev of events.slice(-30)) {
        res.write(`data: ${JSON.stringify(ev)}\n\n`);
      }
    } catch {}
  }

  // Backfill from activity file
  if (fs.existsSync(activityPath)) {
    try {
      const lines = fs.readFileSync(activityPath, 'utf-8').trim().split('\n').slice(-20);
      for (const line of lines) {
        for (const ev of parseActivityLine(line)) {
          res.write(`data: ${JSON.stringify(ev)}\n\n`);
        }
      }
    } catch {}
  }

  // Watch for new data
  let sessionLastSize = sessionPath && fs.existsSync(sessionPath) ? fs.statSync(sessionPath).size : 0;
  let activityLastSize = fs.existsSync(activityPath) ? fs.statSync(activityPath).size : 0;

  const watcher = setInterval(() => {
    if (sessionPath) {
      try {
        const stat = fs.statSync(sessionPath);
        if (stat.size > sessionLastSize) {
          const fd = fs.openSync(sessionPath, 'r');
          const buf = Buffer.alloc(Math.min(stat.size - sessionLastSize, 20000));
          fs.readSync(fd, buf, 0, buf.length, sessionLastSize);
          fs.closeSync(fd);
          sessionLastSize = stat.size;
          for (const line of buf.toString('utf-8').trim().split('\n')) {
            for (const ev of parseSessionLine(line)) {
              res.write(`data: ${JSON.stringify(ev)}\n\n`);
            }
          }
        }
      } catch {}
    }

    try {
      if (!fs.existsSync(activityPath)) return;
      const stat = fs.statSync(activityPath);
      if (stat.size > activityLastSize) {
        const fd = fs.openSync(activityPath, 'r');
        const buf = Buffer.alloc(stat.size - activityLastSize);
        fs.readSync(fd, buf, 0, buf.length, activityLastSize);
        fs.closeSync(fd);
        activityLastSize = stat.size;
        for (const line of buf.toString('utf-8').trim().split('\n')) {
          for (const ev of parseActivityLine(line)) {
            res.write(`data: ${JSON.stringify(ev)}\n\n`);
          }
        }
      }
    } catch {}
  }, 1500);

  req.on('close', () => clearInterval(watcher));
});

// --- Start ---
loadStatsFromDisk();

server.listen(PORT, BIND, () => {
  console.log(`Anton Dashboard on http://${BIND}:${PORT}`);
  pollAndBroadcast();
  setInterval(pollAndBroadcast, POLL_INTERVAL);
});
