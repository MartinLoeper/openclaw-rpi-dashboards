#!/usr/bin/env bash
# Provision a Matrix access token on the Pi.
#
# Usage: ./scripts/provision-matrix.sh [host]
#
# This script:
# 1. Prompts for the Matrix access token
# 2. Writes it to /var/lib/clawpi/matrix-access-token on the Pi
# 3. Prints the next steps (enable in NixOS config, deploy)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOST="${1:-openclaw-rpi5.local}"
KEY_FILE="${SCRIPT_DIR}/../id_ed25519_rpi5"
TOKEN_PATH="/var/lib/clawpi/matrix-access-token"

if [ ! -f "${KEY_FILE}" ]; then
  echo "Error: SSH key not found at ${KEY_FILE}"
  echo "Run ./scripts/setup-ssh.sh first."
  exit 1
fi

SSH="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=accept-new nixos@${TARGET_HOST}"

echo "=== ClawPi Matrix Channel Provisioning ==="
echo ""
echo "You need a Matrix account and an access token."
echo ""
echo "To get an access token, use the Matrix login API:"
echo ""
echo '  curl -s -X POST https://matrix.example.org/_matrix/client/v3/login \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"type":"m.login.password","user":"@bot:example.org","password":"..."}'"'"' \'
echo '    | jq -r .access_token'
echo ""
read -rp "Paste your Matrix access token: " ACCESS_TOKEN

if [ -z "${ACCESS_TOKEN}" ]; then
  echo "Error: empty token"
  exit 1
fi

echo ""
echo "Writing access token to ${TARGET_HOST}:${TOKEN_PATH}..."
${SSH} "sudo mkdir -p /var/lib/clawpi && echo -n '${ACCESS_TOKEN}' | sudo tee ${TOKEN_PATH} > /dev/null && sudo chown kiosk:kiosk ${TOKEN_PATH} && sudo chmod 600 ${TOKEN_PATH}"
echo "Done."

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Enable the Matrix channel in your NixOS config:"
echo ""
echo '   services.clawpi.matrix = {'
echo '     enable = true;'
echo '     homeserver = "https://matrix.example.org";'
echo '     encryption = true;  # recommended'
echo '     dm.policy = "pairing";'
echo '   };'
echo ""
echo "2. Deploy: ./scripts/deploy.sh ${TARGET_HOST} --specialisation kiosk"
echo ""
echo "3. Verify: ssh nixos@${TARGET_HOST} sudo tail -50 /tmp/openclaw/openclaw-gateway.log"
echo ""
echo "4. Send a DM to the bot on Matrix. With the default dm.policy (\"pairing\"),"
echo "   the bot will reply with a pairing code. Approve it in the gateway."
