# Canvas: Kiosk Display for ClawPi

## Decision

Use **labwc** (Wayland stacking compositor) + **Chromium** in `--kiosk` mode as the graphical display stack, delivered as a NixOS **specialisation** so the base system remains CLI-only.

## Why labwc + Chromium?

- **labwc** is a lightweight Wayland stacking compositor that supports window rules, multiple overlapping windows, and layer-shell surfaces. This is essential for ClawPi — the Eww status overlay renders as a layer-shell surface on top of the Chromium kiosk window.
- **Chromium** renders any web content OpenClaw serves (dashboards, status pages, admin UIs). The `--kiosk` flag hides all browser UI. Additional flags disable first-run dialogs, crash bubbles, and pinch-to-zoom for a clean touch-friendly experience.
- A labwc window rule maximizes and removes decorations from Chromium automatically, giving the same fullscreen kiosk experience as a dedicated kiosk compositor.
- Together they provide a minimal, robust display pipeline: kernel DRM → Wayland (labwc) → Chromium + Eww overlays → web content at `http://localhost:3100`.

### Why not Cage?

Cage is a single-application Wayland compositor — it runs exactly one window fullscreen. This made Eww overlays impossible since Cage doesn't support layer-shell or multiple surfaces. labwc provides the multi-window support needed while remaining lightweight.

## Why a Specialisation?

NixOS specialisations create alternative system profiles that share the same base closure but layer additional configuration on top. This gives us:

- **CLI by default** — the base system boots to a console, keeping the image small and SSH-friendly for headless operation.
- **Kiosk on demand** — the graphical stack is only activated when explicitly switched to, avoiding wasted resources when no display is attached.
- **Atomic switching** — `switch-to-configuration switch` transitions between CLI and kiosk without a reboot.
- **Shared closure** — both profiles share the same Nix store paths, so deploying the kiosk specialisation adds only the labwc/Chromium delta to the system.

## How to Switch

### Activate kiosk mode (runtime)

```sh
sudo /run/current-system/specialisation/kiosk/bin/switch-to-configuration switch
```

### Return to CLI mode (runtime)

```sh
sudo /run/current-system/bin/switch-to-configuration switch
```

### Deploy directly into kiosk mode

```sh
./scripts/deploy.sh 192.168.0.64 --specialisation kiosk
```

## Session Startup

labwc is launched by greetd as the `kiosk` user. The autostart script (`home/labwc.nix`):

1. Exports `WAYLAND_DISPLAY` into the systemd user environment
2. Starts the `labwc-session.service` marker, which activates `graphical-session.target`
3. Waits for the PipeWire socket (HDMI/USB audio)
4. Launches Chromium in kiosk mode pointing at the ClawPi landing page

Services that depend on `graphical-session.target` (eww, clawpi) start automatically.

## Bigger Picture

OpenClaw serves dashboard web applications on `http://localhost:3100`. The kiosk specialisation turns a Raspberry Pi 5 into a plug-and-play display appliance: power on, auto-login the `kiosk` user, launch labwc + Chromium, and render whatever OpenClaw is serving — no manual interaction required.
