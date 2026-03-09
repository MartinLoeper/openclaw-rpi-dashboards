# ClawPi Tools

ClawPi ships an OpenClaw plugin (`clawpi-tools`) that gives the agent hardware control tools for the smart display. The plugin is a TypeScript module loaded by the gateway at startup.

**Source:** `pkgs/clawpi-tools/`

## Summary

| Tool | Category | Parameters | Description |
|------|----------|-----------|-------------|
| `audio_status` | Audio | — | List all PipeWire sinks, sources, and devices |
| `audio_get_volume` | Audio | — | Get current volume of default sink |
| `audio_set_volume` | Audio | `level` (0.0–1.0) | Set volume of default sink |
| `audio_test_tone` | Audio | `frequency?`, `duration?` | Play test sine wave (requires debug mode) |
| `audio_set_default_sink` | Audio | `sink_id` | Switch default audio output by sink ID |
| `audio_get_input_volume` | Audio | — | Get current volume of default source (mic) |
| `audio_set_input_volume` | Audio | `level` (0.0–1.0) | Set volume of default source (mic) |
| `audio_set_default_source` | Audio | `source_id` | Switch default audio input by source ID |
| `audio_record` | Audio | `seconds?` (1–30) | Record audio from mic, returns WAV |
| `audio_transcribe` | Audio | `seconds?`, `language?` | Record and transcribe speech via whisper.cpp |
| `screenshot_display` | Screenshot | — | Full compositor screenshot (grim) |
| `screenshot_browser` | Screenshot | `format?`, `quality?` | Browser viewport screenshot (CDP) |

## Audio

All audio tools operate on the PipeWire graph via WirePlumber (`wpctl`) and ALSA utilities (`speaker-test`). They run as the `kiosk` user with `XDG_RUNTIME_DIR` set automatically.

### `audio_status`

List all PipeWire audio devices, sinks, and sources. Shows sink IDs needed for `audio_set_default_sink`.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Full `wpctl status` output.

### `audio_get_volume`

Get the current volume level of the default audio sink.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Volume between 0.0 and 1.0 plus mute status.

### `audio_set_volume`

Set the volume of the default audio sink.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `level` | number | yes | Volume level from 0.0 (mute) to 1.0 (maximum) |

**Returns:** Confirmation with the new volume readback.

### `audio_test_tone`

Play a short test tone through the default audio sink to verify output is working.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `frequency` | number | no | 440 | Tone frequency in Hz (20–20000) |
| `duration` | number | no | 3 | Duration in seconds (1–30) |

**Returns:** Confirmation message.

### `audio_set_default_sink`

Switch the default audio output to a different sink. Use `audio_status` first to find available sink IDs.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sink_id` | number | yes | WirePlumber sink ID (e.g. 54 for USB speaker, 73 for HDMI) |

**Returns:** Confirmation message.

### `audio_get_input_volume`

Get the current volume level of the default audio source (microphone).

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Volume between 0.0 and 1.0 plus mute status.

### `audio_set_input_volume`

Set the volume of the default audio source (microphone).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `level` | number | yes | Input volume level from 0.0 (mute) to 1.0 (maximum) |

**Returns:** Confirmation with the new volume readback.

### `audio_set_default_source`

Switch the default audio input to a different source. Use `audio_status` first to find available source IDs.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source_id` | number | yes | WirePlumber source ID (e.g. 46 for USB mic) |

**Returns:** Confirmation message.

### `audio_record`

Record audio from the default input source (microphone) for a specified duration. Returns the recording as a WAV file (16kHz mono, 16-bit). Useful for testing microphone input or capturing ambient audio.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `seconds` | number | yes | Recording duration in seconds (1–30) |

**Returns:** Text summary and base64-encoded WAV audio file.

**How it works:** Runs `pw-record` (PipeWire) with a SIGTERM after the specified duration.

### `audio_transcribe`

Record audio from the microphone and transcribe it locally using whisper.cpp. Combines `pw-record` + `whisper-cli` in a single tool call. Requires `services.clawpi.audio.enable = true`.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `seconds` | number | no | 5 | Recording duration in seconds (1–60) |
| `language` | string | no | (from config) | Language code (e.g. `"en"`, `"de"`) or `"auto"` |

**Returns:** Transcription text, or a "no speech detected" message.

**How it works:** Records via `pw-record`, then runs `whisper-cli` with the model and language from the gateway's `openclaw.json` config. The whisper model path is read dynamically from the config so it stays in sync with the Nix configuration.

## Screenshots

Two screenshot tools are available, each capturing a different layer of the display stack. Choose based on what you need:

### When to use which

| Use case | Tool | Why |
|----------|------|-----|
| "What does the user see on the monitor?" | `screenshot_display` | Captures the full physical output including Eww overlays |
| "What web page is showing?" | `screenshot_browser` | Captures just the page content, clean and overlay-free |
| Debugging Eww overlays | `screenshot_display` | Only way to see if overlays are rendering correctly |
| Saving a dashboard to send/email | `screenshot_browser` | Clean capture without status indicators cluttering the image |
| Checking if the browser loaded correctly | `screenshot_browser` | Directly accesses the browser viewport |

### `screenshot_display`

Capture the entire Wayland compositor output using `grim`. This is what the user physically sees on the connected monitor — the Chromium kiosk window **and** any Eww overlays (status indicator, OSD, etc.) rendered on top.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** PNG image of the full display.

**How it works:** Runs `grim` with `WAYLAND_DISPLAY=wayland-0` to capture all layer-shell surfaces and windows composited by labwc.

### `screenshot_browser`

Capture the Chromium browser viewport via CDP (Chrome DevTools Protocol, port 9222). This captures **only** the web page content rendered inside the browser — Eww overlays and other compositor elements are **not** included.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `format` | `"png"` \| `"jpeg"` | no | `"png"` | Image format |
| `quality` | number | no | — | JPEG quality 0–100 (ignored for PNG) |

**Returns:** Image in the requested format.

**How it works:** Connects to Chromium's CDP WebSocket at `127.0.0.1:9222`, finds the first page target, and calls `Page.captureScreenshot`.

## Planned Tools

See `docs/ideas.md` for tools under consideration:

- **Display power** — turn the connected display on/off via `wlr-randr` or DDC/CI
- **Display brightness** — adjust brightness via DDC/CI (`ddcutil`)
- **Show choices** — Eww overlay for multi-option disambiguation, returns user selection
- **Show message** — speech bubble Eww overlay with agent text
- **Volume/brightness OSD** — Eww overlays when the agent adjusts hardware settings
- **Browser mode switch** — toggle between kiosk (`--app`) and browse (`--start-fullscreen`) mode
- **Virtual keyboard** — on-screen keyboard for text input
