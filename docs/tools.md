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
| `audio_transcribe` | Audio | `seconds?` | Record and transcribe speech (Groq cloud or local whisper.cpp) |
| `audio_play` | Audio | `path` | Play an audio file through the speakers |
| `tts_cartesia` | Audio | `text`, `voice?`, `model?`, `language?`, `speed?` | TTS via Cartesia Sonic API |
| `tts_cartesia_voices` | Audio | `search?`, `gender?`, `limit?` | Search and list Cartesia voices |
| `tts_hq` | Audio | `text`, `voice?`, `model?` | High-quality TTS via ElevenLabs API |
| `tts_stop` | Audio | — | Stop any currently playing audio |
| `tts_hq_voices` | Audio | `search?`, `voice_type?`, `page_size?` | Search and list ElevenLabs voices |
| `screenshot_display` | Screenshot | — | Full compositor screenshot (grim) |
| `screenshot_browser` | Screenshot | `format?`, `quality?` | Browser viewport screenshot (CDP) |
| `canvas_folder` | Canvas | — | Get canvas workspace path and usage instructions |
| `canvas_open` | Canvas | `path?` | Navigate kiosk Chromium to canvas content via CDP |
| `canvas_close` | Canvas | — | Navigate back to the landing page |
| `canvas_archive` | Canvas | `name` | Archive current canvas project, then clear workspace |
| `canvas_list_archive` | Canvas | — | List all archived canvas projects |
| `canvas_restore` | Canvas | `name` | Archive current canvas (if any), copy a project from archive (archive preserved) |
| `display_power` | Display | `state` ("on"/"off") | Turn the display on or off via wlr-randr |
| `system_poweroff` | System | — | Shut down the Raspberry Pi |
| `system_reboot` | System | — | Reboot the Raspberry Pi |

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

Record audio from the microphone and transcribe it using the configured transcription backend. Tries Groq cloud first (if enabled), falls back to local whisper.cpp. Requires `services.clawpi.audio.enable = true`.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `seconds` | number | no | 5 | Recording duration in seconds (1–60) |

**Returns:** Transcription text, or a "no speech detected" message.

**How it works:** Records via `pw-record`, then calls the shared `whisper-transcribe` wrapper from the gateway's `openclaw.json`. The wrapper tries Groq cloud transcription first (if `services.clawpi.audio.groq.enable = true`), then falls back to local `whisper-cli`. Format conversion is handled automatically.

### `audio_play`

Play an audio file through the default audio output (speakers). Supports WAV, MP3, OGG, FLAC, and other common formats. Non-WAV formats are converted via ffmpeg before playback.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | yes | Absolute path to the audio file |

**Returns:** Confirmation message.

**How it works:** WAV files are played directly via `pw-play`. Other formats (MP3, OGG, etc.) are first converted to WAV with `ffmpeg`, then played.

**TTS integration:** The built-in `tts` tool generates speech as an MP3 file (e.g. `/tmp/openclaw/tts-.../voice-*.mp3`) and sends it as a Telegram voice message. To also play it through the Pi's speakers, the agent can call `audio_play` with the TTS output path. For higher quality, use `tts_hq` which generates via ElevenLabs.

### `tts_cartesia`

Generate speech from text using Cartesia's Sonic TTS API. Returns the path to a generated WAV file — call `audio_play` to play it through the speakers.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | yes | — | Text to convert to speech |
| `voice` | string | no | `a0e99841-438c-4a64-b679-ae501e7d6091` | Cartesia voice ID |
| `model` | string | no | `sonic-2` | Cartesia model ID |
| `language` | string | no | auto-detect | Language code (e.g. `en`, `de`, `fr`) |
| `speed` | number | no | normal | Speech speed from 0.6 to 1.5 |

**Returns:** File path to the generated WAV (e.g. `/tmp/clawpi-tts-cartesia/voice-*.wav`).

**Setup:** Provision an API key with `./scripts/provision-cartesia.sh [host]`. The key is read from `/var/lib/clawpi/cartesia-api-key` at runtime.

**Models:**

| Model | Latency | Description |
|-------|---------|-------------|
| `sonic-2` | ~90ms | Most capable, ultra-realistic speech |
| `sonic-turbo` | ~40ms | Half the latency of Sonic-2 |

### `tts_cartesia_voices`

