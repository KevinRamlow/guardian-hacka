const express = require('express');
const { WebSocketServer } = require('ws');
const { exec, execSync, spawn } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

// ─── Config ───────────────────────────────────────────────────────────────────
const PORT = 8765;
const BIND = '127.0.0.1';
const HOME = process.env.HOME || '/Users/fonsecabc';
const OPENCLAW = path.join(HOME, '.openclaw');
const WORKSPACE = path.join(OPENCLAW, 'workspace');
const REGISTRY_FILE = path.join(OPENCLAW, 'tasks/agent-registry.json');
const AGENT_LOGS = path.join(OPENCLAW, 'tasks/agent-logs');
const STATS_FILE = path.join(__dirname, 'stats.json');

const SSH_OPTS = '-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=/tmp/ssh-dash-%r@%h -o ControlPersist=60';
const REMOTE_HOST = 'caio@89.167.23.2';

// ─── Env Loading ──────────────────────────────────────────────────────────────
function loadEnvFile(filepath) {
  try {
    if (!fs.existsSync(filepath)) return;
    for (const line of fs.readFileSync(filepath, 'utf-8').split('\n')) {
      const t = line.trim();
      if (!t || t.startsWith('#')) continue;
      const clean = t.replace(/^export\s+/, '');
      const eq = clean.indexOf('=');
      if (eq < 1) continue;
      const key = clean.slice(0, eq).trim();
      let val = clean.slice(eq + 1).trim();
      if ((val[0] === '"' && val.at(-1) === '"') || (val[0] === "'" && val.at(-1) === "'"))
        val = val.slice(1, -1);
      process.env[key] = val;
    }
  } catch {}
}

loadEnvFile(path.join(WORKSPACE, '.env.linear'));
loadEnvFile(path.join(WORKSPACE, '.env.secrets'));

const LINEAR_API_KEY = process.env.LINEAR_API_KEY || '';
const LANGFUSE_PUBLIC = process.env.LANGFUSE_PUBLIC_KEY || '';
const LANGFUSE_SECRET = process.env.LANGFUSE_SECRET_KEY || '';
const LANGFUSE_AUTH = Buffer.from(`${LANGFUSE_PUBLIC}:${LANGFUSE_SECRET}`).toString('base64');

// ─── Cache System ─────────────────────────────────────────────────────────────
class Cache {
  constructor(ttlMs) { this.ttlMs = ttlMs; this.data = null; this.fetchedAt = 0; this.fetching = false; }
  isStale() { return Date.now() - this.fetchedAt > this.ttlMs; }
  get() { return this.data; }
  set(d) { this.data = d; this.fetchedAt = Date.now(); }
  bust() { this.fetchedAt = 0; }
}

const caches = {
  system: new Cache(30000),
  remote: new Cache(30000),
  linear: new Cache(60000),
  langfuse: new Cache(60000),
  selfImprovement: new Cache(120000),
  guardian: new Cache(15000),
  git: new Cache(120000),
};

// ─── Helpers ──────────────────────────────────────────────────────────────────
function run(cmd, timeout = 10000) {
  try { return execSync(cmd, { encoding: 'utf-8', timeout, maxBuffer: 2 * 1024 * 1024 }).trim(); } catch { return null; }
}

function runAsync(cmd, timeout = 15000) {
  return new Promise(resolve => {
    exec(cmd, { encoding: 'utf-8', timeout, maxBuffer: 2 * 1024 * 1024 }, (err, stdout) => {
      resolve(err ? null : (stdout || '').trim());
    });
  });
}

function readJSON(filepath) {
  try { return JSON.parse(fs.readFileSync(filepath, 'utf-8')); } catch { return null; }
}

function extractTaskId(label) {
  const m = (label || '').match(/\b((?:AUTO|CAI)-\d+)\b/);
  return m ? m[1] : null;
}

function isAlive(pid) {
  try { process.kill(pid, 0); return true; } catch { return false; }
}

