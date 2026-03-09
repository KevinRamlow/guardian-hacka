#!/usr/bin/env node
/**
 * OpenClaw → Langfuse Bridge
 * 
 * Watches OpenClaw session JSONL files and sends traces to Langfuse.
 * Adapted from stefanocalabrese/openclaw-langfuse-integration for macOS.
 * 
 * Instead of journalctl (Linux), we tail session JSONL files directly.
 * 
 * Usage: node openclaw-langfuse-bridge.mjs
 * Env: LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST
 */

import fs from 'fs';
import path from 'path';

// Config from env
const LANGFUSE_HOST = process.env.LANGFUSE_HOST || 'https://us.cloud.langfuse.com';
const LANGFUSE_PUBLIC_KEY = process.env.LANGFUSE_PUBLIC_KEY;
const LANGFUSE_SECRET_KEY = process.env.LANGFUSE_SECRET_KEY;
const OPENCLAW_HOME = process.env.OPENCLAW_HOME || path.join(process.env.HOME, '.openclaw');
const AGENTS_DIR = path.join(OPENCLAW_HOME, 'agents');

if (!LANGFUSE_PUBLIC_KEY || !LANGFUSE_SECRET_KEY) {
  console.error('❌ Missing LANGFUSE_PUBLIC_KEY or LANGFUSE_SECRET_KEY');
  process.exit(1);
}

const AUTH = Buffer.from(`${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}`).toString('base64');

// Track active sessions and file positions
const filePositions = new Map(); // filePath → byte offset
const activeSessions = new Map(); // sessionId → { traceId, agentId, startTime }
const batchQueue = [];
let batchTimer = null;

// ── Langfuse API ────────────────────────────────────────────────────────────

