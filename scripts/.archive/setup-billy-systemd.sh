#!/bin/bash
# Setup Billy VM with systemd + auto-restart
set -euo pipefail

BILLY_VM="89.167.64.183"
BILLY_USER="root"

echo "Setting up Billy VM systemd service..."

# Create systemd service file
cat > /tmp/billy-openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Gateway for Billy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/Users/fonsecabc/.openclaw
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/gateway/index.js --port 18790
Restart=always
RestartSec=10
StandardOutput=append:/var/log/openclaw-billy.log
StandardError=append:/var/log/openclaw-billy-error.log

# Environment
Environment="NODE_ENV=production"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

# Copy to Billy VM
scp -o StrictHostKeyChecking=no /tmp/billy-openclaw.service "${BILLY_USER}@${BILLY_VM}:/etc/systemd/system/"

# Enable and start service
ssh -o StrictHostKeyChecking=no "${BILLY_USER}@${BILLY_VM}" << 'REMOTE'
  # Reload systemd
  systemctl daemon-reload
  
  # Enable service (starts on boot)
  systemctl enable billy-openclaw.service
  
  # Start service now
  systemctl start billy-openclaw.service
  
  # Check status
  sleep 3
  systemctl status billy-openclaw.service --no-pager
  
  echo ""
  echo "✅ Billy systemd service installed and started"
  echo ""
  echo "Commands:"
  echo "  systemctl status billy-openclaw"
  echo "  systemctl restart billy-openclaw"
  echo "  systemctl stop billy-openclaw"
  echo "  journalctl -u billy-openclaw -f"
REMOTE

echo ""
echo "✅ Setup complete"
