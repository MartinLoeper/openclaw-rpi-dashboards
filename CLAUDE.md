# OpenClaw RPi Dashboards

## Deployment

- **Target device:** Raspberry Pi 5 reachable at `openclaw-rpi5.local` (mDNS)
- **Deploy command:** `./scripts/deploy.sh [host] --specialisation kiosk`
- **Default specialisation:** `kiosk` (always deploy with `--specialisation kiosk` unless told otherwise)
- **SSH user:** `nixos`
- **SSH key:** `id_ed25519_rpi5` in repo root (gitignored), set up via `./scripts/setup-ssh.sh`

### Remote build cache

When the user asks to deploy or build an SD image but doesn't mention a remote cache, **ask** whether to use a Hetzner ARM builder as a remote build cache (see `.claude/skills/hetzner-builder.md`). For deploys, prepend `REMOTE_CACHE=<server-ip>` to the deploy command. For SD image builds, build on Hetzner first, then `nix copy` the result locally. This avoids slow local cross-compilation by fetching pre-built packages from the server.

### "Deploy in background"

When the user says "deploy in background", run the deploy script as a background task:

```
./scripts/deploy.sh  (with run_in_background: true, timeout: 600000)
```

The deploy builds the NixOS closure locally (cross-compiled for aarch64) and copies it to the Pi over SSH. This can take several minutes. While it runs:

1. Continue working on other tasks — don't block on the deploy.
2. You will be notified when the background task completes.
3. When it finishes, check the output for errors and report the result to the user.
4. If deploying a specialisation, append `--specialisation <name>` to the deploy command (no `--` separator).

## Nix Build Rules

- **Always** pass `--show-trace -L` (or `--print-build-logs`) to `nix build` commands so build progress is visible.
- **Never** pipe build output through `tail`, `head`, or other filters that buffer output — this hides progress and makes long builds appear stuck.
- When running builds in background tasks, the full output must stream to the task output file unfiltered.

## Architecture

- **NixOS flake** with two configurations sharing `commonModules`:
  - `rpi5` — for live deploys via `nixos-rebuild`
  - `rpi5-installer` — for building flashable SD images
- **Kiosk specialisation** — Cage + Chromium kiosk mode, activated at runtime or via deploy (see `docs/canvas.md`)
- Base system is CLI-only; graphical stack is opt-in via the specialisation
- **Known issue:** `nixos-rebuild --specialisation kiosk` doesn't always activate the specialisation. After deploying, verify and manually activate if needed:
  ```sh
  # Check which system is active (base vs kiosk)
  readlink /run/current-system
  # If cage-tty1.service is not running, the kiosk spec wasn't activated:
  ssh nixos@<host> sudo systemctl status cage-tty1
  # Manually activate the kiosk specialisation (use -f to resolve the full absolute path):
  ssh nixos@<host> "sudo \$(readlink -f /nix/var/nix/profiles/system)/specialisation/kiosk/bin/switch-to-configuration switch"
  # Then restart cage since switch-to-configuration skips it:
  ssh nixos@<host> sudo systemctl restart cage-tty1
  ```
- **File structure:**
  - `modules/base.nix` — system config (boot, users, networking, PipeWire, Avahi, SSH)
  - `modules/kiosk.nix` — kiosk specialisation (Cage + Chromium, PipeWire wait)
  - `home/openclaw.nix` — Home Manager config for OpenClaw gateway (kiosk user)
  - `overlays/openclaw-gateway-fix.nix` — pnpm dependency fix for openclaw-gateway

## OpenClaw Gateway

- **Service:** `openclaw-gateway.service` (systemd user service, kiosk user)
- **Port:** `18789`
- **Config:** managed by Home Manager (`programs.openclaw`)
- **State dir:** `/var/lib/kiosk/.openclaw`
- **User:** `kiosk` (system user with linger)
- **Gateway mode:** `local` (loopback only)
- **Auth token:** auto-generated at first boot, retrieve with `./scripts/gateway-token.sh`
- **Flake input:** `nix-openclaw` (`github:MartinLoeper/nix-openclaw/main`)
- **Kiosk URL:** `http://localhost:18789` (Chromium points here in kiosk mode)
- **Browser:** agent reuses the kiosk Chromium via CDP (`attachOnly`, port `9222`)
- **Port forwarding:** access the gateway from your machine via SSH tunnel:
  ```sh
  ssh -i id_ed25519_rpi5 -L 18789:127.0.0.1:18789 -N nixos@<host>
  ```
  Then open `http://localhost:18789` locally.

## PinchChat (Web UI)

[PinchChat](https://github.com/MarlBurroW/pinchchat) is a webchat UI for interacting with the OpenClaw gateway from your workstation.

```sh
# 1. Set up SSH tunnel to the gateway
ssh -i id_ed25519_rpi5 -L 18789:127.0.0.1:18789 -N nixos@<host>

# 2. Run PinchChat
docker run -d --name pinchchat -p 3000:80 \
  -e VITE_GATEWAY_WS_URL=ws://localhost:18789 \
  ghcr.io/marlburrow/pinchchat:latest

# 3. Open http://localhost:3000 and enter the gateway token
```

Retrieve the token with `./scripts/gateway-token.sh`.

## Writing Skills and Agent Instructions

- Skills (`.claude/skills/`) and CLAUDE.md must be **generic** — no user-specific paths, credentials, CLI wrappers, or machine-specific details.
- User-specific information (e.g. custom CLI wrappers like `mloeper-hcloud`, SSH key names, server IPs) belongs in **dynamic Claude memory** (auto-memory `MEMORY.md`), not in checked-in files.

## NixOS Specifics

- Bootloader: `"kernel"` (RPi kernel-based, supports generational rollback)
- State version: `25.05`
- Built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) flake
- PipeWire with ALSA + PulseAudio compat for HDMI audio
- RTKit enabled for realtime scheduling
