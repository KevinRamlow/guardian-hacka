#!/bin/bash
# Cloud SQL Proxy Manager — Keeps proxy alive with fresh tokens
# Runs every 45min via cron (aligned with token refresh from Mac)
# Also runs on boot to restore proxy after server restart
set -euo pipefail

TOKEN_FILE="/Users/fonsecabc/.openclaw/workspace/.gcp-access-token"
PROXY_LOG="/tmp/cloud-sql-proxy.log"
INSTANCE="brandlovers-prod:us-east1:brandlovers-prod"
PORT=3306
LOG_TAG="[proxy-refresh]"
TS=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Check if token file exists and is recent (<2 hours old)
if [ ! -f "$TOKEN_FILE" ]; then
    echo "$LOG_TAG [$TS] No token file — waiting for Mac to push one"
    exit 0
fi

TOKEN_AGE=$(( $(date +%s) - $(stat -c %Y "$TOKEN_FILE") ))
if [ "$TOKEN_AGE" -gt 7200 ]; then
    echo "$LOG_TAG [$TS] Token is ${TOKEN_AGE}s old (>2hr) — likely expired, skipping proxy restart"
    exit 0
fi

# Check if proxy is already running and healthy
PROXY_PID=$(pgrep -f "cloud-sql-proxy.*$INSTANCE" | head -1 || true)
if [ -n "$PROXY_PID" ]; then
    # Test if MySQL is actually reachable
    if mysql -e 'SELECT 1' &>/dev/null; then
        echo "$LOG_TAG [$TS] OK: proxy running (PID=$PROXY_PID), MySQL healthy"
        exit 0
    else
        echo "$LOG_TAG [$TS] Proxy running but MySQL unreachable — restarting"
        kill "$PROXY_PID" 2>/dev/null
        sleep 2
    fi
fi

# Start proxy with fresh token
echo "$LOG_TAG [$TS] Starting Cloud SQL Proxy..."

cat > /tmp/start-proxy.sh << 'SCRIPT'
#!/bin/bash
TOKEN=$(cat /Users/fonsecabc/.openclaw/workspace/.gcp-access-token)
exec cloud-sql-proxy "brandlovers-prod:us-east1:brandlovers-prod" --port 3306 --token "$TOKEN"
SCRIPT
chmod +x /tmp/start-proxy.sh

nohup /tmp/start-proxy.sh > "$PROXY_LOG" 2>&1 &
NEW_PID=$!
sleep 3

if kill -0 "$NEW_PID" 2>/dev/null; then
    if mysql -e 'SELECT 1' &>/dev/null; then
        echo "$LOG_TAG [$TS] Proxy started (PID=$NEW_PID), MySQL OK"
    else
        echo "$LOG_TAG [$TS] Proxy started (PID=$NEW_PID) but MySQL not responding yet"
    fi
else
    echo "$LOG_TAG [$TS] FAILED to start proxy"
    tail -5 "$PROXY_LOG" 2>/dev/null
fi
