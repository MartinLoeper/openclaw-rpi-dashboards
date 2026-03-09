# ClawPi Tools

ClawPi ships an OpenClaw plugin (`clawpi-tools`) that gives the agent hardware control tools for the smart display. The plugin is a TypeScript module loaded by the gateway at startup.

**Source:** `pkgs/clawpi-tools/`

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

Play a short test tone through the default audio sink to verify output is working. Requires `alsa-utils` (`services.clawpi.debug = true`).

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

## Planned Tools

See `docs/ideas.md` for tools under consideration:

- **Display power** — turn the connected display on/off via `wlr-randr` or DDC/CI
- **TTS** — text-to-speech via KittenTTS, played through `pw-play`
- **Volume/brightness OSD** — Eww overlays when the agent adjusts hardware settings
- **Choice picker** — Eww overlay for multi-option disambiguation
- **Virtual keyboard** — on-screen keyboard for text input
- **Screenshot** — capture the kiosk display via CDP
