#!/usr/bin/env bash
# Forward ClawPi ports from the dev VM to the host via SSH.
# Run this on the HOST machine (not inside the VM).
#
# Usage: ./scripts/forward-vm.sh [vm-ip]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_IP="${1:-192.168.122.24}"
VM_USER="dev"
SSH_KEY="$HOME/repos/mloeper/glinq-os/vms/nixos-dev/ssh_key"

echo "Forwarding ClawPi ports from VM ($VM_IP) to localhost..."
echo "  localhost:18789 → openclaw-gateway"
echo "  localhost:3100  → clawpi landing page"
echo "  localhost:9222  → chromium CDP"
echo ""
echo "Press Ctrl+C to stop."

exec ssh -N \
  -i "$SSH_KEY" \
  -L 18789:localhost:18789 \
  -L 3100:localhost:3100 \
  -L 9222:localhost:9222 \
  "$VM_USER@$VM_IP"