// ─── Stats Persistence ────────────────────────────────────────────────────────
let stats = { date: '', completed: 0, failed: 0, seen: {} };

function loadStats() {
  const today = new Date().toISOString().slice(0, 10);
  const saved = readJSON(STATS_FILE);
  if (saved?.date === today) { stats = saved; }
  else { stats = { date: today, completed: 0, failed: 0, seen: {} }; }
}

function saveStats() {
  try { fs.writeFileSync(STATS_FILE, JSON.stringify(stats)); } catch {}
}

function recordCompletion(taskId, success) {
  const today = new Date().toISOString().slice(0, 10);
  if (stats.date !== today) { stats = { date: today, completed: 0, failed: 0, seen: {} }; }
  if (stats.seen[taskId]) return;
  stats.seen[taskId] = true;
  if (success) stats.completed++; else stats.failed++;
  saveStats();
}

// ─── Data Collectors ──────────────────────────────────────────────────────────

// 1. Local agents from registry
function collectLocalAgents() {
  const reg = readJSON(REGISTRY_FILE) || { agents: {}, maxConcurrent: 3 };
  const now = Date.now() / 1000;
  const active = [], recent = [];

  for (const [tid, a] of Object.entries(reg.agents || {})) {
    const alive = isAlive(a.pid);
    const ageMin = (now - (a.spawnedEpoch || now)) / 60;
    const timeout = a.timeoutMin || 25;
    const progress = Math.min(100, (ageMin / timeout) * 100);

    if (!alive) {
      const outSize = (() => { try { return fs.statSync(path.join(AGENT_LOGS, `${tid}-output.log`)).size; } catch { return 0; } })();
      const ok = outSize > 0;
      recordCompletion(tid, ok);
      recent.push({ taskId: tid, label: a.label || tid, runtimeMin: +ageMin.toFixed(1), status: ok ? 'done' : 'error', source: a.source, machine: 'mac' });
      continue;
    }

    // Get last activity
    let lastEvent = null;
    try {
      const actPath = path.join(AGENT_LOGS, `${tid}-activity.jsonl`);
      if (fs.existsSync(actPath)) {
        const lines = fs.readFileSync(actPath, 'utf-8').trim().split('\n').slice(-5);
        for (const l of lines) { try { const e = JSON.parse(l); if (e._summary) lastEvent = e._summary; } catch {} }
      }
    } catch {}

    active.push({
      taskId: tid,
      label: a.label || tid,
      pid: a.pid,
      runtimeMin: +ageMin.toFixed(1),
      timeoutMin: timeout,
      progress: +progress.toFixed(0),
      source: a.source || '?',
      machine: 'mac',
      lastEvent,
      health: ageMin > 25 ? 'frozen' : ageMin > 18 ? 'warning' : 'healthy',
    });
  }

  return { active, recent, maxSlots: reg.maxConcurrent || 3 };
}

// 2. Remote agents via SSH
async function collectRemote() {
  if (!caches.remote.isStale()) return caches.remote.get();
  if (caches.remote.fetching) return caches.remote.get();
  caches.remote.fetching = true;

  try {
    const cmd = `ssh ${SSH_OPTS} ${REMOTE_HOST} "echo GATEWAY_START; curl -s -o /dev/null -w '%{http_code}' http://localhost:18790/ 2>/dev/null || echo 000; echo GATEWAY_END; echo PROCS_START; ps aux | grep -E 'claude|openclaw' | grep -v grep | wc -l; echo PROCS_END"`;
    const out = await runAsync(cmd, 12000);
    if (!out) { caches.remote.set({ online: false, gateway: 'offline', processCount: 0 }); return caches.remote.get(); }

    const gwMatch = out.match(/GATEWAY_START\n?(\d+)\n?GATEWAY_END/);
    const procMatch = out.match(/PROCS_START\n?(\d+)\n?PROCS_END/);
    const gwCode = gwMatch ? gwMatch[1] : '000';
    const procs = procMatch ? parseInt(procMatch[1]) : 0;

    caches.remote.set({ online: gwCode === '200', gateway: gwCode === '200' ? 'ok' : 'down', processCount: procs });
  } catch {
    caches.remote.set({ online: false, gateway: 'offline', processCount: 0 });
  } finally { caches.remote.fetching = false; }
  return caches.remote.get();
}

