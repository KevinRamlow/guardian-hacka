#!/bin/bash
# Agent Metrics Dashboard - Simple text dashboard
# Usage: agent-dashboard.sh [--refresh]
set -euo pipefail

REFRESH="${1:-}"

# Skip clear if no terminal
if [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
  clear 2>/dev/null || true
fi

cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║           ANTON AGENT METRICS DASHBOARD                  ║
╚══════════════════════════════════════════════════════════╝
BANNER

echo ""

# 1. Current agents running
echo "📊 CURRENT STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash /Users/fonsecabc/.openclaw/workspace/scripts/agent-registry.sh list | tail -n +2
echo ""

# 2. Success rate (last 50 agents)
echo "✅ SUCCESS RATE (Last 50)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$(grep -E "DONE|FAIL|TIMEOUT" /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log 2>/dev/null | tail -50 | wc -l || echo 0)
SUCCESS=$(grep "DONE" /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log 2>/dev/null | tail -50 | wc -l || echo 0)
if [ "$TOTAL" -gt 0 ]; then
  RATE=$((SUCCESS * 100 / TOTAL))
  echo "Success: $SUCCESS/$TOTAL ($RATE%)"
else
  echo "No data"
fi
echo ""

# 3. Recent completions (last 10)
echo "🎯 RECENT COMPLETIONS (Last 10)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "DONE" /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log 2>/dev/null | tail -10 | while read -r line; do
  TASK=$(echo "$line" | awk '{print $2}' | tr -d ':')
  TIME=$(echo "$line" | grep -oP '\d+min' | head -1)
  SIZE=$(echo "$line" | grep -oP '\d+B' | head -1)
  echo "  $TASK ($TIME, $SIZE)"
done
echo ""

# 4. Failed agents (last 10)
echo "❌ RECENT FAILURES (Last 10)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep -E "FAIL|TIMEOUT" /Users/fonsecabc/.openclaw/tasks/agent-logs/watchdog.log 2>/dev/null | tail -10 | while read -r line; do
  TASK=$(echo "$line" | awk '{print $3}' | tr -d ':')
  REASON=$(echo "$line" | cut -d' ' -f4- | cut -c1-50)
  echo "  $TASK: $REASON"
done
echo ""

# 5. Cost tracking (if available)
if [ -f /tmp/agent-cost-report.json ]; then
  echo "💰 COST (24h)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat /tmp/agent-cost-report.json | jq -r '.[:5] | .[] | "  \(.task): $\(.estimatedCost)"'
  echo ""
fi

# 6. System health
echo "🏥 SYSTEM HEALTH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
GATEWAY_PID=$(pgrep -f "openclaw-gateway" | head -1 || echo "")
if [ -n "$GATEWAY_PID" ]; then
  echo "  Gateway: ✅ Running (PID $GATEWAY_PID)"
else
  echo "  Gateway: ❌ Down"
fi

PROXY_PID=$(pgrep -f "cloud-sql-proxy" | head -1 || echo "")
if [ -n "$PROXY_PID" ]; then
  echo "  Cloud SQL Proxy: ✅ Running (PID $PROXY_PID)"
else
  echo "  Cloud SQL Proxy: ❌ Down"
fi

if mysql -e "SELECT 1" &>/dev/null; then
  echo "  MySQL: ✅ Connected"
else
  echo "  MySQL: ❌ Disconnected"
fi

echo ""
echo "Last updated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"

if [ "$REFRESH" = "--refresh" ]; then
  sleep 5
  exec "$0" --refresh
fi
