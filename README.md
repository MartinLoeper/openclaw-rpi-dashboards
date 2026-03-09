# ClawPi

A Raspberry Pi 5 + 10" touchscreen that acts as a voice-controlled AI dashboard appliance. Say "hey claw", describe what you want, and the [OpenClaw gateway](https://github.com/MartinLoeper/nix-openclaw) builds and displays it — no coding required.

1. **OpenClaw gateway** runs on the Pi, generating dashboards on `localhost:18789`
2. **Kiosk mode** (Cage + Chromium) shows them fullscreen on the wired display
3. **Voice wake** ("openclaw", "claude", "computer") triggers dashboard creation
4. **Talk mode** lets you refine dashboards through continuous conversation
5. **Claude Max** powers the AI — just a subscription, no API keys

See [docs/vision.md](docs/vision.md) for the full product vision and [docs/hardware.md](docs/hardware.md) for the hardware setup.

---

NixOS configuration built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

## Quick Start

See [docs/getting-started.md](docs/getting-started.md) for prerequisites, initial setup, and first boot instructions. For ongoing deploys, see [docs/deployment.md](docs/deployment.md).

## Flake Structure

| Config | Builder | Purpose |
|--------|---------|---------|
| `nixosConfigurations.rpi5` | `nixosSystem` | Remote deploys via `nixos-rebuild` |
| `nixosConfigurations.rpi5-installer` | `nixosSystem` + sd-image | Flashable SD card images |

Both share the same system configuration. We use `nixosSystem` (base) instead of `nixosSystemFull` to avoid RPi multimedia overlay rebuilds — see [docs/workarounds.md](docs/workarounds.md) for rationale.

The [OpenClaw gateway](https://github.com/MartinLoeper/nix-openclaw) runs as a systemd service (`openclaw-gateway.service`) on port 18789, serving AI-generated dashboards. It is included in both configurations via `commonModules`. See [docs/openclaw.md](docs/openclaw.md) for details.

### Kiosk Specialisation

A `kiosk` specialisation launches labwc (Wayland compositor) + Chromium in fullscreen mode, auto-logged in as the `kiosk` system user. The base system remains CLI-only by default. See [docs/deployment.md](docs/deployment.md) for switching instructions and [docs/canvas.md](docs/canvas.md) for the design rationale.

## ClawPi Overlay Daemon

A custom Go service (`clawpi`) connects to the OpenClaw gateway WebSocket as a `gateway-client` and listens for agent lifecycle events (thinking, tool use, responses). It drives [Eww](https://github.com/elkowar/eww) overlays rendered as Wayland layer-shell windows on top of the kiosk browser — giving visual feedback like "Thinking..." or "Using: browser" without interrupting the displayed content.

- **Source:** [`pkgs/clawpi/`](pkgs/clawpi/) (Go + Eww config)
- **Service:** `clawpi.service` (systemd user service, kiosk user)
- **Starts with:** `graphical-session.target` (only runs in kiosk mode)
- **Reconnects automatically** if the gateway restarts

## PinchChat (Web UI)

[PinchChat](https://github.com/MarlBurroW/pinchchat) provides a webchat interface for interacting with the OpenClaw gateway from your workstation. See [docs/deployment.md](docs/deployment.md) for setup instructions.

## Documentation

Additional design docs and integration guides live in [`docs/`](docs/).
