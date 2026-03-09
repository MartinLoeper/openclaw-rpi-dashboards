#!/usr/bin/env bash
# Forward the OpenClaw gateway port from the Pi to localhost.
#
# Usage: ./scripts/gateway-forward.sh [host]
#
# Opens an SSH tunnel forwarding port 18789 and prints the URL to open.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOST="${1:-openclaw-rpi5.local}"
TARGET_USER="nixos"
KEY_FILE="${SCRIPT_DIR}/../id_ed25519_rpi5"
PORT=18789

if [ ! -f "${KEY_FILE}" ]; then
  echo "Error: SSH key not found at ${KEY_FILE}"
  echo "Run ./scripts/setup-ssh.sh first to set up SSH authentication."
  exit 1
fi

TOKEN=$(ssh -i "${KEY_FILE}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "${TARGET_USER}@${TARGET_HOST}" \
  "sudo cat /var/lib/kiosk/.openclaw/gateway-token.env 2>/dev/null | sed 's/^OPENCLAW_GATEWAY_TOKEN=//'")

echo ""
echo "  OpenClaw Gateway Forward"
echo "  ========================"
echo ""
echo "  Forwarding ${TARGET_HOST}:${PORT} -> localhost:${PORT}"
echo ""
echo "  Gateway:   http://localhost:${PORT}"
echo "  Token:     ${TOKEN}"
echo "  PinchChat: http://localhost:3000  (if running)"
echo ""
echo "  Press Ctrl+C to stop."
echo ""

exec ssh -i "${KEY_FILE}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  -L "${PORT}:127.0.0.1:${PORT}" -N "${TARGET_USER}@${TARGET_HOST}"
