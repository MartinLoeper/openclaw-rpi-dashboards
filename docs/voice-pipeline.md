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
- **Delivery:** `deliver: true` — voice commands are forwarded to all connected channels (including Telegram), so the user sees the agent's response wherever they are

The agent receives the voice command as if the user typed it, and can respond with browser actions, Eww overlays, or any other tool.

## NixOS Integration

### Module: `modules/voice.nix`

```nix
services.clawpi.voice = {
  enable = true;

  # Path to a custom wake word .onnx model (null = bundled "hey jarvis")
  wakewordModel = ./models/hey_claw.onnx;

  # Detection threshold 0.0–1.0 (lower = more sensitive)
  threshold = 0.5;

  # Seconds of silence before stopping speech recording
  silenceTimeout = 3.0;

  # Maximum recording duration in seconds
  maxRecordSeconds = 15.0;
};
```

### Home Manager: `home/voice.nix`

The `clawpi-voice-pipeline` systemd user service runs after PipeWire and the gateway. It auto-restarts on failure. The gateway token is loaded from the same env file used by the gateway itself.

### File structure

| File | Purpose |
|------|---------|
| `pkgs/voice-pipeline/voice-pipeline.py` | Python orchestrator (PipeWire → openWakeWord → whisper → gateway) |
| `pkgs/voice-pipeline/package.nix` | Nix package wrapping the script with all dependencies |
| `pkgs/voice-pipeline/openwakeword.nix` | openWakeWord v0.6.0 package with pre-fetched models |
| `modules/voice.nix` | NixOS options (`services.clawpi.voice.*`) |
| `home/voice.nix` | Home Manager systemd user service |

### Hardware requirements

- **USB microphone** — any class-compliant USB mic works with PipeWire out of the box
- **Note:** The Pi's USB speaker bar mic (MZ-631M) works but has very low hardware gain (0–0.39dB range). Far-field pickup is poor — consider a dedicated USB mic with better gain.
- **Recommended:** ReSpeaker USB Mic Array (onboard VAD LED, good far-field pickup)

### Packaging plan

| Component | Status | Details |
|-----------|--------|---------|
| whisper.cpp | ✅ In nixpkgs | Used via `whisper-cpp` package |
| openWakeWord | ✅ Packaged | `pkgs/voice-pipeline/openwakeword.nix` (v0.6.0, wheel, pre-fetched models) |
| ONNX Runtime | ✅ In nixpkgs | Dependency of openWakeWord |
| ai-edge-litert | ❌ Removed | Not needed — ONNX Runtime handles all inference |
| Custom "hey claw" model | ❌ Not yet | Train + include as a static asset (see Training section) |

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

## Training a Custom Wake Word Model

The bundled "hey jarvis" model works out of the box. To train a custom "hey claw" model, use the Nix devShell and training scripts in `training/`.

### Training infrastructure

A dedicated Nix devShell provides all training dependencies with GPU acceleration via ROCm:

```sh
# Enter the training shell
nix develop .#training

# First-time setup: clones repos, downloads TTS model, training data (~3GB)
cd training && bash setup.sh

# Train the model (3 steps: generate → augment → train)
bash train.sh
```

**What the devShell provides (Nix):**
- PyTorch with ROCm GPU support (full GPU acceleration)
- torchaudio, torch-audiomentations, torchmetrics, torchinfo
- espeak-phonemizer (for Piper TTS phoneme generation)
- speechbrain, webrtcvad, soundfile
- scipy, scikit-learn, numpy, onnx, onnxruntime, pyyaml, tqdm

**Additional pip packages (installed locally by `setup.sh`):**
- `datasets<4` (HuggingFace datasets — pinned below v4 for soundfile audio backend)
- audiomentations, acoustics, pronouncing, deep-phonemizer

