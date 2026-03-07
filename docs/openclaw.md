# OpenClaw Gateway Integration

## Overview

The OpenClaw gateway is integrated via the [nix-openclaw](https://github.com/MartinLoeper/nix-openclaw) flake, which provides a NixOS module and package overlay for aarch64-linux.

## Flake Integration

The `nix-openclaw` flake is added as a flake input and wired into `commonModules`, so the gateway runs on both the base CLI configuration and the kiosk specialisation.

```nix
# flake.nix (simplified)
inputs.nix-openclaw.url = "github:MartinLoeper/nix-openclaw/main";

commonModules = [
  nix-openclaw.nixosModules.openclaw-gateway
  {
    nixpkgs.overlays = [ nix-openclaw.overlays.default ];
    services.openclaw-gateway.enable = true;
  }
];
```

## Service Details

| Property | Value |
|----------|-------|
| Service name | `openclaw-gateway.service` |
| Port | `18789` |
| Config file | `/etc/openclaw/openclaw.json` |
| State directory | `/var/lib/openclaw` |
| System user | `openclaw` |
| System group | `openclaw` |
| Restart policy | `always` |

## Configuration

### Basic

The NixOS module handles service setup automatically. Default settings (port 18789, user `openclaw`, state dir `/var/lib/openclaw`) work out of the box.

### API Keys and Secrets

Use `environmentFiles` to inject secrets without putting them in the Nix store:

```nix
services.openclaw-gateway = {
  enable = true;
  environmentFiles = [ "/run/secrets/openclaw.env" ];
};
```

The env file can contain API keys and other sensitive configuration:

```
ANTHROPIC_API_KEY=sk-ant-...
```

### Channels

Channel configuration is managed through the gateway's config file at `/etc/openclaw/openclaw.json`. Refer to the [OpenClaw documentation](https://github.com/MartinLoeper/nix-openclaw) for available channel options.

## Kiosk Connection

The kiosk specialisation points Chromium at `http://localhost:18789`, which is the gateway's dashboard interface. When kiosk mode is active, the gateway dashboard is displayed fullscreen on the attached display.

## Useful Commands

```sh
# Check service status
ssh root@openclaw-rpi5.local systemctl status openclaw-gateway

# View logs
ssh root@openclaw-rpi5.local journalctl -u openclaw-gateway -f

# Test the dashboard endpoint
ssh root@openclaw-rpi5.local curl -s http://localhost:18789
```
