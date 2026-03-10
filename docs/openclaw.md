# OpenClaw Gateway Integration

## Overview

The OpenClaw gateway runs as a Home Manager user service for the `kiosk` user, managed via the [nix-openclaw](https://github.com/MartinLoeper/nix-openclaw) flake's Home Manager module (`programs.openclaw`).

## Flake Integration

The `nix-openclaw` flake provides:
- **Overlay** — builds the `openclaw-gateway` package (with a pnpm dependency fix)
- **Home Manager module** — manages config, systemd user service, and workspace for the `kiosk` user

```nix
# flake.nix (simplified)
inputs.nix-openclaw.url = "github:MartinLoeper/nix-openclaw/main";
inputs.home-manager.url = "github:nix-community/home-manager";

home-manager.users.kiosk = {
  imports = [ nix-openclaw.homeManagerModules.openclaw ];
  programs.openclaw = {
    enable = true;
    config.gateway.mode = "local";
  };
};
```

## Service Details

| Property | Value |
|----------|-------|
| Service name | `openclaw-gateway.service` (systemd user service, kiosk user) |
| Port | `18789` |
| Config | `~/.openclaw/openclaw.json` (managed by Home Manager) |
| State directory | `/var/lib/kiosk/.openclaw` |
| User | `kiosk` (system user) |
| Gateway mode | `local` (loopback only) |

## Authentication

A random gateway token is generated on first boot by a companion user service (`openclaw-gateway-token.service`). The token is stored at `~/.openclaw/gateway-token.env` and loaded via `EnvironmentFile`.

### Retrieving the Token

```sh
./scripts/gateway-token.sh [host]
```

Defaults to `openclaw-rpi5.local`. Pass an IP to override:

```sh
./scripts/gateway-token.sh 192.168.0.64
```

The script prints the token and a ready-to-use dashboard URL with the token parameter.

## Agent Auth (API Keys)

The gateway needs at least one LLM provider API key. Configure with:

```sh
./scripts/setup-agent-auth.sh [host]
```

The script prompts for API keys from supported providers. Leave a field empty to skip that provider:

- **Anthropic** — from `claude setup-token` or [console.anthropic.com](https://console.anthropic.com)
- **OpenRouter** — from [openrouter.ai/keys](https://openrouter.ai/keys) (provides access to many models including Claude, GPT-4, Gemini, etc.)

At least one provider is required. The auth profile is stored at `~/.openclaw/agents/main/agent/auth-profiles.json`.

## Kiosk User Design Decisions

The `kiosk` user is a system user with:

- **Bash shell** — the agent needs to execute commands (SFTP transfers, system tools, etc.). A `nologin` shell would prevent all command execution.
- **`sshpass`** in system packages — enables the agent to do non-interactive SFTP/SCP file transfers to the user's workstation.
- **Linger enabled** — ensures the user's systemd services (gateway, token generation) start at boot without requiring a login session.

## Kiosk Connection

The kiosk specialisation runs Cage + Chromium pointing at `http://localhost:18789`. The Cage service waits for PipeWire before launching Chromium so that audio is available.

## Useful Commands

```sh
# Check service status (run as kiosk user)
ssh nixos@openclaw-rpi5.local sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) systemctl --user status openclaw-gateway

# View logs
ssh nixos@openclaw-rpi5.local cat /tmp/openclaw/openclaw-gateway.log

# Retrieve the gateway token
./scripts/gateway-token.sh
```

## Agent Tools (laptop-side)

These scripts run Docker containers on your workstation to give the agent secure, authenticated access to services it can't run on the Pi itself. Each generates random credentials at startup and prints connection details to hand to the agent.

### File Drop (SFTP)

**Script:** `./scripts/file-drop.sh [port]`

Starts a containerized SFTP server (`atmoz/sftp`) so the agent can send files from the Pi to your laptop — screenshots, logs, recordings, etc. Files land in `/tmp/openclaw-drop`.

- **Port:** `2222` (default, configurable)
- **Auth:** random password generated at startup (printed in output)
- **Agent usage:** `sshpass -p '<password>' sftp -P 2222 -o StrictHostKeyChecking=no drop@<laptop-ip>:/upload/`

The agent authenticates with the one-time password. No persistent credentials are stored on the Pi.

### Email Relay (Gmail SMTP)

**Script:** `./scripts/email-relay.sh <recipient-email> [port]`

Starts a restricted HTTP→Gmail SMTP relay so the agent can email the user — dashboard summaries, screenshots, alerts, etc.

- **Port:** `8025` (default, configurable)
- **Auth:** random Bearer token generated at startup (printed in output)
- **Recipient restriction:** only the email address given at startup is allowed — the agent cannot email anyone else
- **Attachments:** supported via base64-encoded JSON (`data_base64` field)
- **Gmail credentials:** prompted interactively, passed via a temp env file (deleted after container starts, not visible in `docker inspect`)
- **Agent usage:**
  ```sh
  curl -X POST http://<laptop-ip>:8025/send \
    -H 'Authorization: Bearer <token>' \
    -H 'Content-Type: application/json' \
    -d '{"subject":"Hello","body":"From OpenClaw","attachments":[{"filename":"shot.png","data_base64":"..."}]}'
  ```

Both tools are designed so the agent never handles raw credentials — it only receives the generated one-time tokens/passwords needed to use the service.
