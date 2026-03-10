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
const PROCESS_REGISTRY_FILE = path.join(OPENCLAW_HOME, 'tasks/process-registry.json');
const STATE_FILE = path.join(OPENCLAW_HOME, 'tasks/state.json');
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
  const match = (label || '').match(/\b((?:CAI|AUTO|REVIEW)-\d+)\b/);
  return match ? match[1] : null;
}

function readProcessRegistry() {
  try {
    const data = JSON.parse(fs.readFileSync(PROCESS_REGISTRY_FILE, 'utf-8'));
    const nowS = Math.floor(Date.now() / 1000);
    const processes = [];
    for (const [procId, p] of Object.entries(data.processes || {})) {
      const alive = p.pid ? isProcessAlive(p.pid) : false;
      const ageMin = ((nowS - (p.startedEpoch || nowS)) / 60).toFixed(1);
      processes.push({
        id: procId,
        pid: p.pid,
        type: p.type,
        taskId: p.taskId,
        status: p.status,
        alive,
        ageMin: parseFloat(ageMin),
        timeoutMin: p.timeoutMin || 120,
        callbackType: p.callbackType || 'none',
        callbackDispatched: p.callbackDispatched || false,
        exitCode: p.exitCode,
        startedAt: p.startedAt,
        completedAt: p.completedAt,
        resultPath: p.resultPath,
        metricsPath: p.metricsPath,
      });
    }
    return processes;
  } catch {
    return [];
  }
}

