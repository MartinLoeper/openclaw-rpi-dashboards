# Security Considerations

## Kiosk User Isolation

The `kiosk` user runs the OpenClaw gateway and the agent. It is deliberately **not an admin**:

- System user (`isSystemUser = true`)
- Groups: `kiosk`, `audio`, `video` only
- Not in `wheel` — no sudo access
- Home: `/var/lib/kiosk` (not a regular home directory)
- Shell: `bash` (needed for agent command execution)

This means the agent cannot escalate privileges, modify system configuration, install packages, or access other users' files.

## Credential Isolation

Any credentials the agent should not directly access (e.g. Gmail App Passwords, API keys for external services) must run under a **separate system user**, exposed to the kiosk user only via a localhost API or socket. If credentials were stored in files readable by the kiosk user, the agent could read them directly.

Example: an email relay service runs as `mailrelay` user with the Gmail password, and exposes a restricted HTTP endpoint on localhost that the agent can call to send emails — but only to the user's own address.

## Gateway Auth

The gateway runs in `local` mode (loopback only) and requires a token for WebSocket connections. The token is auto-generated at first boot and stored in `~/.openclaw/gateway-token.env`. It is not exposed to the network.

## Agent API Key

The Anthropic API key is stored in `~/.openclaw/agents/main/agent/auth-profiles.json`. This file is readable by the kiosk user (necessary for the gateway to use it). This is an accepted trade-off — the agent needs the key to function, and the kiosk user is already isolated from the rest of the system.

## Network Exposure

- Gateway listens on `127.0.0.1:18789` only (not externally accessible)
- CDP (Chrome DevTools Protocol) on `127.0.0.1:9222` only
- Browser control on `127.0.0.1:18791` only
- SSH is the only externally accessible service
- Avahi/mDNS advertises the hostname for local network discovery
