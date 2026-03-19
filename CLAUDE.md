# ClawPi

## Deployment

- **Deploy command:** `./scripts/deploy.sh [host] --specialisation kiosk`
- **Flake configuration:** Set via `FLAKE_ATTR` env var (defaults to `rpi5`). Example: `FLAKE_ATTR=rpi5-matrix-debug ./scripts/deploy.sh ...` — do NOT pass `--flake` as a CLI argument. Use `rpi4` for Raspberry Pi 4B targets.
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

**CRITICAL: `git add` new files before running any `nix` command.** Nix flakes only see paths that are tracked (staged) in git. If you create a new `.nix` file and reference it without staging it first, the build will fail with "path does not exist".

**CRITICAL: NEVER pipe build output through `tail`, `head`, or any filter.** These swallow build progress and make long builds appear stuck. Always let output stream directly.

- **Always** pass `--show-trace -L` (or `--print-build-logs`) to `nix build` commands so build progress is visible.
- **Never** use `| tail`, `| head`, `2>&1 | tail`, or any output filtering on build commands. This is the number one cause of builds appearing to hang.
- When running builds in background tasks, the full output must stream to the task output file unfiltered.
- **Run `nix build` and deploy commands in the background by default** (using `run_in_background: true, timeout: 600000`). These are long-running operations — don't block the conversation on them.

## Architecture

- **NixOS flake** with configurations sharing `commonModules` (application layer) and per-board hardware modules:
  - `rpi5` / `rpi4` — for live deploys via `nixos-rebuild`
  - `rpi5-installer` / `rpi4-installer` — for building flashable SD images
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

## OpenClaw Plugins

- Plugins live in `pkgs/` (e.g. `pkgs/clawpi-tools/`)
- TypeScript loaded directly by the gateway via jiti — no build step
- When changing plugin source code (`index.ts`), **bump the `version` field** in both `openclaw.plugin.json` and `package.nix` so the Nix store path changes and the gateway picks up the new code

## Go Packages

- Go packages live in `pkgs/` (e.g. `pkgs/clawpi/`)
- Build locally with `CGO_ENABLED=0 go build ./...` (no C compiler available on the dev machine)
- Production builds are handled by Nix (`buildGoModule`) which provides the full toolchain

## VM Development

The flake exports `nixosModules.default` for running the ClawPi software stack in a NixOS dev VM (x86_64) without Pi hardware. The VM config lives at `/nixos-config/`.

- **Rebuild:** `git commit` in clawpi2, then in `/nixos-config/`: `nix flake update clawpi && sudo nixos-rebuild switch --flake .#nixos-dev`
- **CRITICAL: `git+file:` caching** — The VM flake uses `git+file:/host/clawpi2`. Nix locks to a specific git commit. After changing clawpi2 code, you must `git commit` then `nix flake update clawpi` — just `git add` is not enough.
- **Services (dev user):** `clawpi-daemon.service`, `clawpi-quickshell.service` — restart both with `systemctl --user restart clawpi-daemon.service`
- **Services (kiosk user):** `openclaw-gateway.service` — restart with `sudo -u kiosk XDG_RUNTIME_DIR=/run/user/991 systemctl --user restart openclaw-gateway.service`
- **Chromium:** Launch with `clawpi-chromium` (windowed) or `clawpi-chromium-kiosk` (fullscreen)
- **Port forwarding to host:** `./scripts/forward-vm.sh` (SSH tunnel for ports 18789, 3100, 9222)

### Quickshell debugging

- **Ghost processes are the #1 pitfall.** Running `quickshell -p /tmp/...` manually during testing leaves invisible overlay instances that stack on top of the service. Always `pkill -f quickshell` and verify with `pgrep -a quickshell` before testing. This was the main debugging red herring — tests appeared broken because stale overlays blocked the new one.
- **Canvas doesn't render on virtio-gpu.** Use Rectangle elements instead. Original animated Canvas version saved as `shell.qml.bak`.
- **FileView inotify doesn't detect Go's `os.WriteFile`.** The QML uses `Process { command: ["cat", path] }` with a Timer polling every 200ms instead.
- **FileView.preload is async.** `onFileChanged` doesn't fire on initial load — use `onTextChanged` to catch the first read.

## NixOS Specifics

- Bootloader: `"kernel"` for Pi 5 (generational rollback), `"uboot"` for Pi 4
- State version: `25.05`
- Built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) flake
- PipeWire with ALSA + PulseAudio compat for HDMI audio
- RTKit enabled for realtime scheduling
