# Speech-to-Text

## Current Implementation (whisper.cpp)

Local audio transcription using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) on the Pi. The gateway's media understanding subsystem reads `tools.media.audio.models` from the config and invokes whisper-cli for voice messages.

### How It Works

```
Telegram voice message → Gateway downloads .ogg → ffmpeg converts → whisper-cli transcribes → text fed to agent
```

The gateway passes the audio file path via `{{MediaPath}}` template substitution in the args. whisper-cli outputs the transcript to stdout (with `-np` for clean output).

### NixOS Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.clawpi.audio.enable` | bool | `false` | Enable audio transcription |
| `services.clawpi.audio.model` | enum | `"tiny"` | Whisper model: `tiny`, `base`, `small` |
| `services.clawpi.audio.language` | string | `"auto"` | Language code or `"auto"` |
| `services.clawpi.audio.timeoutSeconds` | int | `60` | Transcription timeout |

### Whisper Model Comparison

All models use the same architecture, scaled by parameter count. We use the multilingual variants (`ggml-<model>.bin`) to support `auto` language detection. English-only variants (`.en`) exist for tiny/base/small and are slightly better for English-only use.

| Model | Params | Download | RPi 5 Speed | RAM | Notes |
|-------|--------|----------|-------------|-----|-------|
| **tiny** | 39M | 75 MB | ~0.3x real-time | ~1 GB | **Default.** Fastest, good for voice commands |
| **base** | 74M | 142 MB | ~0.7x real-time | ~1 GB | Best balance of speed and accuracy |
| **small** | 244M | 466 MB | ~2-3x real-time | ~2 GB | Better multilingual accuracy |
| medium | 769M | 1.5 GB | ~5x real-time | ~3 GB | High accuracy, too slow for interactive use |
| large-v3 | 1.5B | 2.9 GB | Impractical | ~5 GB | Best accuracy, won't fit comfortably on 8 GB Pi |
| large-v3-turbo | 809M | 1.5 GB | ~5x real-time | ~3 GB | Large-v3 quality at medium size, still slow on Pi |

**Why `tiny`:** Prioritizes low latency for interactive Telegram voice messages. `tiny` is ~3x faster than real-time on the RPi 5, which means near-instant transcription. All models are multilingual (using `ggml-<model>.bin` variants) so `auto` language detection works with any model. If accuracy is insufficient, switch to `base` — the biggest quality jump is tiny → base.

Only `tiny`, `base`, and `small` are currently packaged in `pkgs/whisper-model.nix`. The larger models are feasible on the Pi (8 GB RAM) but impractical for interactive Telegram voice messages where response latency matters.

### Gateway Config (injected via ExecStartPre)

The typed Nix config schema doesn't expose `tools.media.audio.models`, so the config is patched at service start via `jq`. See `docs/workarounds.md` for details.

```json
{
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "language": "auto",
        "models": [
          {
            "type": "cli",
            "command": "/nix/store/...-whisper-transcribe",
            "args": ["{{MediaPath}}"],
            "timeoutSeconds": 60
          }
        ]
      }
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

A Groq API key is provisioned on the Pi at `/var/lib/clawpi/groq-api-key`. Once the nix-openclaw schema is updated to expose `tools.media.audio.models` as a typed option, Groq can be added as an alternative provider alongside or instead of local whisper.
