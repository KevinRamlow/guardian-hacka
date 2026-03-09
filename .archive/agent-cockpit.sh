#!/bin/bash
# Agent Cockpit Dashboard - Monitor all running sub-agents
# Usage: ./agent-cockpit.sh [--html | --serve]

set -euo pipefail

# Load Linear API key
if [[ -f "/root/.openclaw/workspace/.env.linear" ]]; then
    source /root/.openclaw/workspace/.env.linear
fi

OUTPUT_MODE="${1:-text}"
HTML_FILE="/tmp/agent-cockpit.html"
PORT="${2:-8765}"

# Cost estimates (rough, per 1M tokens)
SONNET_4_5_INPUT_COST=3.00
SONNET_4_5_OUTPUT_COST=15.00
SONNET_4_5_CACHE_COST=0.30

# Get subagents data
get_subagents_json() {
    # Use OpenClaw CLI to get subagents (using 📊 alias)
    openclaw subagents list --json 2>/dev/null || echo '{}'
}

# Get Linear task data
get_linear_task() {
    local task_id="$1"
    
    if [[ -z "$LINEAR_API_KEY" ]]; then
        echo "{}"
        return
    fi
    
    curl -s -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"query{issue(id:\\\"$task_id\\\"){state{name} comments(first:5 orderBy:createdAt){nodes{createdAt body}}}}\"}" 2>/dev/null || echo "{}"
}

# Parse runtime to minutes
parse_runtime_ms() {
    local ms="$1"
    echo "scale=1; $ms / 1000 / 60" | bc
}

# Calculate cost
calculate_cost() {
    local input_tokens="${1:-0}"
    local output_tokens="${2:-0}"
    local cache_tokens="${3:-0}"
    
    local input_cost=$(echo "scale=4; $input_tokens * $SONNET_4_5_INPUT_COST / 1000000" | bc)
    local output_cost=$(echo "scale=4; $output_tokens * $SONNET_4_5_OUTPUT_COST / 1000000" | bc)
    local cache_cost=$(echo "scale=4; $cache_tokens * $SONNET_4_5_CACHE_COST / 1000000" | bc)
    
    echo "scale=4; $input_cost + $output_cost + $cache_cost" | bc
}

# Extract Linear task ID from label or task description
extract_task_id() {
    local text="$1"
    echo "$text" | grep -oP 'CAI-\d+' | head -1 || echo ""
}

# Check if agent is frozen (>30min with no Linear updates)
check_frozen() {
    local runtime_ms="$1"
    local last_comment_time="$2"
    
    local runtime_min=$(parse_runtime_ms "$runtime_ms")
    local runtime_min_int=${runtime_min%.*}
    
    if [[ $runtime_min_int -lt 30 ]]; then
        echo "ok"
        return
    fi
    
    if [[ -z "$last_comment_time" || "$last_comment_time" == "null" ]]; then
        echo "frozen-no-logs"
        return
    fi
    
    # Calculate time since last comment
    local now=$(date +%s)
    local comment_ts=$(date -d "$last_comment_time" +%s 2>/dev/null || echo "$now")
    local minutes_since=$(( ($now - $comment_ts) / 60 ))
    
    if [[ $minutes_since -gt 15 ]]; then
        echo "frozen-stale"
    else
        echo "ok"
    fi
}