**Cloned repos (by `setup.sh`):**
- [dscripka/openWakeWord](https://github.com/dscripka/openWakeWord) — training scripts
- [dscripka/piper-sample-generator](https://github.com/dscripka/piper-sample-generator) — TTS fork with bundled `piper_train` VITS model code

**Training data (downloaded by `setup.sh`, ~17GB total):**
- MIT room impulse responses — 270 recordings for realistic reverb augmentation
- ESC-50 environmental sounds — 2000 clips for background noise mixing
- ACAV100M pre-computed features (~17GB, 2000 hours of negative data)
- Validation features (~185MB, ~11 hours, for false-positive rate estimation)
- Piper TTS model (`en-us-libritts-high.pt`, ~255MB) for synthetic speech generation

**Known issues / workarounds:**
- `torch.load` in piper-sample-generator needs `weights_only=False` for PyTorch ≥2.6 (patched automatically by setup)
- AudioSet on HuggingFace may return 404 — ESC-50 is used as background audio instead
- `torchcodec` fails to build with ROCm torch — `datasets<4` with soundfile backend is used instead

### Training config: `training/hey_claw.yml`

The config defines the "hey claw" target phrase with custom negative phrases to reduce false positives on similar-sounding words ("hey claude", "hey clock", "hey class", etc.). Key parameters:

| Parameter | Value | Description |
|-----------|-------|-------------|
| `n_samples` | 50,000 | Synthetic positive samples |
| `n_samples_val` | 5,000 | Validation samples |
| `augmentation_rounds` | 2 | Augmentation passes per sample |
| `steps` | 50,000 | Training iterations |
| `layer_size` | 32 | Model DNN layer size |
| `target_false_positives_per_hour` | 0.2 | Target FP rate |

### Training steps

The automated pipeline runs three sequential steps:

1. **Generate clips** — Piper TTS synthesizes "hey claw" in varied voices/accents, plus adversarial negatives. Uses GPU for faster generation.
2. **Augment clips** — Applies room impulse responses, background noise, pitch shifts, and reverb to make synthetic clips realistic.
3. **Train model** — Trains a small DNN on openWakeWord features with early stopping and checkpoint averaging. Outputs `.onnx` model file.

### Improving the model with real recordings

For better real-world accuracy, supplement synthetic data with real voice recordings:

- Record 50+ samples of "hey claw" from different speakers, distances (0.5–3m), and tones (normal, whisper, loud)
- Record in the actual deployment environment (ambient noise helps generalization)
- Place recordings in `training/data/real_positive/` as 16kHz mono WAV files
- The training pipeline can incorporate these alongside synthetic samples

### Deploying the model

After training, copy the output model and configure the NixOS option:

```nix
services.clawpi.voice = {
  enable = true;
  wakewordModel = ./training/output/hey_claw/hey_claw.onnx;
  threshold = 0.5;  # Tune: lower = more sensitive, higher = fewer false positives
};
```

Test locally first with a microphone:
```sh
python openwakeword/examples/detect_from_microphone.py --model_path output/hey_claw/hey_claw.onnx
```

## Implementation Phases

### Phase 1: Basic pipeline (MVP)
- [x] Package openWakeWord for NixOS (Python derivation)
- [ ] Train custom "hey claw" wake word model
- [x] Write pipeline orchestrator script
- [x] NixOS module with systemd service
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

1. **Mic recommendation:** The USB speaker bar mic (MZ-631M) has very low hardware gain (0–0.39dB). A dedicated USB mic with better gain would improve far-field detection. ReSpeaker USB Mic Array is a popular option.
2. **Wake word false positives:** Two-syllable "hey claw" should have a low false positive rate. If still too trigger-happy, "open claw" is an alternative.
3. **Concurrent resource usage:** whisper.cpp uses all 4 Cortex-A76 cores during transcription. Will this cause browser jank? May need to pin whisper to 2 cores via `taskset`.
4. **PipeWire routing:** Need to ensure the USB mic is the default capture device and doesn't conflict with browser audio playback.
