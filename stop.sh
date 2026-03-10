#!/bin/bash
# Stop Anton locally
echo "=== Stopping gateway ==="
openclaw gateway stop 2>/dev/null || pkill -f openclaw-gateway 2>/dev/null
echo "=== Stopping claude agents ==="
pkill -f "claude --print" 2>/dev/null
echo "All stopped"
