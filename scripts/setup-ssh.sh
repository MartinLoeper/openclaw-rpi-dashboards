#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${1:-openclaw-rpi5.local}"
TARGET_USER="nixos"
KEY_FILE="${2:-$(dirname "$0")/../id_ed25519_rpi5}"

echo "Resolving ${TARGET_HOST}..."
if ! getent hosts "${TARGET_HOST}" >/dev/null 2>&1; then
  echo "Error: Could not resolve ${TARGET_HOST}"
  echo "Make sure the device is powered on and Avahi (mDNS) is working."
  exit 1
fi

if [ -f "${KEY_FILE}" ]; then
  echo "SSH key already exists at ${KEY_FILE}"
else
  echo "Generating SSH key pair..."
  ssh-keygen -t ed25519 -f "${KEY_FILE}" -N "" -C "openclaw-rpi-deploy"
fi

echo "Copying public key to ${TARGET_USER}@${TARGET_HOST}..."
echo "You will be prompted for the password."
ssh-copy-id -i "${KEY_FILE}.pub" -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${TARGET_HOST}"

echo ""
echo "Setup complete. You can now deploy with:"
echo "  ./scripts/deploy.sh"
