#!/usr/bin/env python3
"""Generate Guardian Eval Dashboard HTML with live data."""

import json
import subprocess
import sys
from pathlib import Path

def get_eval_data():
    """Get eval data from shell script."""
    result = subprocess.run(
        ['bash', str(Path(__file__).parent / 'cockpit-eval-data.sh')],
        capture_output=True,
        text=True
    )
    return json.loads(result.stdout)

def generate_html(data, output_path):
    """Generate HTML dashboard."""
    html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Guardian Eval Dashboard</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, monospace;
            background: #0a0e1a;
            color: #e0e0e0;
            padding: 20px;
        }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #1e3a5f;
        }}
        h1 {{
            font-size: 28px;
            color: #00d9ff;
            text-shadow: 0 0 10px rgba(0, 217, 255, 0.5);
        }}
        .refresh-btn {{
            background: #1e3a5f;
            color: #00d9ff;
            border: 1px solid #00d9ff;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }}
        .refresh-btn:hover {{
            background: #00d9ff;
            color: #0a0e1a;
        }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-card {{
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }}
        .stat-card h3 {{
            font-size: 14px;
            color: #888;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        .stat-value {{
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 5px;
        }}
        .stat-card.target .stat-value {{ color: #ff9800; }}
        .stat-card.current .stat-value {{ color: #00d9ff; }}
        .stat-card.remaining .stat-value {{ color: #4caf50; }}
        .stat-delta {{
            font-size: 14px;
            color: #888;
        }}
        .progress-section {{
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 30px;
        }}
        .progress-section h2 {{
            font-size: 18px;
            color: #00d9ff;
            margin-bottom: 15px;
        }}
        .progress-bar-container {{
            background: #0a0e1a;
            height: 30px;
            border-radius: 15px;
            overflow: hidden;
            margin-bottom: 10px;
            border: 1px solid #1e3a5f;
        }}
        .progress-bar {{
            height: 100%;
            background: linear-gradient(90deg, #00d9ff 0%, #0099cc 100%);
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #0a0e1a;
            font-weight: bold;
            font-size: 14px;
        }}
        .progress-info {{
            display: flex;
            justify-content: space-between;
            font-size: 14px;
            color: #888;
        }}
        .runs-grid {{
            display: grid;
            gap: 15px;
        }}
        .run-card {{
            background: linear-gradient(135deg, #1a1f35 0%, #0f1420 100%);
            border: 1px solid #1e3a5f;
            border-radius: 8px;
            padding: 15px;
            display: grid;
            grid-template-columns: 1fr auto auto;
            gap: 15px;
            align-items: center;
        }}
        .run-info h4 {{
            font-size: 14px;
            color: #00d9ff;
            margin-bottom: 5px;
        }}
        .run-info p {{
            font-size: 12px;
            color: #888;
        }}
        .run-accuracy {{
            font-size: 24px;
            font-weight: bold;
            color: #4caf50;
        }}
        .run-delta {{
            font-size: 16px;
            padding: 5px 10px;
            border-radius: 5px;
            font-weight: bold;
        }}
        .run-delta.positive {{ color: #4caf50; background: rgba(76, 175, 80, 0.2); }}
        .run-delta.negative {{ color: #f44336; background: rgba(244, 67, 54, 0.2); }}
        .run-delta.neutral {{ color: #888; background: rgba(136, 136, 136, 0.2); }}
        .no-data {{
            text-align: center;
            padding: 40px;
            color: #888;
            font-size: 14px;
        }}
        @keyframes pulse {{
            0%, 100% {{ box-shadow: 0 0 10px rgba(76, 175, 80, 0.5); }}
            50% {{ box-shadow: 0 0 20px rgba(76, 175, 80, 0.8); }}
        }}
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
                <div class="stat-value">{data['target']['target_accuracy'] * 100:.1f}%</div>
                <div class="stat-delta">+{data['target']['target_delta_pp']:.1f}pp vs baseline</div>
            </div>
            <div class="stat-card current">
                <h3>Current</h3>
                <div class="stat-value">{data['target']['current_accuracy'] * 100:.1f}%</div>
                <div class="stat-delta">{data['target']['current_delta_pp']:+.1f}pp</div>
            </div>
            <div class="stat-card remaining">
                <h3>Remaining</h3>
                <div class="stat-value">{data['target']['remaining_pp']:.1f}pp</div>
                <div class="stat-delta">{data['target']['iterations']} iterations</div>
            </div>
        </div>
'''

    # Current eval section
    if data['current_eval']:
        progress = data['current_eval']['progress']
        html += f'''
        <div class="progress-section" style="background: linear-gradient(135deg, #1a3a1a 0%, #0f200f 100%); border: 2px solid #4caf50; animation: pulse 2s infinite;">
            <h2>⚡ Current Eval Running</h2>
            <div class="progress-bar-container">
                <div class="progress-bar" style="width: {progress['percent']}%">{progress['percent']}%</div>
            </div>
            <div class="progress-info">
                <span>{progress['completed']}/{progress['total']} cases</span>
                <span>Elapsed: {data['current_eval']['elapsed']}</span>
            </div>
        </div>
'''

    # Recent runs
    html += '''
        <div class="progress-section">
            <h2>📊 Recent Runs</h2>
            <div class="runs-grid">
'''
    
    if not data['recent_runs']:
        html += '<div class="no-data">No completed runs yet</div>'
    else:
        for run in data['recent_runs']:
            delta_num = float(run['delta_pp'])
            delta_class = 'positive' if delta_num > 0 else 'negative' if delta_num < 0 else 'neutral'
            timestamp = run['timestamp'].replace('_', ' ')
            
            html += f'''
                <div class="run-card">
                    <div class="run-info">
                        <h4>{run['run_name']}</h4>
                        <p>{timestamp}</p>
                    </div>
                    <div class="run-accuracy">{run['accuracy']}%</div>
                    <div class="run-delta {delta_class}">{run['delta_pp']}pp</div>
                </div>
'''

    html += '''
            </div>
        </div>
    </div>
    <script>
        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>
'''
    
    with open(output_path, 'w') as f:
        f.write(html)

if __name__ == '__main__':
    output = sys.argv[1] if len(sys.argv) > 1 else '/tmp/guardian-eval-dashboard.html'
    data = get_eval_data()
    generate_html(data, output)
    print(f"✓ Dashboard generated: {output}")
    print(f"  Open in browser: http://localhost:8765/{Path(output).name}")
