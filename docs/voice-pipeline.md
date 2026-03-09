# Voice Pipeline Design

## Overview

Always-on voice control for the OpenClaw smart display. The user says **"hey claw"**, the system wakes up, transcribes the spoken command, and feeds it to the OpenClaw agent.

```
USB Mic → PipeWire → openWakeWord ("hey claw") → whisper.cpp (transcribe) → OpenClaw Gateway
                                                                              │
                                                                        Agent acts
                                                                        (browser, tools, etc.)
```

## Components

### 1. Hotword Detection — openWakeWord

- **Engine:** [openWakeWord](https://github.com/dscripka/openWakeWord) (fully open-source, ONNX Runtime)
- **Wake word:** `hey claw` (custom-trained model)
- **Resource usage:** ~5% CPU, ~50MB RAM — runs continuously with negligible impact
- **Audio input:** PipeWire capture from USB microphone

**Why openWakeWord:**
- Fully open-source (Apache 2.0), no cloud dependency
- Supports custom wake word training with as few as ~50 positive samples
- ONNX Runtime runs natively on aarch64
- Active maintenance and good community (Home Assistant / Rhasspy ecosystem)

**Custom model training:**
1. Record ~50 samples of "hey claw" (various speakers, distances, tones)
2. Use openWakeWord's training pipeline (runs on x86_64, produces a small `.onnx` model)
3. Deploy the `.onnx` file to the Pi as part of the NixOS configuration
4. Synthetic augmentation (noise, reverb, pitch shift) is applied automatically during training

### 2. Speech-to-Text — whisper.cpp

- **Engine:** [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (C/C++, ARM NEON optimized)
- **Model:** `base` with INT8 quantization (~1GB RAM, near real-time on RPi 5)
- **Trigger:** only runs after wake word detection (not continuously)
- **Timeout:** stop recording after 5s of silence (configurable)

**Expected performance on RPi 5 (8GB):**

| Model   | Real-time factor | RAM   | Accuracy |
|---------|-----------------|-------|----------|
| `tiny`  | ~0.3x (fast)    | ~1GB  | Good for short commands |
| `base`  | ~0.7x (near RT) | ~1GB  | Good balance for commands + sentences |
| `small` | ~2-3x (slow)    | ~2GB  | Better accuracy, too slow for interactive use |

Start with `base` quantized. Fall back to `tiny` if latency is unacceptable.

### 3. Audio Feedback

Provide clear audio cues so the user knows the system heard them:

- **Wake sound:** short chime when "hey claw" is detected (confirms listening)
- **Done sound:** brief tone when transcription completes and command is sent
- **Error sound:** different tone if transcription fails or times out

Play via PipeWire (`pw-play`) — HDMI audio is already configured.

### 4. Gateway Integration

Once whisper.cpp produces a transcript, send it to the OpenClaw gateway as a user message:

- **Transport:** WebSocket to `localhost:18789` (same as the browser UI)
- **Auth:** use the gateway token from `/var/lib/kiosk/.openclaw`
- **Session:** reuse the active kiosk agent session (same session the browser is connected to)

The agent receives the voice command as if the user typed it, and can respond with browser actions, Eww overlays, or any other tool.

## NixOS Integration

### New module: `modules/voice.nix`

```nix
# Conceptual structure — not final Nix code
{
  # System packages
  environment.systemPackages = [
    whisper-cpp          # pkgs.openai-whisper-cpp
    # openWakeWord       # custom derivation (Python + ONNX Runtime)
  ];

  # Voice pipeline service (runs as kiosk user)
  systemd.user.services.voice-pipeline = {
    description = "OpenClaw voice pipeline (hotword + STT)";
    after = [ "pipewire.service" "openclaw-gateway.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "...";  # Python script orchestrating the pipeline
      Restart = "always";
    };
  };
}
```

### Hardware requirements

- **USB microphone** — any class-compliant USB mic works with PipeWire out of the box
- **Recommended:** ReSpeaker USB Mic Array (has onboard VAD LED, good far-field pickup)
- The mic should be listed in `modules/base.nix` hardware description / agent personality

### Packaging plan

| Component | Nixpkgs status | Action needed |
|-----------|---------------|---------------|
| whisper.cpp | In nixpkgs (`openai-whisper-cpp`) | Use directly |
| openWakeWord | Not in nixpkgs | Package as flake input or `python3.withPackages` derivation |
| ONNX Runtime | In nixpkgs (`onnxruntime`) | Dependency of openWakeWord |
| Custom "hey claw" model | N/A | Train + include as a static asset in the flake |

## Pipeline Orchestrator

A Python script (`voice-pipeline.py`) ties everything together:

```
1. Initialize PipeWire capture stream
2. Load openWakeWord with "hey claw" model
3. Loop:
   a. Feed audio chunks to openWakeWord
   b. On "hey claw" detection:
      - Play wake chime
      - Start recording to buffer
      - Run whisper.cpp on buffered audio (stop on silence timeout)
      - Send transcript to gateway WebSocket
      - Play done/error sound
   c. Continue listening for next "hey claw"
```

**Silence detection:** Use Silero VAD or simple RMS energy threshold to detect end-of-speech. This avoids running whisper.cpp on silence and gives a natural "I'm done talking" boundary.

## Implementation Phases

### Phase 1: Basic pipeline (MVP)
- [ ] Package openWakeWord for NixOS (Python derivation)
- [ ] Train custom "hey claw" wake word model
- [ ] Write pipeline orchestrator script
- [ ] NixOS module with systemd service
- [ ] Test with USB mic on RPi 5

### Phase 2: Polish
- [ ] Audio feedback (wake/done/error chimes)
- [ ] Silence detection via Silero VAD
- [ ] Eww overlay showing listening state (mic icon / waveform)
- [ ] Configurable whisper model size via NixOS option
- [ ] Noise suppression (PipeWire filter chain or RNNoise)

### Phase 3: Advanced
- [ ] "Talk mode" — continuous conversation without re-triggering wake word
- [ ] Multi-wake-word support ("hey claw", "computer", custom)
- [ ] Speaker identification (who is talking?)
- [ ] Interrupt support — say "claw stop" to cancel an in-progress action
- [ ] TTS responses via Piper (local, fast, aarch64-native)

## Open Questions

1. **Mic recommendation:** Which USB mic gives the best far-field performance for the price? ReSpeaker is popular but there may be better options.
2. **Wake word false positives:** Two-syllable "hey claw" should have a low false positive rate. If still too trigger-happy, "open claw" is an alternative.
3. **Concurrent resource usage:** whisper.cpp uses all 4 Cortex-A76 cores during transcription. Will this cause browser jank? May need to pin whisper to 2 cores via `taskset`.
4. **PipeWire routing:** Need to ensure the USB mic is the default capture device and doesn't conflict with browser audio playback.
