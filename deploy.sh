#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${1:-openclaw-rpi5.local}"
TARGET_USER="root"
FLAKE_ATTR="rpi5"

echo "Deploying NixOS to ${TARGET_USER}@${TARGET_HOST}..."
echo "  Flake: .#${FLAKE_ATTR}"
echo ""

nixos-rebuild switch \
  --flake ".#${FLAKE_ATTR}" \
  --target-host "${TARGET_USER}@${TARGET_HOST}" \
  --use-remote-sudo \
  -L --show-trace \
  "${@:2}"
