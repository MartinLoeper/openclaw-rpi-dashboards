# OpenClaw RPi Dashboards

## Deployment

- **Target device:** Raspberry Pi 5 reachable at `openclaw-rpi5.local` (mDNS)
- **Deploy command:** `./scripts/deploy.sh`
- **SSH key:** `id_ed25519_rpi5` in repo root (gitignored), set up via `./scripts/setup-ssh.sh`

### "Deploy in background"

When the user says "deploy in background", run the deploy script as a background task:

```
./scripts/deploy.sh  (with run_in_background: true, timeout: 600000)
```

The deploy builds the NixOS closure locally (cross-compiled for aarch64) and copies it to the Pi over SSH. This can take several minutes. While it runs:

1. Continue working on other tasks — don't block on the deploy.
2. You will be notified when the background task completes.
3. When it finishes, check the output for errors and report the result to the user.
4. If deploying a specialisation, append `-- --specialisation <name>` to the deploy command.

## Architecture

- **NixOS flake** with two configurations sharing `commonModules`:
  - `rpi5` — for live deploys via `nixos-rebuild`
  - `rpi5-installer` — for building flashable SD images
- **Kiosk specialisation** — Cage + Chromium kiosk mode, activated at runtime or via deploy (see `docs/canvas.md`)
- Base system is CLI-only; graphical stack is opt-in via the specialisation

## OpenClaw Gateway

- **Service:** `openclaw-gateway.service` (systemd, `Restart=always`)
- **Port:** `18789`
- **Config:** `/etc/openclaw/openclaw.json`
- **State dir:** `/var/lib/openclaw`
- **User/Group:** `openclaw`
- **Flake input:** `nix-openclaw` (`github:MartinLoeper/nix-openclaw/main`)
- **Kiosk URL:** `http://localhost:18789` (Chromium points here in kiosk mode)

## NixOS Specifics

- Bootloader: `"kernel"` (RPi kernel-based, supports generational rollback)
- State version: `25.05`
- Built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) flake
