#!/bin/bash
# Generate Guardian Eval Dashboard HTML
# Usage: bash guardian-eval-dashboard.sh [output.html]

OUTPUT="${1:-/tmp/guardian-eval-dashboard.html}"

# Get eval data
EVAL_DATA=$(bash "$(dirname "$0")/cockpit-eval-data.sh")

# Generate HTML
cat > "$OUTPUT" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Guardian Eval Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, monospace;
            background: #0a0e1a;
            color: #e0e0e0;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #1e3a5f;
        }
        h1 {
            font-size: 28px;
            color: #00d9ff;
            text-shadow: 0 0 10px rgba(0, 217, 255, 0.5);
        }
        .refresh-btn {
            background: #1e3a5f;
            color: #00d9ff;
            border: 1px solid #00d9ff;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        .refresh-btn:hover {
            background: #00d9ff;
            color: #0a0e1a;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }
        .stat-card h3 {
            font-size: 14px;
            color: #888;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .stat-value {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .stat-card.target .stat-value { color: #ff9800; }
        .stat-card.current .stat-value { color: #00d9ff; }
        .stat-card.remaining .stat-value { color: #4caf50; }
        .stat-delta {
            font-size: 14px;
            color: #888;
        }
        .progress-section {
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 30px;
        }
        .progress-section h2 {
            font-size: 18px;
            color: #00d9ff;
            margin-bottom: 15px;
        }
        .progress-bar-container {
            background: #0a0e1a;
            height: 30px;
            border-radius: 15px;
            overflow: hidden;
            margin-bottom: 10px;
            border: 1px solid #1e3a5f;
        }
        .progress-bar {
            height: 100%;
            background: linear-gradient(90deg, #00d9ff 0%, #0099cc 100%);
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #0a0e1a;
            font-weight: bold;
            font-size: 14px;
        }
        .progress-info {
            display: flex;
            justify-content: space-between;
            font-size: 14px;
            color: #888;
        }
        .runs-grid {
            display: grid;
            gap: 15px;
        }
        .run-card {
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 8px;
            padding: 15px;
            display: grid;
            grid-template-columns: 1fr auto auto;
            gap: 15px;
            align-items: center;
        }
        .run-info h4 {
            font-size: 14px;
            color: #00d9ff;
            margin-bottom: 5px;
        }
        .run-info p {
            font-size: 12px;
            color: #888;
        }
        .run-accuracy {
            font-size: 24px;
            font-weight: bold;
            color: #4caf50;
        }
        .run-delta {
            font-size: 16px;
            padding: 5px 10px;
            border-radius: 5px;
            font-weight: bold;
        }
        .run-delta.positive { color: #4caf50; background: rgba(76, 175, 80, 0.2); }
        .run-delta.negative { color: #f44336; background: rgba(244, 67, 54, 0.2); }
        .run-delta.neutral { color: #888; background: rgba(136, 136, 136, 0.2); }
        .no-data {
            text-align: center;
            padding: 40px;
            color: #888;
            font-size: 14px;
        }
        .current-eval {
            background: linear-gradient(135deg, #1a3a1a 0%, #0f200f 100%);
            border: 2px solid #4caf50;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { box-shadow: 0 0 10px rgba(76, 175, 80, 0.5); }
            50% { box-shadow: 0 0 20px rgba(76, 175, 80, 0.8); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Guardian Eval Dashboard</h1>
            <button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button>
        </div>

        <div class="stats-grid">
            <div class="stat-card target">
                <h3>Target</h3>
                <div class="stat-value" id="target-accuracy">--</div>
                <div class="stat-delta" id="target-delta">--</div>
            </div>
            <div class="stat-card current">
                <h3>Current</h3>
                <div class="stat-value" id="current-accuracy">--</div>
                <div class="stat-delta" id="current-delta">--</div>
            </div>
            <div class="stat-card remaining">
                <h3>Remaining</h3>
                <div class="stat-value" id="remaining-pp">--</div>
                <div class="stat-delta" id="iterations">--</div>
            </div>
        </div>

        <div class="progress-section" id="current-eval-section" style="display:none;">
            <h2>⚡ Current Eval Running</h2>
            <div class="progress-bar-container">
                <div class="progress-bar" id="current-progress-bar">0%</div>
            </div>
            <div class="progress-info">
                <span id="current-progress-text">--</span>
                <span id="current-elapsed">--</span>
            </div>
        </div>

        <div class="progress-section">
            <h2>📊 Recent Runs</h2>
            <div class="runs-grid" id="recent-runs"></div>
        </div>
    </div>

    <script>
        const data = EVAL_DATA_PLACEHOLDER;

        // Populate target stats
        const target = data.target;
        document.getElementById('target-accuracy').textContent = 
            (target.target_accuracy * 100).toFixed(1) + '%';
        document.getElementById('target-delta').textContent = 
            '+' + target.target_delta_pp.toFixed(1) + 'pp vs baseline';

        document.getElementById('current-accuracy').textContent = 
            (target.current_accuracy * 100).toFixed(1) + '%';
        document.getElementById('current-delta').textContent = 
            (target.current_delta_pp >= 0 ? '+' : '') + target.current_delta_pp.toFixed(1) + 'pp';

        document.getElementById('remaining-pp').textContent = 
            target.remaining_pp.toFixed(1) + 'pp';
        document.getElementById('iterations').textContent = 
            target.iterations + ' iterations';

        // Show current eval if running
        if (data.current_eval) {
            document.getElementById('current-eval-section').style.display = 'block';
            const progress = data.current_eval.progress;
            const progressBar = document.getElementById('current-progress-bar');
            progressBar.style.width = progress.percent + '%';
            progressBar.textContent = progress.percent + '%';
            
            document.getElementById('current-progress-text').textContent = 
                progress.completed + '/' + progress.total + ' cases';
            document.getElementById('current-elapsed').textContent = 
                'Elapsed: ' + data.current_eval.elapsed;
        }

        // Populate recent runs
        const runsContainer = document.getElementById('recent-runs');
        if (data.recent_runs.length === 0) {
            runsContainer.innerHTML = '<div class="no-data">No completed runs yet</div>';
        } else {
            runsContainer.innerHTML = data.recent_runs.map(run => {
                const deltaNum = parseFloat(run.delta_pp);
                const deltaClass = deltaNum > 0 ? 'positive' : deltaNum < 0 ? 'negative' : 'neutral';
                
                return `
                    <div class="run-card">
                        <div class="run-info">
                            <h4>${run.run_name}</h4>
                            <p>${run.timestamp.replace('_', ' ')}</p>
                        </div>
                        <div class="run-accuracy">${run.accuracy}%</div>
                        <div class="run-delta ${deltaClass}">${run.delta_pp}pp</div>
                    </div>
                `;
            }).join('');
        }

        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>
HTMLEOF

# Inject data
sed -i '' "s|EVAL_DATA_PLACEHOLDER|$EVAL_DATA|g" "$OUTPUT"

echo "✓ Dashboard generated: $OUTPUT"
echo "  Open: open $OUTPUT"
echo "  Or visit: http://localhost:8765/$(basename "$OUTPUT")"
