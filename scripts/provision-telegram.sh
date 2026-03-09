#!/usr/bin/env bash
# Provision a Telegram bot token on the Pi.
#
# Usage: ./scripts/provision-telegram.sh [host]
#
# This script:
# 1. Prompts for the bot token (from @BotFather)
# 2. Writes it to /var/lib/clawpi/telegram-bot-token on the Pi
# 3. Prints the next steps (get chat ID, enable in NixOS config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOST="${1:-openclaw-rpi5.local}"
KEY_FILE="${SCRIPT_DIR}/../id_ed25519_rpi5"
TOKEN_PATH="/var/lib/clawpi/telegram-bot-token"

if [ ! -f "${KEY_FILE}" ]; then
  echo "Error: SSH key not found at ${KEY_FILE}"
  echo "Run ./scripts/setup-ssh.sh first."
  exit 1
fi

SSH="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=accept-new nixos@${TARGET_HOST}"

echo "=== ClawPi Telegram Bot Provisioning ==="
echo ""
echo "Create a bot via @BotFather on Telegram first."
echo "Send /newbot, follow the prompts, and copy the token."
echo ""
read -rp "Paste your bot token: " BOT_TOKEN

if [ -z "${BOT_TOKEN}" ]; then
  echo "Error: empty token"
  exit 1
fi

echo ""
echo "Writing token to ${TARGET_HOST}:${TOKEN_PATH}..."
${SSH} "sudo mkdir -p /var/lib/clawpi && echo -n '${BOT_TOKEN}' | sudo tee ${TOKEN_PATH} > /dev/null && sudo chmod 600 ${TOKEN_PATH}"
echo "Done."

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Get your Telegram chat ID:"
echo "   Send any message to your bot, then open:"
echo "   https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
echo "   Find your chat.id in the JSON response."
echo ""
echo "2. Enable the Telegram bridge in your NixOS config (modules/clawpi.nix is already imported):"
echo ""
echo '   services.clawpi.telegram = {'
echo '     enable = true;'
echo "     tokenFile = \"${TOKEN_PATH}\";"
echo '     allowedChatIds = [ <your-chat-id> ];'
echo '   };'
echo ""
echo "3. Deploy: ./scripts/deploy.sh ${TARGET_HOST} --specialisation kiosk"
echo ""
echo "4. Check the service: ssh nixos@${TARGET_HOST} sudo systemctl status clawpi-telegram"