# Generate text dashboard
generate_text_dashboard() {
    local data="$1"
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              Agent Cockpit - Subagent Monitor                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local active_count=$(echo "$data" | jq -r '.active | length')
    local recent_count=$(echo "$data" | jq -r '.recent | length')
    local total_count=$(echo "$data" | jq -r '.total // 0')
    
    echo "📊 OVERVIEW"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Active agents:          $active_count"
    echo "  Recent (last 30m):      $recent_count"
    echo "  Total tracked:          $total_count"
    echo ""
    
    # Active agents
    if [[ $active_count -gt 0 ]]; then
        echo "🔄 ACTIVE AGENTS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "$data" | jq -r '.active[] | @json' | while IFS= read -r agent_json; do
            local label=$(echo "$agent_json" | jq -r '.label')
            local runtime=$(echo "$agent_json" | jq -r '.runtime')
            local runtime_ms=$(echo "$agent_json" | jq -r '.runtimeMs')
            local model=$(echo "$agent_json" | jq -r '.model // "unknown"')
            local task_preview=$(echo "$agent_json" | jq -r '.task[:80]')
            
            # Extract task ID
            local task_id=$(extract_task_id "$label")
            if [[ -z "$task_id" ]]; then
                task_id=$(extract_task_id "$task_preview")
            fi
            
            # Get Linear status
            local linear_state="unknown"
            local last_comment=""
            if [[ -n "$task_id" ]]; then
                local linear_data=$(get_linear_task "$task_id")
                linear_state=$(echo "$linear_data" | jq -r '.data.issue.state.name // "unknown"')
                last_comment=$(echo "$linear_data" | jq -r '.data.issue.comments.nodes[0].createdAt // ""')
            fi
            
            # Check if frozen
            local frozen_status=$(check_frozen "$runtime_ms" "$last_comment")
            local frozen_icon=""
            if [[ "$frozen_status" == "frozen-no-logs" ]]; then
                frozen_icon=" ⚠️  FROZEN (no logs)"
            elif [[ "$frozen_status" == "frozen-stale" ]]; then
                frozen_icon=" ⚠️  FROZEN (stale logs)"
            fi
            
            echo ""
            echo "  🤖 $label ($runtime)$frozen_icon"
            if [[ -n "$task_id" ]]; then
                echo "     Task: $task_id [$linear_state]"
            fi
            echo "     Model: ${model##*/}"
            echo "     Task: $task_preview..."
        done
        echo ""
    fi
    
    # Recent agents
    if [[ $recent_count -gt 0 ]]; then
        echo "📋 RECENT (Last 30 min)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local total_cost=0
        
        echo "$data" | jq -r '.recent[] | @json' | while IFS= read -r agent_json; do
            local label=$(echo "$agent_json" | jq -r '.label')
            local status=$(echo "$agent_json" | jq -r '.status')
            local runtime=$(echo "$agent_json" | jq -r '.runtime')
            local total_tokens=$(echo "$agent_json" | jq -r '.totalTokens // 0')
            
            # Extract task ID
            local task_id=$(extract_task_id "$label")
            
            local status_icon="✅"
            if [[ "$status" == "failed" ]]; then
                status_icon="❌"
            elif [[ "$status" == "timeout" ]]; then
                status_icon="⏱️"
            fi
            
            echo "  $status_icon $label ($runtime)"
            if [[ -n "$task_id" ]]; then
                echo "     Task: $task_id"
            fi
            if [[ $total_tokens -gt 0 ]]; then
                local tokens_k=$(echo "scale=1; $total_tokens / 1000" | bc)
                echo "     Tokens: ${tokens_k}k"
            fi
        done
        echo ""
    fi
    
    echo "════════════════════════════════════════════════════════════════"
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}

# Generate HTML dashboard
generate_html_dashboard() {
    local data="$1"
    
    local active_count=$(echo "$data" | jq -r '.active | length')
    local recent_count=$(echo "$data" | jq -r '.recent | length')
    local total_count=$(echo "$data" | jq -r '.total // 0')
    
    # Calculate totals
    local total_cost=0
    local total_tokens=0
    
    cat > "$HTML_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="30">
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
        }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 30px;
            font-size: 0.85em;
        }
        .refresh-note {
            color: #888;
            font-size: 0.8em;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🦞 Agent Cockpit</h1>
        <div class="subtitle">Real-time subagent monitoring dashboard</div>
        
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
        
        <div class="footer">
            Generated: <span id="timestamp"></span>
            <div class="refresh-note">Auto-refresh every 30 seconds</div>
        </div>
    </div>
    
    <script>
        const data = 
EOF

    # Inject JSON data
    echo "$data" | jq '.' >> "$HTML_FILE"
    
    cat >> "$HTML_FILE" <<'EOF'
;
        
        // Update stats
        document.getElementById('active-count').textContent = data.active?.length || 0;
        document.getElementById('recent-count').textContent = data.recent?.length || 0;
        document.getElementById('total-count').textContent = data.total || 0;
        document.getElementById('timestamp').textContent = new Date().toUTCString();
        
        // Render active agents
        const activeContainer = document.getElementById('active-agents');
        if (data.active && data.active.length > 0) {
            data.active.forEach(agent => {
                const taskId = agent.label.match(/CAI-\d+/)?.[0] || '';
                const runtimeMin = (agent.runtimeMs / 1000 / 60).toFixed(1);
                const isFrozen = runtimeMin > 30; // Simplified check
                
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
                    <div class="task-preview">${agent.task?.substring(0, 150)}...</div>
                `;
                activeContainer.appendChild(card);
            });
        } else {
            activeContainer.innerHTML = '<p style="color: #666;">No active agents</p>';
        }
        
        // Render recent agents
        const recentContainer = document.getElementById('recent-agents');
        if (data.recent && data.recent.length > 0) {
            data.recent.forEach(agent => {
                const taskId = agent.label.match(/CAI-\d+/)?.[0] || '';
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
    </script>
</body>
</html>
EOF

    echo "$HTML_FILE"
}

# Main execution
main() {
    echo "🔍 Fetching subagent data..." >&2
    
    local data=$(get_subagents_json)
    
    if [[ "$OUTPUT_MODE" == "--html" ]]; then
        local html_path=$(generate_html_dashboard "$data")
        echo "✅ HTML dashboard generated: $html_path" >&2
        echo "$html_path"
        
    elif [[ "$OUTPUT_MODE" == "--serve" ]]; then
        local html_path=$(generate_html_dashboard "$data")
        echo "✅ HTML dashboard generated: $html_path" >&2
        echo "🌐 Starting web server on http://localhost:$PORT" >&2
        echo "   Press Ctrl+C to stop" >&2
        cd /tmp && python3 -m http.server "$PORT"
        
    else
        generate_text_dashboard "$data"
    fi
}

main
