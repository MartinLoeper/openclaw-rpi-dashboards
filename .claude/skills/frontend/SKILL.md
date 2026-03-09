---
name: frontend
description: Style and iterate on the ClawPi kiosk GUI. Take screenshots of the Pi's Chromium display via CDP, review the result, and edit HTML/CSS/Eww widget files. Use when the user asks to change the landing page design, tweak colors/fonts/layout, or review what the kiosk screen looks like.
user-invocable: true
---

# Frontend — ClawPi Kiosk GUI

Style and iterate on the ClawPi kiosk display. This skill provides a feedback loop: take a screenshot, review, edit, rebuild, redeploy, screenshot again.

## Architecture

The kiosk display has two independent layers:

1. **Chromium** (fullscreen) — serves the landing page from the clawpi Go service at `http://localhost:3100`. HTML/CSS lives in `pkgs/clawpi/internal/web/landing-page/`.
2. **Eww overlays** (wlr-layer-shell) — floating status widgets rendered by Eww on top of Chromium. Config lives in `pkgs/clawpi/eww/`.

**Important:** CDP screenshots only capture the Chromium viewport. Eww overlays are rendered by the Wayland compositor (labwc) in a separate layer and are **not visible** in CDP screenshots. To understand where Eww widgets appear on screen, query Eww separately:

```sh
# List open windows and their geometry
ssh nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) eww --config <config-dir> windows"
ssh nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) eww --config <config-dir> get <variable>"
```

Combine the CDP screenshot with Eww window/anchor info to reason about the full composite display. For a true full-screen capture including all layers, use the Wayland screenshot method described below.

## Taking screenshots

There are two screenshot methods. Use the right one for the job:

| Method | Captures | Use when |
|--------|----------|----------|
| **CDP** (Chromium only) | Chromium viewport only | Iterating on the landing page HTML/CSS |
| **Wayland** (grim) | Full compositor output (Chromium + Eww + all layers) | Working on Eww widgets, checking overall layout, or when CDP doesn't show what you need |

### Method 1: CDP screenshot (Chromium only)

#### Prerequisites

An SSH tunnel to the Pi's CDP port must be active:

```sh
ssh -i id_ed25519_rpi5 -L 9222:127.0.0.1:9222 -N nixos@openclaw-rpi5.local
```

#### Using the screenshot tool

From the devShell (provides `clawpi-screenshot` and Python with websockets):

```sh
nix develop --command clawpi-screenshot [output.png]
```

Or directly:

```sh
nix develop --command python3 scripts/screenshot.py [output.png]
```

Default output: `/tmp/clawpi-screenshot.png`

#### Programmatic usage (for Claude)

```sh
nix develop --command python3 -c "
import json, base64, asyncio, websockets, urllib.request

async def screenshot(path='/tmp/clawpi-screenshot.png'):
    with urllib.request.urlopen('http://localhost:9222/json') as r:
        ws_url = [t for t in json.loads(r.read()) if t['type']=='page'][0]['webSocketDebuggerUrl']
    async with websockets.connect(ws_url) as ws:
        await ws.send(json.dumps({'id':1,'method':'Page.captureScreenshot','params':{'format':'png'}}))
        resp = json.loads(await ws.recv())
        open(path,'wb').write(base64.b64decode(resp['result']['data']))
        print(f'Saved {path}')

asyncio.run(screenshot())
"
```

Then read the screenshot with the Read tool to view it.

### Method 2: Wayland screenshot (full compositor — grim)

Captures the full compositor output including Chromium, Eww overlays, and any other Wayland surfaces. Uses `grim` which is installed as a package on the kiosk user.

#### Taking a Wayland screenshot

```sh
# Capture on the Pi and copy to local machine in one step
# Note: sudo -u doesn't load the kiosk profile PATH, so use the full path to grim
ssh nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) WAYLAND_DISPLAY=wayland-0 /etc/profiles/per-user/kiosk/bin/grim /tmp/wayland-screenshot.png" && \
scp nixos@<host>:/tmp/wayland-screenshot.png /tmp/clawpi-wayland-screenshot.png
```

Then read `/tmp/clawpi-wayland-screenshot.png` with the Read tool to view it.

#### When to prefer Wayland screenshots

- **Eww widget work** — Eww overlays are invisible to CDP; grim is the only way to see them
- **Layout verification** — confirm that Eww widgets and Chromium are properly layered/positioned
- **Debugging visual glitches** — compositor-level issues (transparency, z-order) only show in grim
- **Overall appearance** — see exactly what the user sees on the HDMI display

#### Troubleshooting

If `grim` fails with a "no output" error, ensure the compositor is running and `WAYLAND_DISPLAY` is set:

```sh
ssh nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) ls /run/user/\$(id -u kiosk)/wayland-*"
```

Use the actual socket name shown (usually `wayland-0`).

## File locations

| What | Path | Notes |
|------|------|-------|
| Landing page HTML | `pkgs/clawpi/internal/web/landing-page/index.html` | Embedded in Go binary via `//go:embed` |
| Landing page server | `pkgs/clawpi/internal/web/server.go` | HTTP file server |
| Eww widget config | `pkgs/clawpi/eww/eww.yuck` | Widget layout (layer-shell overlay) |
| Eww styles | `pkgs/clawpi/eww/eww.scss` | Widget styling |
| Eww controller | `pkgs/clawpi/internal/eww/controller.go` | State management |
| Web server port | `CLAWPI_WEB_ADDR` env var | Default `:3100` |

## Workflow

1. **Screenshot** the current state to see what you're working with
2. **Edit** the HTML/CSS/Eww files
3. **Build** — the landing page is embedded in the Go binary, so changes require a rebuild
4. **Deploy** to the Pi (use Hetzner builder for faster builds)
5. **Activate** the kiosk specialisation if needed
6. **Screenshot** again to verify

For quick iteration on HTML/CSS without rebuilding, you can also serve the landing page locally and review in a browser. But the authoritative view is always the CDP screenshot from the Pi.

## Design constraints

- Display: 1920x1080 HDMI (typical Pi setup)
- Dark background preferred (OLED-friendly, reduces glare)
- Monospaced fonts for the hacker aesthetic
- No scrolling — everything must fit in viewport
- Chromium runs in `--kiosk` mode (no chrome, no scrollbars)
- Eww overlays anchor via wlr-layer-shell (center, edges, etc.)
