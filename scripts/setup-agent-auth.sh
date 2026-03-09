#!/usr/bin/env bash
# Configure the Anthropic API key for the OpenClaw gateway agent.
#
# Usage: ./scripts/setup-agent-auth.sh [host]
#
# The script prompts for an API key (from `claude setup-token` or the Anthropic console)
# and writes it to the agent auth profile on the Pi.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOST="${1:-openclaw-rpi5.local}"
TARGET_USER="nixos"
KEY_FILE="${SCRIPT_DIR}/../id_ed25519_rpi5"

if [ ! -f "${KEY_FILE}" ]; then
  echo "Error: SSH key not found at ${KEY_FILE}"
  echo "Run ./scripts/setup-ssh.sh first to set up SSH authentication."
  exit 1
fi

SSH_OPTS="-i ${KEY_FILE} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

echo "Enter Anthropic API key (from 'claude setup-token' or console.anthropic.com):"
read -rs API_KEY

if [ -z "${API_KEY}" ]; then
  echo "Error: No API key provided."
  exit 1
fi

AUTH_JSON=$(cat <<EOF
{"version":1,"profiles":{"anthropic:default":{"type":"api_key","provider":"anthropic","key":"${API_KEY}"}}}
EOF
)

# Write to both the main agent dir and the default (global fallback) agent dir.
# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" "
  for dir in /var/lib/kiosk/.openclaw/agents/main/agent /var/lib/kiosk/.openclaw/agents/default/agent; do
    sudo mkdir -p \"\$dir\"
    echo '${AUTH_JSON}' | sudo tee \"\$dir/auth-profiles.json\" > /dev/null
    sudo chmod 600 \"\$dir/auth-profiles.json\"
  done
  sudo chown -R kiosk:kiosk /var/lib/kiosk/.openclaw/agents
"

echo ""
echo "  API key configured on ${TARGET_HOST}."
echo "  Restarting openclaw-gateway..."

# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) systemctl --user restart openclaw-gateway"

echo "  Done."