Search and list available Cartesia voices. Returns voice IDs, names, descriptions, and languages.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `search` | string | no | — | Search term to filter by name, description, or voice ID |
| `gender` | string | no | — | Filter: `"masculine"`, `"feminine"`, `"gender_neutral"` |
| `limit` | number | no | 20 | Max results (1–100) |

**Returns:** List of voices with IDs, names, descriptions, and languages.

### `tts_hq`

Generate high-quality speech from text using the ElevenLabs cloud TTS API. Returns the path to the generated MP3 file — call `audio_play` to play it through the speakers.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | yes | — | Text to convert to speech |
| `voice` | string | no | `JBFqnCBsd6RMkjVDRZzb` (George) | ElevenLabs voice ID |
| `model` | string | no | `eleven_multilingual_v2` | ElevenLabs model ID |

**Returns:** File path to the generated MP3 (e.g. `/tmp/clawpi-tts-hq/voice-*.mp3`).

**Setup:** Provision an API key with `./scripts/provision-elevenlabs.sh [host]`. The key is read from `/var/lib/clawpi/elevenlabs-api-key` at runtime.

**Popular voices:**

| Voice | ID | Style |
|-------|----|-------|
| George | `JBFqnCBsd6RMkjVDRZzb` | Warm, natural (default) |
| Rachel | `21m00Tcm4TlvDq8ikWAM` | Calm, clear |
| Domi | `AZnzlk1XvdvUeBnXmlld` | Strong, expressive |
| Bella | `EXAVITQu4vr4xnSDxMaL` | Soft, friendly |

**Models:**

| Model | Latency | Quality | Languages |
|-------|---------|---------|-----------|
| `eleven_multilingual_v2` | Standard | Best | 29 languages |
| `eleven_turbo_v2_5` | Low | Good | 32 languages |

### `tts_stop`

Stop any currently playing audio by killing the `pw-play` process. Also hides the Eww stop button overlay.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Confirmation message.

**How it works:** Calls `POST /api/tts/stop` on the clawpi daemon, which runs `pkill -f pw-play` and hides the stop button overlay.

### `tts_hq_voices`

Search and list available ElevenLabs voices. Returns voice IDs, names, categories, and labels.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `search` | string | no | — | Search term to filter by name, description, or labels |
| `voice_type` | string | no | — | Filter: `"personal"`, `"community"`, `"default"`, `"workspace"`, `"saved"` |
| `page_size` | number | no | 20 | Max results (1–100) |

**Returns:** List of voices with IDs, names, categories, and labels.

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

## Canvas

The canvas tools give the agent a writable workspace for building static web content (HTML, CSS, JS) that is displayed on the kiosk screen. Files are served at `http://localhost:3100/canvas/`. See `docs/canvas.md` for architecture and storage details.

**Important agent behavior:**
- **Never move files directly** into the archive directory. Always use the `canvas_archive` tool — it handles creating the subdirectory and moving files.
- When starting a completely new task, always call `canvas_archive` first to archive the current project.
- If it is unclear whether the user wants to modify the existing project or start fresh, **ask the user** — do not assume.

### Version control with git

The canvas directory is git-tracked. The agent **must** commit every change the user requests:

1. **First use:** If the canvas directory is not yet a git repo, run `git init` and make an initial commit.
2. **Every change:** After modifying canvas files, stage and commit with a short descriptive message summarizing what changed (e.g. `"Add temperature chart"`, `"Fix header alignment"`).
3. **Before archiving:** Ensure all changes are committed before calling `canvas_archive`. Uncommitted work will still be archived, but the git history makes it easy to review and revert.
4. **After restoring:** The restored project includes its `.git` directory and full history.

This gives the user the ability to ask the agent to undo changes, compare versions, or review what was modified.

### `canvas_folder`

Get the canvas workspace directory path and usage instructions. Call this first to know where to write files.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** The absolute path to the canvas workspace directory, the base URL where files are served (`http://localhost:3100/canvas/`), and instructions for creating web content.

**Static files only:** The canvas serves plain HTML, CSS, and JS — no build tools (npm, yarn, webpack) are available on the Pi. For third-party libraries, use CDN links directly in your HTML:
```html
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@latest/build/three.module.js" type="module"></script>
<link href="https://cdn.jsdelivr.net/npm/tailwindcss@4/dist/tailwind.min.css" rel="stylesheet">
```

### `canvas_open`

Navigate the kiosk Chromium browser to canvas content via CDP. Use after writing files to the canvas directory.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `path` | string | no | `"index.html"` | Relative path within the canvas directory to navigate to |