// 3. System health
function collectSystem() {
  if (!caches.system.isStale()) return caches.system.get();
  const gw = run('curl -s -o /dev/null -w "%{http_code}" http://localhost:18789/', 3000);
  const mysql = run('mysql -e "SELECT 1" 2>/dev/null', 5000);
  const jobs = run('launchctl list 2>/dev/null | grep -c "com.anton"', 3000);
  const queue = run(`bash ${WORKSPACE}/scripts/queue-control.sh status 2>/dev/null`, 3000);
  const d = {
    gateway: gw === '200' ? 'ok' : 'down',
    mysql: mysql !== null ? 'ok' : 'down',
    launchdJobs: parseInt(jobs || '0'),
    queue: queue?.includes('PAUSED') ? 'paused' : 'active',
  };
  caches.system.set(d);
  return d;
}

// 4. Linear
async function collectLinear() {
  if (!caches.linear.isStale()) return caches.linear.get();
  if (!LINEAR_API_KEY) { caches.linear.set({ todo: [], inProgress: [], blocked: [], done: [] }); return caches.linear.get(); }

  try {
    const q = JSON.stringify({
      query: `{ todo: issues(filter:{team:{key:{eq:"AUTO"}},state:{name:{eq:"Todo"}}},first:10,orderBy:updatedAt){nodes{identifier title state{name color}}} inProgress: issues(filter:{team:{key:{eq:"AUTO"}},state:{name:{eq:"In Progress"}}},first:10){nodes{identifier title state{name color} comments(last:1){nodes{body createdAt}}}} blocked: issues(filter:{team:{key:{eq:"AUTO"}},state:{name:{eq:"Blocked"}}},first:5){nodes{identifier title}} done: issues(filter:{team:{key:{eq:"AUTO"}},state:{name:{eq:"Done"}},completedAt:{gte:"${new Date(Date.now()-86400000).toISOString()}"}},first:10){nodes{identifier title}} }`
    });
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 8000);
    const r = await fetch('https://api.linear.app/graphql', {
      method: 'POST', headers: { 'Authorization': LINEAR_API_KEY, 'Content-Type': 'application/json' },
      body: q, signal: ctrl.signal,
    });
    clearTimeout(t);
    const body = await r.json();
    const d = body?.data || {};
    const result = {
      todo: (d.todo?.nodes || []).map(n => ({ id: n.identifier, title: n.title, color: n.state?.color })),
      inProgress: (d.inProgress?.nodes || []).map(n => ({ id: n.identifier, title: n.title, color: n.state?.color, lastComment: n.comments?.nodes?.[0]?.body?.slice(0, 120) })),
      blocked: (d.blocked?.nodes || []).map(n => ({ id: n.identifier, title: n.title })),
      done: (d.done?.nodes || []).map(n => ({ id: n.identifier, title: n.title })),
    };
    caches.linear.set(result);
  } catch { if (!caches.linear.get()) caches.linear.set({ todo: [], inProgress: [], blocked: [], done: [] }); }
  return caches.linear.get();
}

