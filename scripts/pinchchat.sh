#!/usr/bin/env bash
# Start PinchChat web UI for interacting with the OpenClaw gateway.
#
# Prerequisites: Docker, SSH tunnel to the gateway (./scripts/gateway-forward.sh)
#
# Usage: ./scripts/pinchchat.sh [port]
set -euo pipefail

PORT="${1:-3000}"
CONTAINER_NAME="pinchchat"
URL="http://localhost:${PORT}"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "PinchChat is already running at ${URL}"
else
  # Remove stopped container if it exists
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

  echo "Starting PinchChat on port ${PORT}..."
  docker run -d --name "${CONTAINER_NAME}" -p "${PORT}:80" \
    -e VITE_GATEWAY_WS_URL=ws://localhost:18789 \
    ghcr.io/marlburrow/pinchchat:latest > /dev/null

  echo "PinchChat running at ${URL}"
fi

echo ""
echo "Gateway token:"
"$(dirname "$0")/gateway-token.sh" 2>/dev/null || echo "(could not retrieve token — is the SSH tunnel up?)"

echo ""
read -rp "Open in browser? [Y/n] " answer
answer="${answer:-y}"
if [[ "${answer}" =~ ^[Yy]$ ]]; then
  xdg-open "${URL}" 2>/dev/null || open "${URL}" 2>/dev/null || echo "Could not open browser. Visit ${URL} manually."
fi
