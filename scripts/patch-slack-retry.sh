#!/bin/sh
# Patch OpenClaw Slack WebClient to use strict retry config (retries: 0)
# Prevents duplicate messages per https://github.com/openclaw/openclaw/issues/1481
# OpenClaw doesn't expose webClient.retryConfig in config, so we patch the dist.

set -e
OC_DIST="${1:-/usr/local/lib/node_modules/openclaw/dist}"
[ -d "$OC_DIST" ] || { echo "OpenClaw dist not found: $OC_DIST"; exit 1; }

patched=0
for p in $(find "$OC_DIST" -maxdepth 2 -name "*.js" -type f -exec grep -l "SLACK_DEFAULT_RETRY_OPTIONS" {} \; 2>/dev/null); do
  sed -i.bak 's/retries: 2,/retries: 0,/' "$p" && sed -i.bak 's/maxTimeout: 3e3/maxTimeout: 1e3/' "$p"
  rm -f "${p}.bak"
  echo "Patched: $p"
  patched=$((patched + 1))
done

[ "$patched" -gt 0 ] || { echo "No Slack retry config found to patch"; exit 1; }
echo "Patched $patched file(s). Slack WebClient now uses retries: 0, maxTimeout: 1s."
