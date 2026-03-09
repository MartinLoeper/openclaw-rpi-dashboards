# ClawPi Module Options

ClawPi extends the base NixOS configuration with custom services. Options are defined under `services.clawpi`.

## General

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.debug` | bool | `false` | Enable extra debugging tools (e.g. `speaker-test`) and verbose gateway logging (`OPENCLAW_LOG_LEVEL=debug`). Used by debug NixOS configurations (e.g. `rpi5-telegram-debug`). |

## Gateway Settings

Shared gateway connection settings used by all ClawPi services.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.gateway.url` | string | `"ws://localhost:18789"` | OpenClaw gateway WebSocket URL |
| `services.clawpi.gateway.tokenFile` | path | `/var/lib/kiosk/.openclaw/gateway-token.env` | Path to gateway auth token file (format: `OPENCLAW_GATEWAY_TOKEN=<hex>`) |

## Web Server

The ClawPi overlay daemon serves a landing page that the kiosk Chromium displays.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.web.port` | port | `3100` | HTTP port for the landing page |

The landing page is embedded in the `clawpi` Go binary and served at `http://localhost:<port>`. The kiosk Chromium opens this URL on startup.

## Canvas Workspace

The canvas is a writable directory where the agent creates static web files (HTML, CSS, JS). The ClawPi web server serves these files at `http://localhost:<port>/canvas/`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.canvas.tmpfs` | bool | `true` | `true` → workspace at `/tmp/clawpi-canvas` (volatile, cleared on reboot). `false` → workspace at `/var/lib/kiosk/.openclaw/canvas` (persistent, survives reboots). |

The canvas directory is created automatically at startup by the Go backend. Both the `clawpi` and `openclaw-gateway` services receive the `CLAWPI_CANVAS_DIR` environment variable so the agent tools can locate it.

**When to use persistent mode:** If the agent builds dashboards or UIs that should survive reboots (e.g. a permanent status display), set `canvas.tmpfs = false`. The workspace then lives inside the kiosk user's home directory alongside the OpenClaw config.

**When to use tmpfs (default):** For ephemeral content like one-off visualizations, debugging output, or experiments. The workspace is automatically cleaned on every reboot.

## Telegram Channel

Telegram is handled by the **built-in OpenClaw channel** — no separate bridge service is needed. The gateway process connects to the Telegram Bot API directly. These NixOS options are proxied into the OpenClaw Home Manager config automatically.

### Quick Start

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Provision the token on the Pi: `./scripts/provision-telegram.sh [host]`
3. Enable in your NixOS config: `services.clawpi.telegram.enable = true;`
4. Deploy: `./scripts/deploy.sh openclaw-rpi5.local --specialisation kiosk`
5. Message the bot — it replies with a pairing code. Approve it:
   `./scripts/approve-telegram.sh <CODE> [host]`

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.telegram.enable` | bool | `false` | Enable the Telegram channel |
| `services.clawpi.telegram.tokenFile` | string | `/var/lib/clawpi/telegram-bot-token` | Path to the bot token file |
| `services.clawpi.telegram.allowFrom` | list of (string \| int) | `[]` | User/group IDs allowed to interact with the bot |
| `services.clawpi.telegram.requireMentionInGroups` | bool | `true` | Require @bot mention in group chats |
| `services.clawpi.telegram.streaming` | null \| bool \| enum | `null` | Streaming mode: `"off"`, `"partial"`, `"block"`, `"progress"` |
| `services.clawpi.telegram.replyToMode` | null \| enum | `null` | Reply handling: `"off"`, `"first"`, `"all"` |
| `services.clawpi.telegram.reactionLevel` | null \| enum | `null` | Reaction level: `"off"`, `"ack"`, `"minimal"`, `"extensive"` |

### Architecture

```
Phone (Telegram) → Telegram Bot API → OpenClaw Gateway (on Pi, port 18789) → Agent
                                       ↕
                                  Agent responds
```

The gateway handles Telegram natively as a channel — no separate bridge process. It uses long polling by default (no inbound ports needed).

## Audio Transcription

Speech-to-text via whisper.cpp for Telegram voice messages and future voice input.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.audio.enable` | bool | `false` | Enable audio transcription via whisper.cpp |
| `services.clawpi.audio.model` | enum | `"tiny"` | Whisper model size: `"tiny"` (fast, default), `"base"` (balanced), `"small"` (slow, best accuracy) |
| `services.clawpi.audio.language` | string | `"auto"` | Spoken language code (e.g. `"en"`, `"de"`) or `"auto"` for auto-detect |
| `services.clawpi.audio.timeoutSeconds` | int | `60` | Timeout in seconds for transcription |
| `services.clawpi.audio.groq.enable` | bool | `false` | Enable Groq cloud transcription (whisper-large-v3-turbo) with local fallback |
| `services.clawpi.audio.groq.apiKeyFile` | path | `/var/lib/clawpi/groq-api-key` | Path to Groq API key file. Provision with `./scripts/provision-groq.sh` |
| `services.clawpi.audio.groq.model` | string | `"whisper-large-v3-turbo"` | Groq transcription model |

When enabled, installs `whisper-cpp`, `ffmpeg`, and `file` utilities (plus `curl` when Groq is enabled). The gateway's `ExecStartPre` patches `openclaw.json` to configure the transcription wrapper. When Groq is enabled, the wrapper tries Groq API first and falls back to local whisper.cpp on failure.

## ElevenLabs TTS

High-quality text-to-speech via the ElevenLabs cloud API. When enabled, the `tts_hq` tool is registered in the clawpi-tools plugin.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.elevenlabs.enable` | bool | `false` | Enable the `tts_hq` tool (ElevenLabs cloud TTS) |
| `services.clawpi.elevenlabs.apiKeyFile` | path | `/var/lib/clawpi/elevenlabs-api-key` | Path to ElevenLabs API key. Provision with `./scripts/provision-elevenlabs.sh` |
| `services.clawpi.elevenlabs.voice` | string | `"eokb0hhuVX3JuAiUKucB"` | Default ElevenLabs voice ID |
| `services.clawpi.elevenlabs.model` | string | `"eleven_v3"` | Default ElevenLabs model ID |

## Overlay Daemon

The `clawpi` overlay daemon connects to the gateway and drives Eww status overlays (thinking, responding, tool use indicators). It runs as a Home Manager user service under the `kiosk` user, gated on `graphical-session.target`.

This service is not yet configurable via `services.clawpi` options — it is configured directly in `home/clawpi.nix` with environment variables:

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `CLAWPI_GATEWAY_URL` | `ws://localhost:18789` | Gateway WebSocket URL |
| `CLAWPI_EWW_CONFIG` | (set by Nix) | Path to bundled Eww config directory |
| `CLAWPI_WEB_ADDR` | `:3100` | Web server listen address |
| `OPENCLAW_GATEWAY_TOKEN` | (from env file) | Gateway auth token |
