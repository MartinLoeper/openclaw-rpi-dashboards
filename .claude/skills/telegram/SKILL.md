---
name: telegram
description: Debug Telegram channel issues on the OpenClaw gateway — voice messages, media handling, message routing, and config. Use when troubleshooting Telegram bot behavior, voice transcription, or message delivery.
user-invocable: false
---

# Telegram Channel Internals

Reference for debugging Telegram channel issues on the OpenClaw gateway (version pinned at rev `addd290f`).

## Gateway Source Layout

The Telegram plugin is bundled in the gateway at:
```
/nix/store/...-openclaw-gateway-unstable-addd290f/lib/openclaw/dist/
├── plugin-sdk/dispatch-C3I0nvaq.js   # Main dispatch logic (Telegram, Discord, Slack, etc.)
├── channels/plugins/actions/telegram.js  # Telegram-specific actions (send, voice, stickers)
├── audio-preflight-BfYWWvUF.js       # Pre-mention audio transcription
├── audio-transcription-runner-BpLIe3GL.js  # CLI/API transcription runner
├── model-selection-ySxEKig3.js       # Config parsing, legacy migration
└── subsystem-B-oDv-jG.js            # Core subsystem (config validation, logging)
```

## Voice Message Flow

```
Telegram voice msg → resolveMediaFileRef(msg) [returns msg.voice]
  → resolveTelegramFileWithRetry(ctx) [calls getFile API]
  → downloadAndSaveTelegramFile() [fetches from api.telegram.org/file/bot<token>/<path>]
  → saveMediaBuffer() [saves to local temp file]
  → allMedia = [{ path, contentType, ... }]
  → buildTelegramMessageContext()
    → ctx.MediaPath = allMedia[0].path
    → ctx.MediaPaths = allMedia.map(m => m.path)
    → ctx.MediaTypes = allMedia.map(m => m.contentType)
  → Agent dispatch with media context
```

### Audio Preflight (Group + RequireMention only)

In group chats with `requireMention: true`, the gateway transcribes voice messages **before** checking for @mention — so voice commands work without typing the bot name:

```js
if (isGroup && requireMention && hasAudio && !hasUserText && mentionRegexes.length > 0 && !disableAudioPreflight) {
  transcribeFirstAudio({ ctx: { MediaPaths, MediaTypes }, cfg, ... })
}
```

### Audio Transcription Runner

`runAudioTranscription()` in `audio-transcription-runner-BpLIe3GL.js`:
1. Reads `cfg.tools.media.audio` for model config
2. Calls `normalizeAttachments(ctx)` to get `MediaPath`/`MediaPaths`
3. Finds first audio attachment via `isAudioAttachment()` (checks MIME or file extension)
4. For `type: "cli"` models: spawns the command with `{{MediaPath}}` template substitution
5. Returns `{ transcript }` from stdout

### Audio Detection

`isAudioAttachment()` checks:
1. MIME type via `kindFromMime()` — `audio/*` → "audio"
2. File extension via `isAudioFileName()` — `.ogg`, `.mp3`, `.m4a`, `.wav`, etc.

### Attachment Processing

`resolveMediaFileRef(msg)` returns the first match from:
```js
msg.photo?.[last] ?? msg.video ?? msg.video_note ?? msg.document ?? msg.audio ?? msg.voice
```

Non-image attachments go through `normalizeMediaAttachments()` which sets `MediaPath`/`MediaType` in the agent context. The attachment handler in `push-apns-*.js` drops non-image attachments — but that's for push notifications, not the main message pipeline.

## Config Schema

### Audio transcription (`tools.media.audio`)

```json
{
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "language": "auto",
        "models": [{
          "type": "cli",
          "command": "/path/to/whisper-cli",
          "args": ["-m", "/path/to/model.bin", "-l", "auto", "-np", "--no-gpu", "{{MediaPath}}"],
          "timeoutSeconds": 60
        }]
      }
    }
  }
}
```

Valid model entry fields: `type`, `command`, `args`, `timeoutSeconds`. No `id`, `provider`, or `capabilities` fields.

### Legacy migration

The gateway auto-migrates `routing.transcribeAudio` → `tools.media.audio.models` via `applyLegacyAudioTranscriptionModel()`. The `audio.transcription.command` field is separate and NOT used for voice message transcription.

## Debugging

### Enable verbose logging

Set `OPENCLAW_LOG_LEVEL=debug` in the gateway environment. In ClawPi, this is automatic when `services.clawpi.debug = true` (used by `rpi5-telegram-debug`).

Verbose logs show:
- `audio-preflight: transcribing attachment ...`
- `audio-preflight: transcribed N chars from attachment ...`
- `audio-preflight: transcription failed: ...`
- `telegram: getFile retry ...`
- `telegram: skipping sticker-only message ...`

### Log locations

- **Main log:** `/tmp/openclaw/openclaw-gateway.log`
- **Dated JSON log:** `/tmp/openclaw/openclaw-2026-MM-DD.log` (structured, more verbose)

### Common issues

- **"detected non-image, dropping"** — This is from the push notification attachment handler (`push-apns-*.js`), NOT the main message pipeline. Audio attachments are handled separately.
- **"Unrecognized key: id"** in `tools.media.models` — Stale config from a previous Groq attempt. Run `openclaw doctor --fix` or remove the offending key.
- **Voice messages not transcribed** — Check: (1) `tools.media.audio.enabled` is `true` in runtime config, (2) `models` array has entries, (3) whisper-cli binary exists at the configured path, (4) model file exists.
- **groupPolicy "allowlist" but allowFrom empty** — All group messages silently dropped. Set `allowFrom` or change to `"open"`.

### Useful grep patterns for the dated log

```sh
# Voice/audio processing
grep -i 'audio\|voice\|transcri\|whisper\|MediaPath' /tmp/openclaw/openclaw-2026-MM-DD.log

# Attachment handling
grep -i 'attachment\|media.*process\|download\|getFile' /tmp/openclaw/openclaw-2026-MM-DD.log

# Telegram message flow
grep 'telegram.*sendMessage\|telegram.*inbound\|telegram.*mention' /tmp/openclaw/openclaw-2026-MM-DD.log
```
