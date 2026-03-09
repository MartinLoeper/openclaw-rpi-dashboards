# ClawPi Module Options

ClawPi extends the base NixOS configuration with custom services. Options are defined under `services.clawpi`.

## General

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.debug` | bool | `false` | Enable extra debugging tools (e.g. `speaker-test`) and verbose gateway logging (`OPENCLAW_VERBOSE=1`). Used by debug NixOS configurations (e.g. `rpi5-telegram-debug`). |

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
| `services.clawpi.audio.model` | enum | `"base"` | Whisper model size: `"tiny"` (fast, lower accuracy), `"base"` (balanced), `"small"` (slow, best accuracy) |
| `services.clawpi.audio.language` | string | `"auto"` | Spoken language code (e.g. `"en"`, `"de"`) or `"auto"` for auto-detect |
| `services.clawpi.audio.timeoutSeconds` | int | `60` | Timeout in seconds for transcription |

When enabled, installs `whisper-cpp`, `ffmpeg`, and `file` utilities. The gateway's `ExecStartPre` patches `openclaw.json` to configure the whisper-cli transcription model.

## Overlay Daemon

The `clawpi` overlay daemon connects to the gateway and drives Eww status overlays (thinking, responding, tool use indicators). It runs as a Home Manager user service under the `kiosk` user, gated on `graphical-session.target`.

This service is not yet configurable via `services.clawpi` options — it is configured directly in `home/clawpi.nix` with environment variables:

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `CLAWPI_GATEWAY_URL` | `ws://localhost:18789` | Gateway WebSocket URL |
| `CLAWPI_EWW_CONFIG` | (set by Nix) | Path to bundled Eww config directory |
| `CLAWPI_WEB_ADDR` | `:3100` | Web server listen address |
| `OPENCLAW_GATEWAY_TOKEN` | (from env file) | Gateway auth token |
