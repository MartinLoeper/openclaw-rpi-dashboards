#!/usr/bin/env bash
# Start a restricted email relay on your laptop for the OpenClaw agent.
#
# Usage: ./scripts/email-relay.sh <your-email> [port]
#
# Runs a tiny HTTP→SMTP relay in Docker that:
#   - Only accepts POST /send with { "subject": "...", "body": "..." }
#   - Only sends to YOUR email address (hardcoded at startup)
#   - Requires Bearer token authentication on every request
#   - Relays via Gmail SMTP using an App Password
#
# Gmail credentials are passed via a temporary env file (not CLI args),
# so they don't appear in `docker inspect` or process listings.
#
# Requires: Docker, a Gmail App Password (https://myaccount.google.com/apppasswords)
set -euo pipefail

RECIPIENT="${1:?Usage: $0 <your-email> [port]}"
PORT="${2:-8025}"
CONTAINER_NAME="openclaw-email-relay"
LOCAL_IP="$(ip -4 route get 1 | grep -oP 'src \K\S+')"

echo "Enter your Gmail address (sender) [${RECIPIENT}]:"
read -r GMAIL_USER
GMAIL_USER="${GMAIL_USER:-${RECIPIENT}}"
echo "Enter Gmail App Password (create one at https://myaccount.google.com/apppasswords):"
read -rs GMAIL_PASS
echo ""

# Generate a random bearer token for HTTP auth
BEARER_TOKEN="$(openssl rand -hex 16)"

docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Write credentials to a temp env file (deleted after container starts)
ENV_FILE="$(mktemp)"
cat > "${ENV_FILE}" <<EOF
GMAIL_USER=${GMAIL_USER}
GMAIL_PASS=${GMAIL_PASS}
RECIPIENT=${RECIPIENT}
BEARER_TOKEN=${BEARER_TOKEN}
EOF
chmod 600 "${ENV_FILE}"

# Create a minimal relay server using Python inside the container
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:8025" \
  --env-file "${ENV_FILE}" \
  python:3.12-slim \
  python3 -c "
import http.server, json, smtplib, os, base64, mimetypes
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders

GMAIL_USER = os.environ['GMAIL_USER']
GMAIL_PASS = os.environ['GMAIL_PASS']
RECIPIENT = os.environ['RECIPIENT']
BEARER_TOKEN = os.environ['BEARER_TOKEN']

class Handler(http.server.BaseHTTPRequestHandler):
    def _check_auth(self):
        auth = self.headers.get('Authorization', '')
        if auth != f'Bearer {BEARER_TOKEN}':
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{\"error\":\"unauthorized\"}')
            return False
        return True
    def do_POST(self):
        if not self._check_auth():
            return
        if self.path != '/send':
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get('Content-Length', 0))
        data = json.loads(self.rfile.read(length))
        subject = data.get('subject', 'OpenClaw notification')
        body = data.get('body', '')
        attachments = data.get('attachments', [])
        if attachments:
            msg = MIMEMultipart()
            msg.attach(MIMEText(body))
            for att in attachments:
                filename = att.get('filename', 'attachment')
                file_data = base64.b64decode(att['data_base64'])
                mime, _ = mimetypes.guess_type(filename)
                maintype, subtype = (mime or 'application/octet-stream').split('/', 1)
                part = MIMEBase(maintype, subtype)
                part.set_payload(file_data)
                encoders.encode_base64(part)
                part.add_header('Content-Disposition', 'attachment', filename=filename)
                msg.attach(part)
        else:
            msg = MIMEText(body)
        msg['From'] = GMAIL_USER
        msg['To'] = RECIPIENT
        msg['Subject'] = subject
        try:
            with smtplib.SMTP('smtp.gmail.com', 587) as s:
                s.starttls()
                s.login(GMAIL_USER, GMAIL_PASS)
                s.send_message(msg)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{\"status\":\"sent\"}')
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())
    def do_GET(self):
        if not self._check_auth():
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{\"service\":\"openclaw-email-relay\",\"recipient\":\"' + RECIPIENT.encode() + b'\"}')

http.server.HTTPServer(('0.0.0.0', 8025), Handler).serve_forever()
"

# Remove the env file now that the container has read it
rm -f "${ENV_FILE}"

cat <<BANNER

  OpenClaw Email Relay
  ====================

  Recipient:  ${RECIPIENT} (only address allowed)
  Container:  ${CONTAINER_NAME}

  --- Hand these to the agent ---

  Relay URL:    http://${LOCAL_IP}:${PORT}/send
  Bearer Token: ${BEARER_TOKEN}
  Method:       POST
  Headers:      Authorization: Bearer ${BEARER_TOKEN}
                Content-Type: application/json
  Body:         {"subject": "...", "body": "...", "attachments": [...]}

  Text-only example:
    curl -X POST http://${LOCAL_IP}:${PORT}/send \\
      -H 'Authorization: Bearer ${BEARER_TOKEN}' \\
      -H 'Content-Type: application/json' \\
      -d '{"subject":"Hello","body":"Test from OpenClaw"}'

  With attachment:
    curl -X POST http://${LOCAL_IP}:${PORT}/send \\
      -H 'Authorization: Bearer ${BEARER_TOKEN}' \\
      -H 'Content-Type: application/json' \\
      -d '{"subject":"Screenshot","body":"See attached",
           "attachments":[{"filename":"shot.png",
           "data_base64":"'\$(base64 -w0 /tmp/shot.png)'"}]}'

  Restricted email relay for the OpenClaw agent. Sends emails via Gmail
  to a single hardcoded recipient. Supports text and file attachments.
  Authenticate every request with the Bearer token above.

  ---

  Stop with: docker rm -f ${CONTAINER_NAME}

BANNER
