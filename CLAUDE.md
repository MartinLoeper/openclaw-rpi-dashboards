# ClawPi

## Deployment

- **Deploy command:** `./scripts/deploy.sh [host] --specialisation kiosk`
- **Default specialisation:** `kiosk` (always deploy with `--specialisation kiosk` unless told otherwise)
- See `docs/deployment.md` for full deployment workflow, specialisation switching, and known issues.
- See `docs/getting-started.md` for prerequisites and initial setup.

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

**CRITICAL: NEVER pipe build output through `tail`, `head`, or any filter.** These swallow build progress and make long builds appear stuck. Always let output stream directly.

- **Always** pass `--show-trace -L` (or `--print-build-logs`) to `nix build` commands so build progress is visible.
- **Never** use `| tail`, `| head`, `2>&1 | tail`, or any output filtering on build commands. This is the number one cause of builds appearing to hang.
- When running builds in background tasks, the full output must stream to the task output file unfiltered.
- **Run `nix build` and deploy commands in the background by default** (using `run_in_background: true, timeout: 600000`). These are long-running operations — don't block the conversation on them.

## Architecture

- **NixOS flake** with two configurations sharing `commonModules`:
  - `rpi5` — for live deploys via `nixos-rebuild`
  - `rpi5-installer` — for building flashable SD images
- **Kiosk specialisation** — labwc + Chromium kiosk mode, activated at runtime or via deploy (see `docs/canvas.md`)
- Base system is CLI-only; graphical stack is opt-in via the specialisation
- **Known issue:** specialisation may not activate on deploy — see `docs/deployment.md` for the manual activation procedure.
- **File structure:**
  - `modules/base.nix` — system config (boot, users, networking, PipeWire, Avahi, SSH)
  - `modules/kiosk.nix` — kiosk specialisation (labwc + Chromium, PipeWire wait)
  - `home/openclaw.nix` — Home Manager config for OpenClaw gateway (kiosk user)
  - `overlays/openclaw-gateway-fix.nix` — pnpm dependency fix for openclaw-gateway

## OpenClaw Gateway

- **Service:** `openclaw-gateway.service` (systemd user service, kiosk user)
- **Port:** `18789`
- **Logs:** `sudo tail -200 /tmp/openclaw/openclaw-gateway.log` on the Pi (not journalctl — stdout goes to file)
- **Browser:** agent reuses the kiosk Chromium via CDP (`attachOnly`, port `9222`)
- See `docs/openclaw.md` for full gateway details (auth, config, useful commands).
- See `docs/deployment.md` for port forwarding and PinchChat setup.

## Writing Skills and Agent Instructions

- Skills (`.claude/skills/`) and CLAUDE.md must be **generic** — no user-specific paths, credentials, CLI wrappers, or machine-specific details.
- User-specific information (e.g. custom CLI wrappers like `mloeper-hcloud`, SSH key names, server IPs) belongs in **dynamic Claude memory** (auto-memory `MEMORY.md`), not in checked-in files.

## NixOS Specifics

- Bootloader: `"kernel"` (RPi kernel-based, supports generational rollback)
- State version: `25.05`
- Built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) flake
- PipeWire with ALSA + PulseAudio compat for HDMI audio
- RTKit enabled for realtime scheduling