// 5. Langfuse
async function collectLangfuse() {
  if (!caches.langfuse.isStale()) return caches.langfuse.get();
  if (!LANGFUSE_PUBLIC || !LANGFUSE_SECRET) return null;

  try {
    const r = await fetch('https://us.cloud.langfuse.com/api/public/observations?limit=50&type=GENERATION', {
      headers: { 'Authorization': `Basic ${LANGFUSE_AUTH}` },
    });
    if (!r.ok) return caches.langfuse.get();
    const body = await r.json();
    const gens = (body.data || []).filter(g => (g.usage?.total || 0) > 0);

    let tokens = 0, cost = 0, latency = 0, errors = 0, latCount = 0;
    const traces = [];
    for (const g of gens) {
      const tok = g.usage?.total || 0;
      const c = g.calculatedTotalCost || 0;
      const lat = g.latency ? Math.round(g.latency * 1000) : 0;
      tokens += tok; cost += c;
      if (lat) { latency += lat; latCount++; }
      if (g.level === 'ERROR') errors++;
      if (traces.length < 5) traces.push({ name: g.name || 'LLM', latency: lat, tokens: tok, cost: +c.toFixed(4), model: g.model || '?' });
    }
    const d = {
      traces: gens.length, tokens, cost: +cost.toFixed(4),
      avgLatency: latCount ? Math.round(latency / latCount) : 0,
      errorRate: gens.length ? +((errors / gens.length) * 100).toFixed(1) : 0,
      recent: traces,
    };
    caches.langfuse.set(d);
  } catch {}
  return caches.langfuse.get();
}

// 6. Self-improvement + budget + scorecard
function collectSelfImprovement() {
  if (!caches.selfImprovement.isStale()) return caches.selfImprovement.get();
  const state = readJSON(path.join(WORKSPACE, 'self-improvement/loop/state.json'));
  const budget = readJSON(path.join(WORKSPACE, 'self-improvement/loop/budget-status.json'));
  const scorecard = readJSON(path.join(WORKSPACE, 'self-improvement/metrics/daily-scorecard.json'));
  const trends = readJSON(path.join(WORKSPACE, 'self-improvement/metrics/trends.json'));
  const d = { state, budget, scorecard, trends };
  caches.selfImprovement.set(d);
  return d;
}

// 7. Guardian eval
function collectGuardian() {
  if (!caches.guardian.isStale()) return caches.guardian.get();
  const baseline = readJSON(path.join(WORKSPACE, 'guardian-agents-api-real/evals/baseline.json'));
  const runsDir = path.join(WORKSPACE, 'guardian-agents-api-real/evals/.runs/content_moderation');
  const runs = [];
  try {
    const dirs = fs.readdirSync(runsDir).filter(d => d.startsWith('run_')).sort().reverse().slice(0, 5);
    for (const dir of dirs) {
      const m = readJSON(path.join(runsDir, dir, 'metrics.json'));
      if (m?.summary_statistics) {
        const acc = +(m.summary_statistics.mean_aggregate_score * 100).toFixed(2);
        const baseAcc = baseline ? +(baseline.accuracy * 100).toFixed(2) : 76.86;
        runs.push({ name: dir, accuracy: acc, delta: +(acc - baseAcc).toFixed(2), tests: m.summary_statistics.total_tests });
      }
    }
  } catch {}
  const d = {
    baseline: baseline ? +(baseline.accuracy * 100).toFixed(2) : 76.86,
    target: 87,
    current: runs[0]?.accuracy || (baseline ? +(baseline.accuracy * 100).toFixed(2) : 76.86),
    runs,
  };
  caches.guardian.set(d);
  return d;
}

// 8. Git
function collectGit() {
  if (!caches.git.isStale()) return caches.git.get();
  const count = run(`git -C "${WORKSPACE}" log --oneline --since="24 hours ago" 2>/dev/null | wc -l`, 5000);
  const recent = run(`git -C "${WORKSPACE}" log --oneline -5 --format="%h|%s" 2>/dev/null`, 5000);
  const commits = (recent || '').split('\n').filter(Boolean).map(l => {
    const [hash, ...msg] = l.split('|');
    return { hash, msg: msg.join('|') };
  });
  const d = { today: parseInt(count || '0'), recent: commits };
  caches.git.set(d);
  return d;
}

// 9. Agent health summary
function collectAgentHealth() {
  return readJSON(path.join(WORKSPACE, 'metrics/agent-health.json'))?.summary || null;
}

