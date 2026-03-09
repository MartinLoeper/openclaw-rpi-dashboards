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

## Canvas Workspace

The canvas workspace is a writable directory on the Pi's filesystem where the OpenClaw agent can create static web files (HTML, CSS, JS, images, etc.). The ClawPi Go backend serves these files at `http://localhost:3100/canvas/`.

### Architecture

```
Agent writes files → Canvas directory → Go FileServer → /canvas/ → Chromium kiosk
                     (filesystem)        (http.Dir)      (HTTP)     (CDP navigate)
```

Unlike the landing page (which is `//go:embed`'d into the Go binary and immutable), the canvas uses `http.FileServer(http.Dir(...))` to serve mutable files from disk. This lets the agent create and update content at runtime.

### Storage Modes

Controlled by the `services.clawpi.canvas.tmpfs` NixOS option:

| Mode | Path | Survives reboot | Use case |
|------|------|-----------------|----------|
| **tmpfs** (default) | `/tmp/clawpi-canvas` | No | Ephemeral content, experiments, one-off visualizations |
| **persistent** | `/var/lib/kiosk/.openclaw/canvas` | Yes | Permanent dashboards, status displays |

The directory is created automatically by the Go backend at startup via `os.MkdirAll`. Both the `clawpi` service and `openclaw-gateway` service receive the path via the `CLAWPI_CANVAS_DIR` environment variable.

### Archive

When `canvas_reset` is called, the current canvas contents are moved into a timestamped subdirectory under the **archive directory** (`/var/lib/kiosk/.openclaw/canvas-archive`). The archive is always persistent — it survives reboots regardless of the `canvas.tmpfs` setting.

The archive subdirectory is named with a short descriptive slug (e.g. `weather-dashboard`, `photo-gallery`). The agent chooses the name based on the project content. Names use lowercase, dashes, no spaces.

Environment variable: `CLAWPI_CANVAS_ARCHIVE_DIR` (default: `/var/lib/kiosk/.openclaw/canvas-archive`).

### Agent Tools

Six tools give the agent full control over the canvas lifecycle:

| Tool | Description |
|------|-------------|
| `canvas_folder` | Returns the workspace path and usage instructions (no side effects) |
| `canvas_open` | Navigates kiosk Chromium to `http://localhost:3100/canvas/{path}` via CDP |
| `canvas_close` | Navigates back to the landing page (`http://localhost:3100`) |
| `canvas_reset` | Archives current canvas contents, then clears the workspace |
| `canvas_list_archive` | Lists all archived projects in the archive directory |
| `canvas_restore` | Archives the current canvas (if non-empty), then restores a project from the archive |

### Agent Workflow

1. Agent calls `canvas_folder` to get the workspace path
2. Agent writes HTML/CSS/JS files to that directory
3. Agent calls `canvas_open` to navigate Chromium to the canvas
4. User sees the content on the kiosk display
5. Agent can update files and call `canvas_open` again to reload
6. Agent calls `canvas_close` to return to the home screen
7. When starting a **new** project, agent calls `canvas_reset` to archive and clear

#### Starting a new task

When the user asks to build something new, the agent should:
- If the canvas already has content, **ask the user** whether they want to modify the existing project or start a new one — do not assume.
- If it is clear that a completely new project starts, call `canvas_reset` (which archives the current content first).
- If the user wants to keep both the old and new project, archive first, then start fresh.

#### Restoring an archived project

1. Agent calls `canvas_list_archive` to show available projects
2. Agent calls `canvas_restore` with the project name to swap it back in

### Implementation Details

- **Go backend** (`pkgs/clawpi/internal/web/server.go`): Mounts `http.StripPrefix("/canvas/", http.FileServer(http.Dir(canvasDir)))` on the existing mux. Creates both canvas and archive directories at startup.
- **Config** (`pkgs/clawpi/internal/config/config.go`): Reads `CLAWPI_CANVAS_DIR` and `CLAWPI_CANVAS_ARCHIVE_DIR` env vars
- **NixOS option** (`modules/clawpi.nix`): `services.clawpi.canvas.tmpfs` controls canvas storage mode. Archive is always persistent at `/var/lib/kiosk/.openclaw/canvas-archive`.
- **Environment wiring** (`home/clawpi.nix`, `home/openclaw.nix`): Both services get `CLAWPI_CANVAS_DIR` and `CLAWPI_CANVAS_ARCHIVE_DIR`
- **Agent tools** (`pkgs/clawpi-tools/canvas.ts`): CDP navigation + filesystem operations + archive management