**Returns:** Confirmation with the URL navigated to.

**How it works:** Connects to Chromium's CDP WebSocket at `127.0.0.1:9222` and sends `Page.navigate` to `http://localhost:3100/canvas/{path}`.

### `canvas_close`

Navigate the kiosk Chromium browser back to the landing page.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Confirmation message.

**How it works:** CDP `Page.navigate` to `http://localhost:3100`.

### `canvas_archive`

Archive the current canvas project. Creates a new subdirectory with the given `name` in the archive directory, moves all canvas files into it, and clears the workspace. This is the **only** way to archive — never move files to the archive directory manually.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Short descriptive name for the project. Use lowercase, dashes, no spaces (e.g. `weather-dashboard`, `photo-gallery`, `clock-widget`). |

**Returns:** Confirmation with the archive path (e.g. `canvas-archive/weather-dashboard/`).

**How it works:**
1. Creates `<archive-dir>/<name>/` as a new subdirectory
2. Moves **all** files and directories from the canvas directory into that subdirectory
3. If a project with that name already exists in the archive, appends a numeric suffix (e.g. `weather-dashboard-2`)
4. The canvas directory is now empty and ready for new content

The tool always archives **everything** in the canvas directory — there is no way to archive a subset. If you need to keep some files while archiving others, move the files you want to keep to a temporary location first (e.g. `/tmp/canvas-stash/`), call `canvas_archive`, then move them back.

**When to call:** Always call this before starting a new project. If the canvas is already empty, the tool is a no-op (nothing to archive). If unsure whether the user wants a new project or a modification of the current one, ask first.

### `canvas_list_archive`

List all archived canvas projects. Shows project names and allows the user to choose one to restore.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** List of archived project directory names (e.g. `weather-dashboard`, `photo-gallery`).

### `canvas_restore`

Restore an archived project back into the active canvas workspace. If the canvas currently has content, the tool **automatically archives it first** (prompts for a name) to avoid losing work.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Name of the archived project to restore (as shown by `canvas_list_archive`) |

**Returns:** Confirmation message.

**How it works:**
1. If the canvas directory is non-empty, archives the current project first (agent must provide a name for it)
2. **Copies** the named project from the archive into the canvas directory (the archive is preserved, not deleted)
3. The project is now live and served at `http://localhost:3100/canvas/`

Call `canvas_open` after restoring to navigate the browser to the restored content.

## Display & System

Tools for controlling the display and system power. Both require `services.clawpi.powerControl.enable = true` (enabled by default). The tools check for the `CLAWPI_POWER_CONTROL` environment variable at runtime and refuse to execute if it is not set.

### `display_power`

Turn the connected display on or off via `wlr-randr`. Use this for energy saving, privacy (blanking the screen), or waking the display.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `state` | `"on"` \| `"off"` | yes | Turn the display on or off |

**Returns:** Confirmation message with the output name.

**How it works:** Lists Wayland outputs via `wlr-randr`, then toggles the first output with `--on` or `--off`. Requires the `WAYLAND_DISPLAY` environment to be set (handled automatically by the helper).

### `system_poweroff`

Shut down the Raspberry Pi completely. The device will need to be physically power-cycled to start again. The agent must always confirm with the user before calling this tool.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Confirmation that shutdown has been initiated.

**How it works:** Runs `sudo poweroff`. The kiosk user is granted passwordless sudo for `poweroff` when `services.clawpi.powerControl.enable = true`.

### `system_reboot`

Reboot the Raspberry Pi. The system shuts down and starts back up automatically. The agent must always confirm with the user before calling this tool.

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | |

**Returns:** Confirmation that reboot has been initiated.

**How it works:** Runs `sudo reboot`. The kiosk user is granted passwordless sudo for `reboot` when `services.clawpi.powerControl.enable = true`.

## Planned Tools

See `docs/ideas.md` for tools under consideration:

- **Display brightness** — adjust brightness via DDC/CI (`ddcutil`)
- **Show choices** — Eww overlay for multi-option disambiguation, returns user selection
- **Show message** — speech bubble Eww overlay with agent text
- **Volume/brightness OSD** — Eww overlays when the agent adjusts hardware settings
- **Browser mode switch** — toggle between kiosk (`--app`) and browse (`--start-fullscreen`) mode
- **Virtual keyboard** — on-screen keyboard for text input