// ─── Main Poll ────────────────────────────────────────────────────────────────
let dashState = {};

async function poll() {
  const local = collectLocalAgents();
  const [remote, system, linear, langfuse, guardian, git] = await Promise.all([
    collectRemote(), Promise.resolve(collectSystem()), collectLinear(),
    collectLangfuse(), Promise.resolve(collectGuardian()), Promise.resolve(collectGit()),
  ]);
  const si = collectSelfImprovement();
  const health = collectAgentHealth();

  dashState = {
    agents: {
      mac: { active: local.active, recent: local.recent, maxSlots: local.maxSlots },
      vm: { active: [], recent: [], online: remote?.online || false, gateway: remote?.gateway || 'offline', processCount: remote?.processCount || 0 },
    },
    stats: { completed: stats.completed, failed: stats.failed, active: local.active.length },
    system,
    linear: linear || {},
    langfuse: langfuse || null,
    si: si || {},
    guardian: guardian || {},
    git: git || {},
    health: health || {},
    ts: Date.now(),
  };
  return dashState;
}

// ─── Express + WS ─────────────────────────────────────────────────────────────
const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.static(path.join(__dirname, 'public')));
app.get('/api/state', (_, res) => res.json(dashState));

// SSE activity stream
app.get('/api/stream/:taskId', (req, res) => {
  const tid = req.params.taskId;
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });

  const actPath = path.join(AGENT_LOGS, `${tid}-activity.jsonl`);
  if (fs.existsSync(actPath)) {
    try {
      const lines = fs.readFileSync(actPath, 'utf-8').trim().split('\n').slice(-30);
      for (const l of lines) {
        try { const e = JSON.parse(l); if (e._summary) res.write(`data: ${JSON.stringify({ event: e._summary })}\n\n`); } catch {}
      }
    } catch {}
  }

  let lastSize = fs.existsSync(actPath) ? fs.statSync(actPath).size : 0;
  const watcher = setInterval(() => {
    try {
      if (!fs.existsSync(actPath)) return;
      const sz = fs.statSync(actPath).size;
      if (sz <= lastSize) return;
      const fd = fs.openSync(actPath, 'r');
      const buf = Buffer.alloc(Math.min(sz - lastSize, 20000));
      fs.readSync(fd, buf, 0, buf.length, lastSize);
      fs.closeSync(fd);
      lastSize = sz;
      for (const l of buf.toString().trim().split('\n')) {
        try { const e = JSON.parse(l); if (e._summary) res.write(`data: ${JSON.stringify({ event: e._summary })}\n\n`); } catch {}
      }
    } catch {}
  }, 1500);

  req.on('close', () => clearInterval(watcher));
});

wss.on('connection', ws => {
  ws.send(JSON.stringify({ t: 'state', d: dashState }));
  ws.on('message', async raw => {
    try {
      const msg = JSON.parse(raw);
      if (msg.action === 'kill' && msg.taskId) {
        const reg = readJSON(REGISTRY_FILE) || { agents: {} };
        const a = reg.agents?.[msg.taskId];
        if (a?.pid) try { process.kill(a.pid, 9); } catch {}
        run(`bash ${WORKSPACE}/scripts/agent-registry.sh remove "${msg.taskId}" 2>/dev/null`);
      }
      if (msg.action === 'refresh') { Object.values(caches).forEach(c => c.bust()); }
      await broadcast();
    } catch {}
  });
});

async function broadcast() {
  const d = await poll();
  const msg = JSON.stringify({ t: 'state', d });
  wss.clients.forEach(c => { if (c.readyState === 1) c.send(msg); });
}

process.on('uncaughtException', e => console.error('UNCAUGHT:', e.message));
process.on('unhandledRejection', e => console.error('UNHANDLED:', e?.message || e));

loadStats();
server.listen(PORT, BIND, () => {
  console.log(`Anton Command Center v2 → http://${BIND}:${PORT}`);
  broadcast();
  setInterval(broadcast, 8000);
});
