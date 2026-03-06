#!/usr/bin/env node
/**
 * Linear Task Sync - Monitor sub-agents and update Linear tasks
 * Works with both OpenClaw subagents and Claude Code (ACP) agents
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Load environment manually (no dotenv dependency)
const envFile = path.join(__dirname, '../.env.linear');
if (fs.existsSync(envFile)) {
  const envContent = fs.readFileSync(envFile, 'utf8');
  const keyMatch = envContent.match(/LINEAR_API_KEY="?([^"\n]+)"?/);
  if (keyMatch) {
    process.env.LINEAR_API_KEY = keyMatch[1];
  }
}

const LINEAR_API_KEY = process.env.LINEAR_API_KEY;
if (!LINEAR_API_KEY) {
  console.error('❌ Error: LINEAR_API_KEY not set in .env.linear');
  process.exit(1);
}

const STATE_FILE = path.join(__dirname, '../.linear-sync-state.json');

// Initialize state file
if (!fs.existsSync(STATE_FILE)) {
  fs.writeFileSync(STATE_FILE, JSON.stringify({ lastSync: 0, taskAgents: {} }, null, 2));
}

// Linear GraphQL API helper
async function linearQuery(query) {
  const res = await fetch('https://api.linear.app/graphql', {
    method: 'POST',
    headers: {
      'Authorization': LINEAR_API_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ query })
  });
  
  const json = await res.json();
  if (json.errors) {
    throw new Error(`Linear API error: ${JSON.stringify(json.errors)}`);
  }
  return json.data;
}

// Update task with comment
async function addTaskComment(issueId, comment) {
  const mutation = `mutation {
    commentCreate(
      input: {
        issueId: "${issueId}"
        body: ${JSON.stringify(comment)}
      }
    ) {
      success
      comment { id }
    }
  }`;
  
  return await linearQuery(mutation);
}

// Update task status
async function updateTaskStatus(issueId, statusName) {
  // Get state ID first
  const stateQuery = `{
    workflowStates(filter: { name: { eq: "${statusName}" } }) {
      nodes {
        id
        name
      }
    }
  }`;
  
  const stateData = await linearQuery(stateQuery);
  const stateId = stateData.workflowStates.nodes[0]?.id;
  
  if (!stateId) {
    console.warn(`⚠️  Warning: Status '${statusName}' not found`);
    return null;
  }
  
  const mutation = `mutation {
    issueUpdate(
      id: "${issueId}"
      input: {
        stateId: "${stateId}"
      }
    ) {
      success
      issue {
        id
        identifier
        state { name }
      }
    }
  }`;
  
  return await linearQuery(mutation);
}

// Get active subagents from OpenClaw state directory
function getActiveSubagents() {
  try {
    // Read from OpenClaw state directory (session files)
    const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(process.env.HOME, '.openclaw');
    const sessionsDir = path.join(stateDir, 'sessions');
    
    if (!fs.existsSync(sessionsDir)) {
      return { active: [], recent: [] };
    }
    
    // Parse session files to find active subagents
    const sessions = fs.readdirSync(sessionsDir)
      .filter(f => f.endsWith('.json'))
      .map(f => {
        try {
          const content = fs.readFileSync(path.join(sessionsDir, f), 'utf8');
          return JSON.parse(content);
        } catch (err) {
          return null;
        }
      })
      .filter(s => s && s.sessionKey && s.sessionKey.includes('subagent'));
    
    // Separate active vs recent
    const now = Date.now();
    const active = sessions.filter(s => !s.endedAt || (now - s.startedAt) < 3600000); // Active if no end or <1h old
    const recent = sessions.filter(s => s.endedAt && (now - s.endedAt) < 1800000); // Recent if ended <30min ago
    
    return { active, recent };
  } catch (err) {
    console.warn('⚠️  Could not read session files:', err.message);
    return { active: [], recent: [] };
  }
}

// Generate status report
function generateStatusReport(sessionKey, label, status, runtimeMs, model) {
  const runtimeMin = Math.floor(runtimeMs / 60000);
  const statusEmoji = status === 'running' ? '🔄' : status === 'done' ? '✅' : '❌';
  
  return `**Sub-Agent Status Update** (Auto-generated)

${statusEmoji} **Status:** ${status}
⏱️ **Runtime:** ${runtimeMin}m
🤖 **Model:** ${model}
🔑 **Session:** \`${sessionKey}\`

_Last updated: ${new Date().toISOString().split('T')[0]} ${new Date().toISOString().split('T')[1].split('.')[0]} UTC_`;
}

// Main sync logic
async function syncTasks() {
  console.log('🔄 Starting Linear task sync...');
  
  try {
    // Get all CAI team tasks (not completed/canceled)
    const tasksQuery = `{
      issues(filter: { 
        team: { key: { eq: "CAI" } }
        state: { type: { nin: ["completed", "canceled"] } }
      }) {
        nodes {
          id
          identifier
          title
          state { name }
          description
        }
      }
    }`;
    
    const tasksData = await linearQuery(tasksQuery);
    const tasks = tasksData.issues.nodes;
    
    // Get active subagents
    const { active, recent } = getActiveSubagents();
    
    console.log(`  📊 Found ${tasks.length} active tasks, ${active.length} active subagents, ${recent.length} recent`);
    
    // Process each task
    for (const task of tasks) {
      console.log(`  📋 Checking ${task.identifier}: ${task.title}`);
      
      // Extract session ID from description
      const sessionMatch = task.description.match(/Session:\*\* ([a-f0-9-]{36})|Session: `?([a-f0-9-]{36})/);
      if (!sessionMatch) {
        console.log(`    ⏭️  No session ID found, skipping`);
        continue;
      }
      
      const sessionId = sessionMatch[1] || sessionMatch[2];
      console.log(`    🔍 Looking for session: ${sessionId.substring(0, 8)}...`);
      
      // Check if session is active
      const activeMatch = active.find(s => s.sessionKey && s.sessionKey.includes(sessionId));
      const recentMatch = recent.find(s => s.sessionKey && s.sessionKey.includes(sessionId));
      
      if (activeMatch) {
        console.log(`    🔄 Found active sub-agent`);
        
        // Check if already updated today
        const today = new Date().toISOString().split('T')[0];
        if (task.description.includes(`Last updated: ${today}`)) {
          console.log(`    ⏭️  Already updated today`);
          continue;
        }
        
        // Generate and add status report
        const report = generateStatusReport(
          activeMatch.sessionKey,
          activeMatch.label || 'unknown',
          'running',
          activeMatch.runtimeMs || Date.now() - activeMatch.startedAt,
          activeMatch.model || 'unknown'
        );
        
        await addTaskComment(task.id, report);
        console.log(`    ✏️  Added status update`);
        
      } else if (recentMatch && recentMatch.status === 'done' && task.state.name !== 'Done') {
        console.log(`    ✅ Sub-agent completed, updating task status`);
        await updateTaskStatus(task.id, 'Done');
        
      } else {
        console.log(`    ⏭️  No active sub-agent found`);
      }
    }
    
    console.log('✅ Sync complete');
    
    // Update state file
    const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    state.lastSync = Date.now();
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    
  } catch (err) {
    console.error('❌ Sync failed:', err.message);
    process.exit(1);
  }
}

// Run sync
syncTasks();
