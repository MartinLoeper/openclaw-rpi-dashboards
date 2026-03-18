#!/usr/bin/env bash
# Deploy NixOS to the Raspberry Pi.
#
# Usage: ./scripts/deploy.sh [host] [nixos-rebuild args...]
#
# Set REMOTE_CACHE to a Hetzner ARM builder IP to fetch pre-built packages:
#   REMOTE_CACHE=195.201.40.121 ./scripts/deploy.sh 192.168.0.64 --specialisation kiosk
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOST="${1:-openclaw-rpi5.local}"
TARGET_USER="nixos"
FLAKE_ATTR="${FLAKE_ATTR:-rpi5}"
BOARD="${FLAKE_ATTR%%-*}"  # rpi4-telegram → rpi4
KEY_FILE="${KEY_FILE:-${SCRIPT_DIR}/../id_ed25519_${BOARD}}"
REMOTE_CACHE="${REMOTE_CACHE:-}"
REMOTE_CACHE_KEY="${REMOTE_CACHE_KEY:-${HOME}/.ssh/id_ed25519}"

if [ ! -f "${KEY_FILE}" ]; then
  echo "Error: SSH key not found at ${KEY_FILE}"
  echo "Run ./scripts/setup-ssh.sh first to set up SSH authentication."
  exit 1
fi

export NIX_SSHOPTS="-i ${KEY_FILE} -o StrictHostKeyChecking=accept-new"

echo "Resolving ${TARGET_HOST}..."
if ! getent hosts "${TARGET_HOST}" > /dev/null 2>&1; then
  echo "Error: Could not resolve ${TARGET_HOST}"
  echo "Make sure the device is powered on and Avahi (mDNS) is working."
  exit 1
fi

echo "Deploying NixOS to ${TARGET_USER}@${TARGET_HOST}..."
echo "  Flake: .#${FLAKE_ATTR}"
echo ""

if [ -n "${REMOTE_CACHE}" ]; then
  echo "  Remote cache: root@${REMOTE_CACHE}"
  echo "Copying build closure from remote cache..."
  REMOTE_PATH="$(ssh -i "${REMOTE_CACHE_KEY}" -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes "root@${REMOTE_CACHE}" readlink -f clawpi/result)"
  NIX_SSHOPTS="-i ${REMOTE_CACHE_KEY} -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes" \
    nix copy --from "ssh://root@${REMOTE_CACHE}" "${REMOTE_PATH}" --no-check-sigs
  echo "Done. Closure available locally."
fi

nixos-rebuild switch \
  --flake ".#${FLAKE_ATTR}" \
  --target-host "${TARGET_USER}@${TARGET_HOST}" \
  --sudo \
  -L --show-trace \
  "${@:2}"

echo ""
echo "Deploy complete. Verifying mDNS reachability..."
if getent hosts "${TARGET_HOST}" > /dev/null 2>&1; then
  echo "Device reachable at ${TARGET_HOST} ($(getent hosts "${TARGET_HOST}" | awk '{print $1}'))"
else
  echo "Warning: ${TARGET_HOST} not reachable via mDNS after deploy. The device may still be rebooting."
fi
