#!/usr/bin/env node
// Helper script to fetch subagents data via OpenClaw internal API
// Usage: node get-subagents-data.js

const fs = require('fs');
const path = require('path');

// Try to load OpenClaw's session manager
const sessionFile = path.join(process.env.HOME || '/root', '.openclaw', 'sessions.json');

async function getSubagentsData() {
    try {
        // Read OpenClaw session data if available
        if (fs.existsSync(sessionFile)) {
            const sessions = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
            
            // Filter for subagent sessions
            const subagents = Object.values(sessions)
                .filter(s => s.type === 'subagent' && s.requester === 'agent:main:main')
                .map(s => ({
                    sessionKey: s.key,
                    label: s.label || 'unknown',
                    status: s.status || 'unknown',
                    startedAt: s.startedAt,
                    runtime: s.runtime,
                    runtimeMs: s.runtimeMs,
                    model: s.model,
                    task: s.task || '',
                    totalTokens: s.totalTokens || 0
                }));
            
            const active = subagents.filter(s => s.status === 'running');
            const recent = subagents.filter(s => s.status !== 'running').slice(0, 10);
            
            return {
                status: 'ok',
                total: subagents.length,
                active,
                recent
            };
        }
        
        // Fallback: return empty structure
        return {
            status: 'ok',
            total: 0,
            active: [],
            recent: []
        };
        
    } catch (error) {
        console.error(JSON.stringify({
            status: 'error',
            error: error.message,
            total: 0,
            active: [],
            recent: []
        }));
        process.exit(1);
    }
}

getSubagentsData().then(data => {
    console.log(JSON.stringify(data, null, 2));
}).catch(err => {
    console.error(JSON.stringify({
        status: 'error',
        error: err.message,
        total: 0,
        active: [],
        recent: []
    }));
    process.exit(1);
});
