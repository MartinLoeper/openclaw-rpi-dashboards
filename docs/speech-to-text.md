# Speech-to-Text

## Current Implementation (whisper.cpp)

Local audio transcription using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) on the Pi. The gateway's media understanding subsystem reads `tools.media.models` from the config and invokes whisper-cli for voice messages.

### How It Works

```
Telegram voice message → Gateway downloads .ogg → ffmpeg converts → whisper-cli transcribes → text fed to agent
```

### NixOS Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.audio.enable` | bool | `false` | Enable audio transcription |
| `services.clawpi.audio.model` | enum | `"base"` | Whisper model: `tiny`, `base`, `small` |
| `services.clawpi.audio.language` | string | `"auto"` | Language code or `"auto"` |
| `services.clawpi.audio.timeoutSeconds` | int | `60` | Transcription timeout |

### Model Sizes (RPi 5)

| Model | Speed | RAM | Use case |
|-------|-------|-----|----------|
| `tiny` | ~0.3x real-time | ~1GB | Short commands |
| `base` | ~0.7x real-time | ~1GB | Commands + sentences (default) |
| `small` | ~2-3x real-time | ~2GB | Best accuracy, slow |

### Gateway Config (injected via ExecStartPre)

The typed Nix config schema doesn't expose `tools.media.models`, so the config is patched at service start via `jq`. See `docs/workarounds.md` for details.

```json
{
  "tools": {
    "media": {
      "audio": { "language": "auto" },
      "models": [
        {
          "type": "cli",
          "provider": "whisper.cpp",
          "id": "whisper-base",
          "command": "/nix/store/...-whisper-cpp/bin/whisper-cli",
          "args": ["-m", "/nix/store/...-ggml-base.bin", "-l", "auto", "-np", "--no-gpu"],
          "capabilities": ["audio"],
          "timeoutSeconds": 60
        }
      ]
    }
  }
}
```

### System Dependencies

When `audio.enable = true`, these packages are added:
- `whisper-cpp` — transcription engine
- `file` — MIME type detection (used by gateway)
- `ffmpeg-headless` — audio format conversion (Telegram sends .ogg/opus)

### Files

- `modules/clawpi.nix` — NixOS options + system packages
- `home/openclaw.nix` — ExecStartPre config patch + whisper model wiring
- `pkgs/whisper-model.nix` — fetches GGML model from HuggingFace
- `overlays/clawpi.nix` — exposes `whisper-model` package

## Future: Groq Cloud Transcription

A Groq API key is provisioned on the Pi at `/var/lib/clawpi/groq-api-key`. Once the nix-openclaw schema is updated to expose `tools.media.models` as a typed option, Groq can be added as an alternative provider alongside or instead of local whisper.
