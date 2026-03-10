# Eww Overlays

ClawPi uses [Eww](https://elkowar.github.io/eww/) for on-screen overlay widgets on the kiosk display. The Go daemon (`clawpi`) manages widget state via `eww update` commands.

## Architecture

```
Gateway WebSocket → Go daemon (clawpi) → eww update → Overlay windows
TypeScript tools → HTTP API (port 3100) → Go daemon → eww update
```

- **Eww daemon** runs as a systemd user service (`eww.service`)
- **Go daemon** (`clawpi.service`) connects to the gateway WebSocket, listens for agent state changes, and drives Eww variables
- **TypeScript tools** (clawpi-tools plugin) trigger overlays via HTTP endpoints on the Go daemon

## Files

| File | Purpose |
|------|---------|
| `pkgs/clawpi/eww/eww.yuck` | Widget definitions (variables, widgets, windows) |
| `pkgs/clawpi/eww/eww.scss` | Styles and animations |
| `pkgs/clawpi/internal/eww/controller.go` | Go state machine driving `eww update` calls |
| `pkgs/clawpi/internal/web/server.go` | HTTP endpoints that trigger overlay changes |
| `pkgs/clawpi/internal/gateway/client.go` | WebSocket client receiving agent state events |
| `home/clawpi.nix` | systemd services for eww and clawpi daemons |

## Windows

### `status-overlay` (top right)

Shows agent activity state with an emoji icon and label. Automatically opens when the agent is active and closes when idle.

- **Position:** top right, 10px margin
- **Size:** 300x60px
- **Variable:** `clawpi_state`

| State | Icon | Label | Style |
|-------|------|-------|-------|
| `thinking` | 🧠 | Thinking... | Pulsing animation |
| `transcribing` | 🎙 | Transcribing... | Pulsing animation |
| `tool_use` | 🔧 | Using: {tool_name} | Default |
| `responding` | 💬 | Responding... | Default |
| `error` | ⚠ | {message} | Red background |
| `disconnected` | 🔌 | Reconnecting... | Dimmed |
| `idle` | — | — | Hidden |

**Triggered by:** Go daemon watching gateway WebSocket lifecycle events. Also set by the `whisper-transcribe` wrapper script during voice pipeline transcription.

### `tts-stop-overlay` (bottom right)

Red stop button shown during audio playback. Clicking it kills `pw-play` and hides the button.

- **Position:** bottom right, 10px margin
- **Size:** 120x50px
- **Variable:** `clawpi_tts_playing`
- **Onclick:** `POST /api/tts/stop`

**Triggered by:** `audio_play` tool calls `POST /api/tts/playing` to show, `POST /api/tts/stopped` to hide.

### `recording-overlay` (top right, below status)

Red recording indicator shown while the `audio_transcribe` tool is actively recording from the microphone.

- **Position:** top right, 80px from top (below status overlay)
- **Size:** 200x50px
- **Variable:** `clawpi_recording`

**Triggered by:** `audio_transcribe` tool calls `POST /api/recording/start` to show, `POST /api/recording/stop` to hide.

## HTTP API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/tts/playing` | POST | Show TTS stop button |
| `/api/tts/stop` | POST | Kill pw-play + hide stop button |
| `/api/tts/stopped` | POST | Hide stop button (natural end) |
| `/api/recording/start` | POST | Show recording indicator |
| `/api/recording/stop` | POST | Hide recording indicator |

## Adding a New Overlay

1. Add a `defvar` and `defwidget` in `eww.yuck`
2. Add a `defwindow` with position, size, and stacking
3. Add styles in `eww.scss`
4. Add open/close logic in `controller.go`
5. Add HTTP endpoint in `server.go` if triggered by TypeScript tools
6. Bump version in `pkgs/clawpi/` package
