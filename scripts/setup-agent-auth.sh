#!/usr/bin/env bash
# Configure LLM provider API keys for the OpenClaw gateway agent.
#
# Usage: ./scripts/setup-agent-auth.sh [host]
#
# Prompts for Anthropic and OpenRouter API keys. Leave blank to skip a provider.
# Writes the auth profile to the Pi and restarts the gateway.
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
echo "(leave empty to skip)"
read -rs ANTHROPIC_KEY
echo ""

echo "Enter OpenRouter API key (from openrouter.ai/keys):"
echo "(leave empty to skip)"
read -rs OPENROUTER_KEY
echo ""

if [ -z "${ANTHROPIC_KEY}" ] && [ -z "${OPENROUTER_KEY}" ]; then
  echo "Error: No API keys provided. At least one provider is required."
  exit 1
fi

# Build the profiles JSON dynamically
PROFILES=""
if [ -n "${ANTHROPIC_KEY}" ]; then
  PROFILES="\"anthropic:default\":{\"type\":\"api_key\",\"provider\":\"anthropic\",\"key\":\"${ANTHROPIC_KEY}\"}"
fi
if [ -n "${OPENROUTER_KEY}" ]; then
  if [ -n "${PROFILES}" ]; then
    PROFILES="${PROFILES},"
  fi
  PROFILES="${PROFILES}\"openrouter:default\":{\"type\":\"api_key\",\"provider\":\"openrouter\",\"key\":\"${OPENROUTER_KEY}\"}"
fi

AUTH_JSON="{\"version\":1,\"profiles\":{${PROFILES}}}"

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

CONFIGURED=""
[ -n "${ANTHROPIC_KEY}" ] && CONFIGURED="Anthropic"
[ -n "${OPENROUTER_KEY}" ] && CONFIGURED="${CONFIGURED:+$CONFIGURED + }OpenRouter"

echo ""
echo "  Configured: ${CONFIGURED}"
echo "  Restarting openclaw-gateway..."

# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_USER}@${TARGET_HOST}" \
  "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) systemctl --user restart openclaw-gateway"

echo "  Done."