async function flushBatch() {
  if (batchQueue.length === 0) return;
  const batch = batchQueue.splice(0, batchQueue.length);
  
  try {
    const res = await fetch(`${LANGFUSE_HOST}/api/public/ingestion`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${AUTH}`,
      },
      body: JSON.stringify({ batch }),
    });
    
    if (!res.ok) {
      const text = await res.text();
      console.error(`❌ Langfuse API error ${res.status}: ${text.substring(0, 200)}`);
    } else {
      console.log(`📤 Flushed ${batch.length} events to Langfuse`);
    }
  } catch (e) {
    console.error(`❌ Langfuse send failed: ${e.message}`);
    // Re-queue on failure
    batchQueue.unshift(...batch);
  }
}

function queueEvent(event) {
  batchQueue.push(event);
  if (!batchTimer) {
    batchTimer = setTimeout(() => {
      batchTimer = null;
      flushBatch();
    }, 5000); // flush every 5s
  }
}

// ── Session JSONL Parsing ───────────────────────────────────────────────────

function processLine(agentId, sessionFile, line) {
  try {
    const entry = JSON.parse(line);
    const msg = entry.message || {};
    const role = msg.role;
    const sessionId = path.basename(sessionFile, '.jsonl');
    const traceKey = `${agentId}:${sessionId}`;
    
    // User message = new trace (or continuation)
    if (role === 'user') {
      const content = typeof msg.content === 'string' 
        ? msg.content 
        : Array.isArray(msg.content) 
          ? msg.content.filter(c => c.type === 'text').map(c => c.text).join('\n')
          : '';
      
      if (!activeSessions.has(traceKey)) {
        const traceId = sessionId.substring(0, 8) + '-' + Date.now().toString(36);
        activeSessions.set(traceKey, { traceId, agentId, startTime: entry.timestamp });
        
        queueEvent({
          id: `trace-${traceId}`,
          timestamp: entry.timestamp,
          type: 'trace-create',
          body: {
            id: traceId,
            name: `openclaw-${agentId}`,
            userId: 'openclaw-gateway',
            sessionId: sessionId,
            input: content.substring(0, 2000),
            metadata: { agentId, sessionFile: path.basename(sessionFile) },
          },
        });
        console.log(`📊 Trace started: ${agentId}/${sessionId.substring(0, 8)}`);
      }
    }
    
    // Assistant message = generation
    if (role === 'assistant' && msg.usage) {
      const session = activeSessions.get(traceKey);
      if (!session) return;
      
      const content = Array.isArray(msg.content)
        ? msg.content.filter(c => c.type === 'text').map(c => c.text).join('\n')
        : '';
      
      const toolCalls = Array.isArray(msg.content)
        ? msg.content.filter(c => c.type === 'tool_use').map(c => c.name)
        : [];
      
      const genId = `gen-${session.traceId}-${Date.now().toString(36)}`;
      
      queueEvent({
        id: genId,
        timestamp: entry.timestamp,
        type: 'generation-create',
        body: {
          id: genId,
          traceId: session.traceId,
          name: msg.model || 'unknown',
          model: msg.model,
          modelParameters: { provider: msg.provider },
          output: content.substring(0, 3000) || (toolCalls.length ? `[tools: ${toolCalls.join(', ')}]` : ''),
          usage: {
            input: (msg.usage.input || 0) + (msg.usage.cacheRead || 0),
            output: msg.usage.output || 0,
            total: msg.usage.totalTokens || 0,
            inputCost: ((msg.usage.cost?.input || 0) + (msg.usage.cost?.cacheRead || 0) + (msg.usage.cost?.cacheWrite || 0)),
            outputCost: msg.usage.cost?.output || 0,
            totalCost: msg.usage.cost?.total || 0,
          },
          metadata: {
            stopReason: msg.stopReason,
            toolCalls,
            cacheRead: msg.usage.cacheRead,
            cacheWrite: msg.usage.cacheWrite,
          },
        },
      });
      
      console.log(`💬 Generation: ${agentId} | ${msg.model} | ${msg.usage.totalTokens}tok | $${(msg.usage.cost?.total || 0).toFixed(4)}`);
      
      // If stop reason is "stop" (not toolUse), close the trace
      if (msg.stopReason === 'stop' || msg.stopReason === 'end_turn') {
        queueEvent({
          id: `trace-update-${session.traceId}`,
          timestamp: entry.timestamp,
          type: 'trace-create',
          body: {
            id: session.traceId,
            output: content.substring(0, 2000),
          },
        });
        activeSessions.delete(traceKey);
        console.log(`✅ Trace complete: ${agentId}/${sessionId.substring(0, 8)}`);
      }
    }
  } catch (e) {
    // Skip unparseable lines
  }
}

// ── File Watcher ────────────────────────────────────────────────────────────

function tailFile(agentId, filePath) {
  const pos = filePositions.get(filePath) || 0;
  
  try {
    const stat = fs.statSync(filePath);
    if (stat.size <= pos) return; // no new data
    
    const stream = fs.createReadStream(filePath, { start: pos, encoding: 'utf-8' });
    let buffer = '';
    
    stream.on('data', (chunk) => {
      buffer += chunk;
      const lines = buffer.split('\n');
      buffer = lines.pop(); // keep incomplete line
      
      for (const line of lines) {
        if (line.trim()) processLine(agentId, filePath, line);
      }
    });
    
    stream.on('end', () => {
      filePositions.set(filePath, stat.size);
      if (buffer.trim()) processLine(agentId, filePath, buffer);
    });
  } catch (e) {
    // File might be gone
  }
}

function scanAgents() {
  try {
    const agents = fs.readdirSync(AGENTS_DIR).filter(d => {
      const s = fs.statSync(path.join(AGENTS_DIR, d));
      return s.isDirectory();
    });
    
    for (const agentId of agents) {
      const sessionsDir = path.join(AGENTS_DIR, agentId, 'sessions');
      if (!fs.existsSync(sessionsDir)) continue;
      
      const files = fs.readdirSync(sessionsDir)
        .filter(f => f.endsWith('.jsonl'))
        .map(f => path.join(sessionsDir, f));
      
      for (const file of files) {
        tailFile(agentId, file);
      }
    }
  } catch (e) {
    console.error(`Scan error: ${e.message}`);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

console.log(`🔗 OpenClaw → Langfuse Bridge`);
console.log(`   Host: ${LANGFUSE_HOST}`);
console.log(`   Agents: ${AGENTS_DIR}`);
console.log(`   Polling: every 10s`);
console.log('');

// Initial scan - skip existing content (only track new messages)
try {
  const agents = fs.readdirSync(AGENTS_DIR).filter(d => {
    try { return fs.statSync(path.join(AGENTS_DIR, d)).isDirectory(); } catch { return false; }
  });
  for (const agentId of agents) {
    const sessionsDir = path.join(AGENTS_DIR, agentId, 'sessions');
    if (!fs.existsSync(sessionsDir)) continue;
    const files = fs.readdirSync(sessionsDir).filter(f => f.endsWith('.jsonl'));
    for (const file of files) {
      const fp = path.join(sessionsDir, file);
      try { filePositions.set(fp, fs.statSync(fp).size); } catch {}
    }
  }
  console.log(`📁 Tracking ${filePositions.size} existing session files (skipping history)`);
} catch {}

// Poll for new data every 10s
setInterval(scanAgents, 10000);

// Flush remaining batch on exit
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down, flushing remaining events...');
  await flushBatch();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  await flushBatch();
  process.exit(0);
});