function readUnifiedState() {
  try {
    const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8'));
    const nowS = Math.floor(Date.now() / 1000);
    const tasks = [];
    for (const [taskId, t] of Object.entries(data.tasks || {})) {
      const pid = t.agentPid || t.processPid;
      const alive = pid ? isProcessAlive(pid) : false;
      const epoch = t.startedEpoch || t.createdEpoch || nowS;
      const ageMin = ((nowS - epoch) / 60).toFixed(1);
      tasks.push({
        taskId,
        status: t.status,
        label: t.label || taskId,
        agentPid: t.agentPid,
        processPid: t.processPid,
        processType: t.processType,
        parentTask: t.parentTask || null,
        alive,
        ageMin: parseFloat(ageMin),
        timeoutMin: t.timeoutMin || 25,
        source: t.source || 'unknown',
        role: t.role || null,
        callbackType: t.callbackType || 'dispatch',
        exitCode: t.exitCode,
        retries: t.retries || 0,
        extensions: t.extensions || 0,
        historyCount: (t.history || []).length,
        lastHistory: (t.history || []).slice(-1)[0] || null,
        learnings: t.learnings || [],
        createdAt: t.createdAt,
        startedAt: t.startedAt,
        completedAt: t.completedAt,
      });
    }
    return { tasks, maxConcurrent: data.maxConcurrent || 3 };
  } catch {
    return { tasks: [], maxConcurrent: 3 };
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
  // Read from OpenClaw native stdout log (replaces old activity.jsonl)
  try {
    const stdoutPath = path.join(AGENT_LOGS_DIR, `${taskId}-output.log`);
    if (!fs.existsSync(stdoutPath)) return null;
    const stat = fs.statSync(stdoutPath);
    const lines = fs.readFileSync(stdoutPath, 'utf-8').trim().split('\n').slice(-20);
    
    const tools = [];
    let lastEvent = '';
    
    // Parse stdout for tool calls and events
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      
      // Detect tool calls in output
      if (trimmed.includes('tool_use') || trimmed.includes('[tool]')) {
        try {
          const toolMatch = trimmed.match(/name[":]+\s*([a-z_]+)/i);
          if (toolMatch) tools.push(toolMatch[1]);
        } catch {}
      }
      
      lastEvent = trimmed.substring(0, 200);
    }
    
    return {
      tools: [...new Set(tools)],
      lastEvent,
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

// --- Remote Data (VMs, cached 30s) ---
let remoteCache = { data: { online: false, gateway: 'offline', processCount: 0 }, lastCheck: 0 };
let billyCache = { data: { online: false, gateway: 'offline', processCount: 0, framework: 'OpenClaw' }, lastCheck: 0 };

function collectRemoteVM(host, user, port, cache) {
  if (Date.now() - cache.lastCheck < 30000 && cache.lastCheck > 0) return cache.data;
  try {
    const out = execSync(
      `ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ${user}@${host} "curl -s -o /dev/null -w '%{http_code}' http://localhost:${port}/ 2>/dev/null; echo; ps aux | grep -cE 'openclaw|clawdbot'"`,
      { timeout: 10000, encoding: 'utf-8' }
    ).trim();
    const lines = out.split('\n').map(l => l.trim()).filter(Boolean);
    const gwCode = lines[0] || '000';
    const procs = parseInt(lines[1]) || 0;
    cache.data = { online: gwCode === '200', gateway: gwCode === '200' ? 'ok' : 'down', processCount: procs };
    cache.lastCheck = Date.now();
  } catch {
    cache.data = { online: false, gateway: 'offline', processCount: 0 };
    cache.lastCheck = Date.now();
  }
  return cache.data;
}

function collectRemoteData() {
  // Son of Anton VM removed — no remote VM to collect
  return { online: false, gateway: 'offline', processCount: 0 };
}

function collectBillyData() {
  return collectRemoteVM('89.167.64.183', 'root', 18790, billyCache);
}

// --- GitHub Integration (cached 5min) ---
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '';
let githubCache = { data: [], lastFetch: 0 };
const GITHUB_CACHE_TTL = 300000; // 5min

async function fetchGithubCommits() {
  if (Date.now() - githubCache.lastFetch < GITHUB_CACHE_TTL && githubCache.data.length) {
    return githubCache.data;
  }
  if (!GITHUB_TOKEN) return [];

  const repos = [
    { owner: 'fonsecabc', repo: 'replicants-anton', agent: 'Anton' },
    { owner: 'fonsecabc', repo: 'replicants-billy', agent: 'Billy' },
    { owner: 'brandlovers-team', repo: 'guardian-agents-api', agent: 'Guardian' },
  ];

  const allCommits = [];
  for (const r of repos) {
    try {
      const resp = await fetch(`https://api.github.com/repos/${r.owner}/${r.repo}/commits?per_page=10`, {
        headers: { 'Authorization': `token ${GITHUB_TOKEN}`, 'Accept': 'application/vnd.github.v3+json' },
      });
      if (!resp.ok) continue;
      const commits = await resp.json();
      for (const c of commits) {
        allCommits.push({
          repo: r.repo,
          agent: r.agent,
          sha: c.sha?.substring(0, 7),
          message: c.commit?.message?.split('\n')[0]?.substring(0, 80),
          author: c.commit?.author?.name,
          date: c.commit?.author?.date,
          url: c.html_url,
        });
      }
    } catch (e) {
      console.log(`[GitHub] Error fetching ${r.repo}:`, e.message);
    }
  }

  allCommits.sort((a, b) => new Date(b.date) - new Date(a.date));
  githubCache = { data: allCommits.slice(0, 30), lastFetch: Date.now() };
  return githubCache.data;
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

  const { tasks: stateTasks, maxConcurrent } = readUnifiedState();

  // 1. Build active + recent from state.json (single source of truth)
  const active = [];
  const recent = [];

  for (const t of stateTasks) {
    if (t.status === 'agent_running') {
      const runtimeMs = t.ageMin * 60000;
      active.push({
        sessionKey: `state:${t.taskId}`,
        label: t.label,
        runtimeMs,
        status: 'running',
        taskId: t.taskId,
        pid: t.agentPid,
        source: t.source,
        role: t.role,
        timeoutMin: t.timeoutMin,
        alive: t.alive,
        retries: t.retries,
        extensions: t.extensions,
        learnings: t.learnings,
      });
    } else if (t.status === 'eval_running') {
      const runtimeMs = t.ageMin * 60000;
      active.push({
        sessionKey: `state:${t.taskId}`,
        label: t.label,
        runtimeMs,
        status: 'eval_running',
        taskId: t.taskId,
        pid: t.processPid,
        processType: t.processType || 'eval',
        parentTask: t.parentTask,
        source: t.source,
        role: null,
        timeoutMin: t.timeoutMin,
        alive: t.alive,
        retries: t.retries,
        extensions: t.extensions,
        learnings: t.learnings,
      });
    } else if (t.status === 'callback_pending') {
      const runtimeMs = t.ageMin * 60000;
      active.push({
        sessionKey: `state:${t.taskId}`,
        label: t.label,
        runtimeMs,
        status: 'callback_pending',
        taskId: t.taskId,
        pid: null,
        processType: t.processType || 'eval',
        parentTask: t.parentTask,
        source: t.source,
        role: null,
        timeoutMin: t.timeoutMin,
        alive: false,
        retries: t.retries,
        extensions: t.extensions,
        learnings: t.learnings,
        lastHistory: t.lastHistory,
      });
    } else if (['done', 'failed', 'timeout', 'error'].includes(t.status)) {
      // Track for today's counters
      if (!completedAgentsToday.has(t.taskId)) {
        const outputSize = getOutputSize(t.taskId);
        const isDone = t.status === 'done' && outputSize > 0;
        completedAgentsToday.set(t.taskId, {
          taskId: t.taskId,
          label: t.label,
          runtimeMin: t.ageMin.toFixed(1),
          completedAt: t.completedAt || new Date().toISOString(),
          outputSize,
          status: isDone ? 'done' : 'error',
          source: t.source,
          role: t.role,
        });
        if (isDone) persistentStats.completedToday++;
        else persistentStats.failedToday++;
        saveStatsToDisk();
      }

      const cached = completedAgentsToday.get(t.taskId);
      recent.push({
        sessionKey: `completed:${t.taskId}`,
        label: cached.label,
        runtimeMs: parseFloat(cached.runtimeMin) * 60000,
        status: cached.status,
        taskId: t.taskId,
        source: cached.source,
        role: cached.role || t.role,
        completedAt: cached.completedAt,
      });
    }
  }

  // Also load from persistent stats (survives restarts)
  for (const r of (persistentStats.recentAgents || [])) {
    if (!completedAgentsToday.has(r.taskId) && !recent.find(x => x.taskId === r.taskId)) {
      recent.push(r);
    }
  }

  // Sort recent by completion time descending
  recent.sort((a, b) => new Date(b.completedAt || 0) - new Date(a.completedAt || 0));

  // 2. Fetch Linear data for agents with task IDs
  const taskIds = [...new Set(
    [...active, ...recent]
      .map(a => extractTaskId(a.label) || a.taskId)
      .filter(id => id && /^(CAI|AUTO|REVIEW)-\d+$/.test(id))
  )];
  let linearData = {};
  const limitedTaskIds = taskIds.slice(0, 15);
  if (LINEAR_API_KEY && limitedTaskIds.length > 0) {
    try { linearData = await fetchLinearUpdates(limitedTaskIds); } catch (e) { console.error('Linear fetch error:', e.message); }
  }

  // 3. Enrich active agents (+ eval progress for eval_running tasks)
  const enrichedActive = active.map(a => {
    try {
      const health = getHealthStatus(a);
      const taskId = a.taskId || extractTaskId(a.label);
      const linear = taskId ? linearData[taskId] : null;
      const runtimeMin = (a.runtimeMs || 0) / 60000;
      const timeoutMin = a.timeoutMin || 25;
      const etaMin = Math.max(0, timeoutMin - runtimeMin);
      let progress = Math.min(100, (runtimeMin / timeoutMin) * 100);
      const activity = getLastActivity(taskId);

      // For eval_running tasks, read real eval progress from progress_meta.json
      let evalProgress = null;
      if (a.status === 'eval_running') {
        try {
          const EVAL_RUNS_DIR = path.join(WORKSPACE, 'guardian-agents-api-real/evals/.runs/content_moderation');
          if (fs.existsSync(EVAL_RUNS_DIR)) {
            const latestRunDir = fs.readdirSync(EVAL_RUNS_DIR)
              .filter(d => d.startsWith('run_'))
              .sort()
              .reverse()[0];
            if (latestRunDir) {
              const metaPath = path.join(EVAL_RUNS_DIR, latestRunDir, 'progress_meta.json');
              if (fs.existsSync(metaPath)) {
                const meta = JSON.parse(fs.readFileSync(metaPath, 'utf-8'));
                evalProgress = {
                  completed: meta.completed || 0,
                  total: meta.total || 0,
                  errors: meta.errors || 0,
                  percent: meta.total > 0 ? Math.round((meta.completed / meta.total) * 100) : 0,
                };
                progress = evalProgress.percent; // override progress bar with eval progress
              }
            }
          }
        } catch {}
      }

      return {
        ...a, health, taskId, linear, activity, evalProgress,
        runtimeMin: runtimeMin.toFixed(1),
        timeoutMin,
        etaMin: etaMin.toFixed(1),
        progress: typeof progress === 'number' ? progress.toFixed ? progress.toFixed(0) : String(progress) : String(progress),
      };
    } catch {
      return { ...a, health: { status: 'unknown', color: 'gray' }, runtimeMin: '0' };
    }
  });

  // 4. Enrich recent
  const enrichedRecent = recent.slice(0, 100).map(a => {
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
  persistentStats.recentAgents = enrichedRecent.slice(0, 100);
  saveStatsToDisk();

  // 5. Alerts
  const alerts = enrichedActive
    .filter(a => a.health?.alert)
    .map(a => ({
      level: a.health.status === 'frozen' ? 'CRITICAL' : 'WARNING',
      agent: a.label,
      taskId: a.taskId,
      message: a.health.alert,
      timestamp: new Date().toISOString(),
    }));

  // 6. Langfuse (best-effort)
  let langfuseData = null;
  try { langfuseData = await fetchLangfuseMetrics(); } catch {}

  // 7. System health
  const system = getCachedSystemHealth();

  // 7b. Remote VMs
  let remote = { online: false, gateway: 'offline', processCount: 0 };
  try { remote = collectRemoteData(); } catch {}
  let billy = { online: false, gateway: 'offline', processCount: 0 };
  try { billy = collectBillyData(); } catch {}

  // 8. Compute avg runtime from recent completed agents
  const completedRecent = enrichedRecent.filter(a => a.runtimeMin && parseFloat(a.runtimeMin) > 0);
  const avgRuntimeMin = completedRecent.length > 0
    ? (completedRecent.reduce((s, a) => s + parseFloat(a.runtimeMin), 0) / completedRecent.length).toFixed(1)
    : '0';

  // 9. Process Manager data
  const processes = readProcessRegistry();

  // 10. GitHub commits (best-effort, cached)
  let github = [];
  try { github = await fetchGithubCommits(); } catch {}

  console.log('[collectData] Building dashboard state...');
  const tokens = getTokenStatus();
  console.log('[collectData] Got tokens:', tokens);
  
  dashboardState = {
    active: enrichedActive,
    recent: enrichedRecent,
    langfuse: langfuseData,
    system,
    stats: {
      totalActive: enrichedActive.length,
      maxConcurrent,
      completedToday: persistentStats.completedToday,
      failedToday: persistentStats.failedToday,
      avgRuntimeMin,
      recentTotal: enrichedRecent.length,
    },
    alerts,
    remote,
    billy,
    processes,
    github,
    tokens,
    lastUpdated: new Date().toISOString(),
  };

  return dashboardState;
}

function getTokenStatus() {
  try {
    const out = execSync('~/.nvm/versions/node/v22.13.1/bin/openclaw sessions 2>/dev/null', {
      timeout: 5000,
      encoding: 'utf-8'
    }).trim();
    
    const sessions = [];
    const lines = out.split('\n');
    for (const line of lines) {
      // Match format: "direct agent:main:main  3m ago  claude-sonnet-4-5 121k/200k (60%)"
      const match = line.match(/agent:([^:]+):[^\s]+.*?(\S+)\s+(\d+)k\/(\d+)k\s+\((\d+)%\)/);
      if (match) {
        sessions.push({
          agent: match[1],
          model: match[2],
          used: parseInt(match[3]),
          total: parseInt(match[4]),
          percent: parseInt(match[5]),
        });
      }
    }
    console.log(`[tokens] Found ${sessions.length} sessions`);
    return sessions;
  } catch (err) {
    console.error('[tokens] Error:', err.message);
    return [];
  }
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
        const taskId = msg.sessionKey.replace('state:', '').replace('completed:', '');
        const { tasks } = readUnifiedState();
        const task = tasks.find(t => t.taskId === taskId);
        if (task?.agentPid) {
          try { process.kill(task.agentPid, 9); } catch {}
        }
        safeExecSync(`bash ${WORKSPACE}/scripts/task-manager.sh remove "${taskId}" 2>/dev/null`);
        await pollAndBroadcast();
      }

      if (msg.action === 'note' && msg.sessionKey && msg.message) {
        const taskId = msg.sessionKey.replace('state:', '');
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

// Guardian eval data endpoint — reads directly from eval runs directory
app.get('/api/eval', (req, res) => {
  try {
    const EVAL_RUNS_DIR = path.join(WORKSPACE, 'guardian-agents-api-real/evals/.runs/content_moderation');
    const TARGET_ACCURACY = 0.87; // 87% target

    // Read all run directories with metrics.json
    const runs = [];
    if (fs.existsSync(EVAL_RUNS_DIR)) {
      const dirs = fs.readdirSync(EVAL_RUNS_DIR)
        .filter(d => d.startsWith('run_'))
        .sort()
        .reverse(); // newest first

      for (const dir of dirs) {
        const metricsPath = path.join(EVAL_RUNS_DIR, dir, 'metrics.json');
        if (!fs.existsSync(metricsPath)) continue;
        try {
          const m = JSON.parse(fs.readFileSync(metricsPath, 'utf-8'));
          const stats = m.summary_statistics || m;
          const acc = stats.mean_aggregate_score;
          const total = stats.total_tests;
          if (acc == null || total == null || total < 20) continue; // skip tiny/broken runs

          const ts = dir.replace('run_', '');
          const dateStr = ts.replace(/(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/, '$1-$2-$3 $4:$5');
          runs.push({
            run_name: dateStr,
            accuracy: (acc * 100).toFixed(1) + '%',
            accuracy_raw: acc,
            total_tests: total,
            timestamp: ts,
            dir: dir,
          });
        } catch {}
      }
    }

    // Calculate deltas between consecutive runs (same dataset size)
    const fullRuns = runs.filter(r => r.total_tests >= 100); // only 121-case runs
    for (let i = 0; i < fullRuns.length; i++) {
      if (i < fullRuns.length - 1) {
        const delta = (fullRuns[i].accuracy_raw - fullRuns[i + 1].accuracy_raw) * 100;
        fullRuns[i].delta_pp = delta.toFixed(1);
      } else {
        fullRuns[i].delta_pp = '0.0'; // first run, no delta
      }
    }

    // Current accuracy = latest full run
    const latest = fullRuns[0];
    const currentAcc = latest ? latest.accuracy_raw : null;

    // Check for active evals from state.json
    const activeEvals = [];
    try {
      const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8'));
      for (const [taskId, task] of Object.entries(state.tasks || {})) {
        if (task.status !== 'eval_running') continue;
        
        const pid = task.processPid;
        let alive = false;
        try { process.kill(pid, 0); alive = true; } catch {}
        
        // Get progress from progress_meta.json in latest run dir (most reliable)
        let progress = {};
        try {
          const EVAL_RUNS_DIR_P = path.join(WORKSPACE, 'guardian-agents-api-real/evals/.runs/content_moderation');
          if (fs.existsSync(EVAL_RUNS_DIR_P)) {
            const latestRunDir = fs.readdirSync(EVAL_RUNS_DIR_P)
              .filter(d => d.startsWith('run_'))
              .sort()
              .reverse()[0];
            if (latestRunDir) {
              const metaPath = path.join(EVAL_RUNS_DIR_P, latestRunDir, 'progress_meta.json');
              if (fs.existsSync(metaPath)) {
                const meta = JSON.parse(fs.readFileSync(metaPath, 'utf-8'));
                progress = {
                  completed: meta.completed || 0,
                  total: meta.total || 0,
                  errors: meta.errors || 0,
                  percent: meta.total > 0 ? Math.round((meta.completed / meta.total) * 100) : 0,
                  lastUpdated: meta.last_updated || null,
                };
              }
            }
          }
          // Fallback: try /tmp log file
          if (!progress.total) {
            const logFiles = fs.readdirSync('/tmp').filter(f => f.startsWith('guardian-eval-')).sort().reverse();
            if (logFiles.length > 0) {
              const logContent = fs.readFileSync(path.join('/tmp', logFiles[0]), 'utf-8');
              const progressMatch = logContent.match(/(\d+)\/(\d+)\s/g);
              if (progressMatch) {
                const last = progressMatch[progressMatch.length - 1];
                const [completed, total] = last.trim().split('/').map(Number);
                progress = { completed, total, percent: Math.round((completed / total) * 100) };
              }
            }
          }
        } catch {}

        activeEvals.push({
          taskId,
          pid,
          alive,
          dataset: 'guidelines_combined',
          progress,
        });
      }
    } catch {}

    res.json({
      active_evals: activeEvals,
      recent_runs: fullRuns.slice(0, 3), // last 3 completed
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Stream live agent activity via SSE
app.get('/api/stream/:taskId', (req, res) => {
  const taskId = req.params.taskId;
  
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  // Parse OpenClaw native session format (from ~/.openclaw/agents/{agentId}/sessions/)
  function parseOpenClawSessionLine(line) {
    try {
      const e = JSON.parse(line);
      const msg = e.message || {};
      const role = msg.role || '';
      const content = msg.content;

      if (role === 'assistant' && Array.isArray(content)) {
        const events = [];
        for (const p of content) {
          if (p?.type === 'text' && p.text) events.push({ event: `[text] ${p.text.substring(0, 300)}` });
          else if (p?.type === 'tool_use') events.push({ event: `[tool] ${p.name || '?'}(${JSON.stringify(p.input || {}).substring(0, 100)})` });
        }
        if (msg.model) events.push({ event: `[meta] model=${msg.model} tokens=${msg.usage?.total_tokens || '?'}` });
        return events;
      }
      if (role === 'user' && typeof content === 'string' && content.startsWith('# Task:')) {
        return [{ event: `[task] ${content.split('\n')[0].replace('# Task: ', '')}` }];
      }
    } catch {}
    return [];
  }

  // --- 1. Output log is the primary per-task source (always correct) ---
  const stdoutPath = path.join(AGENT_LOGS_DIR, `${taskId}-output.log`);
  let sentFromLog = false;
  if (fs.existsSync(stdoutPath)) {
    try {
      const content = fs.readFileSync(stdoutPath, 'utf-8').trim();
      if (content.length > 0) {
        const lines = content.split('\n').slice(-30);
        for (const line of lines) {
          if (line.trim()) {
            res.write(`data: ${JSON.stringify({ event: line.substring(0, 300) })}\n\n`);
          }
        }
        sentFromLog = true;
      }
    } catch {}
  }

  // --- 2. Session file fallback: ONLY when matched by exact task ID ---
  // (Never guess by time — that shows wrong logs for the card)
  if (!sentFromLog) {
    let sessionPath = null;
    try {
      const agentsDir = path.join(OPENCLAW_HOME, 'agents');
      const agentDirs = fs.readdirSync(agentsDir).filter(d => {
        try { return fs.statSync(path.join(agentsDir, d)).isDirectory(); } catch { return false; }
      });

      for (const dir of agentDirs) {
        const sessionsDir = path.join(agentsDir, dir, 'sessions');
        if (!fs.existsSync(sessionsDir)) continue;
        const files = fs.readdirSync(sessionsDir).filter(f => f.endsWith('.jsonl'));
        for (const file of files) {
          const raw = fs.readFileSync(path.join(sessionsDir, file), 'utf-8');
          if (raw.includes(`# Task: ${taskId}`)) {
            sessionPath = path.join(sessionsDir, file);
            break;
          }
        }
        if (sessionPath) break;
      }
    } catch {}

    if (sessionPath && fs.existsSync(sessionPath)) {
      try {
        const lines = fs.readFileSync(sessionPath, 'utf-8').trim().split('\n').slice(-60);
        const events = [];
        for (const line of lines) {
          for (const ev of parseOpenClawSessionLine(line)) events.push(ev);
        }
        for (const ev of events.slice(-30)) {
          res.write(`data: ${JSON.stringify(ev)}\n\n`);
        }
        sentFromLog = true;
      } catch {}
    }
  }

  // --- 3. Nothing found ---
  if (!sentFromLog) {
    res.write(`data: ${JSON.stringify({ event: '[No logs found for this task]' })}\n\n`);
  }

  // OLD SYSTEM ARCHIVED - No longer reading from:
  // - ~/.claude/projects/ (Claude Desktop sessions)
  // - activity.jsonl (old v1/v2 system)
  
  // Keep connection alive - watch for updates
  let lastSize = fs.existsSync(stdoutPath) ? fs.statSync(stdoutPath).size : 0;
  
  const watcher = setInterval(() => {
    if (fs.existsSync(stdoutPath)) {
      try {
        const stat = fs.statSync(stdoutPath);
        if (stat.size > lastSize) {
          const fd = fs.openSync(stdoutPath, 'r');
          const buf = Buffer.alloc(Math.min(stat.size - lastSize, 10000));
          fs.readSync(fd, buf, 0, buf.length, lastSize);
          fs.closeSync(fd);
          lastSize = stat.size;
          
          const newLines = buf.toString('utf-8').trim().split('\n');
          for (const line of newLines) {
            if (line.trim()) {
              res.write(`data: ${JSON.stringify({ event: line.substring(0, 300) })}\n\n`);
            }
          }
        }
      } catch {}
    }
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
