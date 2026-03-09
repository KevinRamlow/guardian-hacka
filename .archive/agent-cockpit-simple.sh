#!/bin/bash
# Simplified Agent Cockpit - Uses OpenClaw tool output directly
# Usage: ./agent-cockpit-simple.sh [output-path]

set -euo pipefail

OUTPUT_HTML="${1:-/tmp/agent-cockpit.html}"

# Use the subagents tool output (assuming we can capture it)
# For now, we'll create a minimal dashboard that can be manually fed data

cat > "$OUTPUT_HTML" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agent Cockpit - Subagent Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, monospace;
            background: #0a0e27;
            color: #e0e0e0;
            padding: 20px;
            line-height: 1.6;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            font-size: 2em;
            margin-bottom: 10px;
            color: #00d9ff;
            text-shadow: 0 0 10px rgba(0, 217, 255, 0.5);
        }
        .subtitle {
            color: #888;
            margin-bottom: 30px;
            font-size: 0.9em;
        }
        .instructions {
            background: linear-gradient(135deg, #1a1f3a 0%, #0f1424 100%);
            border: 1px solid #2a3f5f;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 25px;
        }
        .instructions h2 {
            color: #00d9ff;
            margin-bottom: 15px;
        }
        .instructions code {
            background: #0a0e1a;
            padding: 2px 6px;
            border-radius: 3px;
            color: #00d9ff;
        }
        .instructions pre {
            background: #0a0e1a;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            margin: 10px 0;
            border-left: 3px solid #00d9ff;
        }
        textarea {
            width: 100%;
            min-height: 300px;
            background: #0a0e1a;
            border: 1px solid #2a3f5f;
            border-radius: 5px;
            color: #e0e0e0;
            padding: 15px;
            font-family: monospace;
            font-size: 0.9em;
            margin: 15px 0;
        }
        button {
            background: #00d9ff;
            color: #0a0e27;
            border: none;
            padding: 12px 24px;
            border-radius: 5px;
            font-weight: bold;
            cursor: pointer;
            font-size: 1em;
        }
        button:hover {
            background: #00b8d9;
        }
        .overview {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #1a1f3a 0%, #0f1424 100%);
            border: 1px solid #2a3f5f;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }
        .stat-card h3 {
            font-size: 0.9em;
            color: #888;
            margin-bottom: 10px;
            text-transform: uppercase;
        }
        .stat-card .value {
            font-size: 2.5em;
            font-weight: bold;
            color: #00d9ff;
        }
        .section {
            background: linear-gradient(135deg, #1a1f3a 0%, #0f1424 100%);
            border: 1px solid #2a3f5f;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }
        .section h2 {
            font-size: 1.4em;
            margin-bottom: 20px;
            color: #00d9ff;
            border-bottom: 2px solid #2a3f5f;
            padding-bottom: 10px;
        }
        .agent-card {
            background: #0f1424;
            border: 1px solid #2a3f5f;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            transition: all 0.3s ease;
        }
        .agent-card:hover {
            border-color: #00d9ff;
            box-shadow: 0 0 15px rgba(0, 217, 255, 0.2);
        }
        .agent-card.frozen {
            border-color: #ff6b6b;
            background: rgba(255, 107, 107, 0.05);
        }
        .agent-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
        }
        .agent-label {
            font-size: 1.1em;
            font-weight: bold;
            color: #00d9ff;
        }
        .agent-runtime {
            background: #2a3f5f;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            color: #00d9ff;
        }
        .agent-details {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
            font-size: 0.9em;
            color: #aaa;
        }
        .detail-item {
            display: flex;
            gap: 8px;
        }
        .detail-label {
            color: #666;
            font-weight: 600;
        }
        .detail-value {
            color: #e0e0e0;
        }
        .status-badge {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: bold;
        }
        .status-done { background: #27ae60; color: white; }
        .status-failed { background: #e74c3c; color: white; }
        .status-timeout { background: #f39c12; color: white; }
        .status-running { background: #3498db; color: white; }
        .frozen-badge {
            background: #ff6b6b;
            color: white;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.85em;
            font-weight: bold;
            margin-left: 10px;
        }
        .task-preview {
            margin-top: 10px;
            padding: 10px;
            background: #0a0e1a;
            border-left: 3px solid #2a3f5f;
            border-radius: 4px;
            font-size: 0.85em;
            color: #888;
            font-family: monospace;
            white-space: pre-wrap;
            word-break: break-word;
        }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 30px;
            font-size: 0.85em;
        }
        #data-display { display: none; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🦞 Agent Cockpit</h1>
        <div class="subtitle">Real-time subagent monitoring dashboard</div>
        
        <div class="instructions">
            <h2>📋 How to Use</h2>
            <p>This dashboard visualizes OpenClaw subagent data. To populate it:</p>
            <ol style="margin: 15px 0 15px 25px; line-height: 2;">
                <li>Run: <code>subagents list</code> in OpenClaw</li>
                <li>Copy the JSON output below</li>
                <li>Click "Load Data"</li>
            </ol>
            
            <textarea id="json-input" placeholder='Paste subagents JSON output here, e.g.:
{
  "status": "ok",
  "active": [...],
  "recent": [...]
}'></textarea>
            
            <button onclick="loadData()">Load Data</button>
        </div>
        
        <div id="data-display">
            <div class="overview">
                <div class="stat-card">
                    <h3>Active Agents</h3>
                    <div class="value" id="active-count">0</div>
                </div>
                <div class="stat-card">
                    <h3>Recent (30m)</h3>
                    <div class="value" id="recent-count">0</div>
                </div>
                <div class="stat-card">
                    <h3>Total Tracked</h3>
                    <div class="value" id="total-count">0</div>
                </div>
            </div>
            
            <div class="section">
                <h2>🔄 Active Agents</h2>
                <div id="active-agents"></div>
            </div>
            
            <div class="section">
                <h2>📋 Recent Activity (Last 30 min)</h2>
                <div id="recent-agents"></div>
            </div>
        </div>
        
        <div class="footer">
            Generated: <span id="timestamp"></span>
        </div>
    </div>
    
    <script>
        function loadData() {
            try {
                const input = document.getElementById('json-input').value;
                const data = JSON.parse(input);
                
                // Update stats
                document.getElementById('active-count').textContent = data.active?.length || 0;
                document.getElementById('recent-count').textContent = data.recent?.length || 0;
                document.getElementById('total-count').textContent = data.total || 0;
                document.getElementById('timestamp').textContent = new Date().toUTCString();
                
                // Show data display
                document.getElementById('data-display').style.display = 'block';
                
                // Render active agents
                const activeContainer = document.getElementById('active-agents');
                activeContainer.innerHTML = '';
                
                if (data.active && data.active.length > 0) {
                    data.active.forEach(agent => {
                        const taskId = agent.label?.match(/CAI-\d+/)?.[0] || '';
                        const runtimeMin = (agent.runtimeMs / 1000 / 60).toFixed(1);
                        const isFrozen = runtimeMin > 30;
                        
                        const card = document.createElement('div');
                        card.className = 'agent-card' + (isFrozen ? ' frozen' : '');
                        card.innerHTML = `
                            <div class="agent-header">
                                <div class="agent-label">🤖 ${agent.label}</div>
                                <div class="agent-runtime">${agent.runtime}</div>
                            </div>
                            <div class="agent-details">
                                ${taskId ? `<div class="detail-item"><span class="detail-label">Task:</span><span class="detail-value">${taskId}</span></div>` : ''}
                                <div class="detail-item"><span class="detail-label">Model:</span><span class="detail-value">${agent.model?.split('/')[1] || 'unknown'}</span></div>
                                <div class="detail-item"><span class="detail-label">Runtime:</span><span class="detail-value">${runtimeMin} min</span></div>
                                <div class="detail-item"><span class="detail-label">Status:</span><span class="detail-value"><span class="status-badge status-running">Running</span></span></div>
                            </div>
                            ${isFrozen ? '<span class="frozen-badge">⚠️ FROZEN (>30min)</span>' : ''}
                            <div class="task-preview">${(agent.task || '').substring(0, 200)}...</div>
                        `;
                        activeContainer.appendChild(card);
                    });
                } else {
                    activeContainer.innerHTML = '<p style="color: #666;">No active agents</p>';
                }
                
                // Render recent agents
                const recentContainer = document.getElementById('recent-agents');
                recentContainer.innerHTML = '';
                
                if (data.recent && data.recent.length > 0) {
                    data.recent.forEach(agent => {
                        const taskId = agent.label?.match(/CAI-\d+/)?.[0] || '';
                        const tokensK = agent.totalTokens ? (agent.totalTokens / 1000).toFixed(1) : null;
                        
                        let statusBadge = '';
                        if (agent.status === 'done') statusBadge = '<span class="status-badge status-done">✅ Done</span>';
                        else if (agent.status === 'failed') statusBadge = '<span class="status-badge status-failed">❌ Failed</span>';
                        else if (agent.status === 'timeout') statusBadge = '<span class="status-badge status-timeout">⏱️ Timeout</span>';
                        
                        const card = document.createElement('div');
                        card.className = 'agent-card';
                        card.innerHTML = `
                            <div class="agent-header">
                                <div class="agent-label">${agent.label}</div>
                                <div class="agent-runtime">${agent.runtime}</div>
                            </div>
                            <div class="agent-details">
                                ${taskId ? `<div class="detail-item"><span class="detail-label">Task:</span><span class="detail-value">${taskId}</span></div>` : ''}
                                ${tokensK ? `<div class="detail-item"><span class="detail-label">Tokens:</span><span class="detail-value">${tokensK}k</span></div>` : ''}
                                <div class="detail-item"><span class="detail-label">Status:</span><span class="detail-value">${statusBadge}</span></div>
                            </div>
                        `;
                        recentContainer.appendChild(card);
                    });
                } else {
                    recentContainer.innerHTML = '<p style="color: #666;">No recent activity</p>';
                }
                
                alert('✅ Data loaded successfully!');
                
            } catch (error) {
                alert('❌ Error parsing JSON: ' + error.message);
            }
        }
        
        document.getElementById('timestamp').textContent = new Date().toUTCString();
    </script>
</body>
</html>
EOF

echo "✅ Agent Cockpit dashboard created: $OUTPUT_HTML"
echo ""
echo "📖 Usage:"
echo "  1. Open $OUTPUT_HTML in your browser"
echo "  2. Run 'subagents list' in OpenClaw chat"
echo "  3. Copy the JSON output"
echo "  4. Paste it into the dashboard and click 'Load Data'"
echo ""
echo "🌐 Or serve it: python3 -m http.server 8765 --directory $(dirname "$OUTPUT_HTML")"
