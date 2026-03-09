#!/usr/bin/env bash
# Start an SFTP drop server for the agent to send files to your laptop.
#
# Usage: ./scripts/file-drop.sh [port]
#
# Starts a containerized SFTP server on the given port (default: 2222).
# Files land in /tmp/openclaw-drop on your machine.
# Prints connection details to hand to the agent.
set -euo pipefail

PORT="${1:-2222}"
CONTAINER_NAME="openclaw-drop"
DROP_DIR="/tmp/openclaw-drop"
USER="drop"
PASS="$(openssl rand -hex 4)"

# Detect local IP reachable from the Pi
LOCAL_IP="$(ip -4 route get 1 | grep -oP 'src \K\S+')"

mkdir -p "${DROP_DIR}"

# Stop any existing instance
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:22" \
  -v "${DROP_DIR}:/home/${USER}/upload" \
  atmoz/sftp "${USER}:${PASS}:1000"

echo ""
echo "  OpenClaw File Drop"
echo "  ==================="
echo ""
echo "  Local directory: ${DROP_DIR}"
echo "  Container:       ${CONTAINER_NAME}"
echo ""
echo "  --- Hand these to the agent ---"
echo ""
echo "  SFTP host:     ${LOCAL_IP}"
echo "  SFTP port:     ${PORT}"
echo "  SFTP user:     ${USER}"
echo "  SFTP password: ${PASS}"
echo "  Upload path:   /upload/"
echo ""
echo "  Agent command:  sshpass -p '${PASS}' sftp -P ${PORT} -o StrictHostKeyChecking=no ${USER}@${LOCAL_IP}:/upload/"
echo ""
echo "  Stop with: docker rm -f ${CONTAINER_NAME}"
echo ""
