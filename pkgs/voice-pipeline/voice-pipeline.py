#!/usr/bin/env python3
"""
Voice pipeline orchestrator for ClawPi.

Captures audio from PipeWire, runs openWakeWord for hotword detection,
then records speech and sends it to the OpenClaw gateway for transcription
and agent processing.

Environment variables:
  CLAWPI_GATEWAY_URL     - WebSocket URL (default: ws://localhost:18789)
  OPENCLAW_GATEWAY_TOKEN - Gateway auth token (required)
  CLAWPI_WAKEWORD_MODEL  - Path to wake word .tflite model
  CLAWPI_WAKEWORD_THRESHOLD - Detection threshold 0.0-1.0 (default: 0.5)
  CLAWPI_SILENCE_TIMEOUT - Seconds of silence before stopping (default: 3.0)
  CLAWPI_MAX_RECORD_SECS - Max recording duration in seconds (default: 15)
  CLAWPI_WEB_URL         - ClawPi web server URL (default: http://localhost:3100)
  CLAWPI_DEBUG           - Enable debug logging (default: false)
"""

import asyncio
import json
import logging
import os
import signal
import struct
import subprocess
import sys
import tempfile
import time

import numpy as np
import openwakeword
from openwakeword.model import Model
import websockets

log = logging.getLogger("voice-pipeline")

# Audio parameters matching openWakeWord expectations
SAMPLE_RATE = 16000
CHANNELS = 1
CHUNK_SAMPLES = 1280  # 80ms chunks as recommended by openWakeWord


def get_config():
    return {
        "gateway_url": os.environ.get("CLAWPI_GATEWAY_URL", "ws://localhost:18789"),
        "gateway_token": os.environ.get("OPENCLAW_GATEWAY_TOKEN", ""),
        "wakeword_model": os.environ.get("CLAWPI_WAKEWORD_MODEL", ""),
        "threshold": float(os.environ.get("CLAWPI_WAKEWORD_THRESHOLD", "0.5")),
        "silence_timeout": float(os.environ.get("CLAWPI_SILENCE_TIMEOUT", "3.0")),
        "max_record_secs": float(os.environ.get("CLAWPI_MAX_RECORD_SECS", "15")),
        "web_url": os.environ.get("CLAWPI_WEB_URL", "http://localhost:3100"),
        "debug": os.environ.get("CLAWPI_DEBUG", "false").lower() in ("true", "1", "yes"),
    }


def rms_energy(audio_chunk):
    """Compute RMS energy of an int16 audio chunk."""
    if len(audio_chunk) == 0:
        return 0.0
    samples = np.frombuffer(audio_chunk, dtype=np.int16).astype(np.float32)
    return float(np.sqrt(np.mean(samples ** 2)))


class VoicePipeline:
    def __init__(self, cfg):
        self.cfg = cfg
        self.running = True
        self._oww_model = None

    def _init_wakeword(self):
        """Initialize openWakeWord model."""
        model_path = self.cfg["wakeword_model"]
        if model_path and os.path.isfile(model_path):
            log.info("loading wake word model: %s", model_path)
            self._oww_model = Model(
                wakeword_models=[model_path],
                inference_framework="tflite",
            )
        else:
            # Use bundled models (e.g. hey_jarvis)
            log.info("loading bundled wake word models")
            self._oww_model = Model(inference_framework="tflite")

        log.info("wake word models loaded: %s", list(self._oww_model.models.keys()))

    def _start_pw_record(self):
        """Start pw-record subprocess capturing raw s16le audio."""
        cmd = [
            "pw-record",
            "--format", "s16",
            "--rate", str(SAMPLE_RATE),
            "--channels", str(CHANNELS),
            "--target", "0",  # default source
            "-",  # stdout
        ]
        log.debug("starting: %s", " ".join(cmd))
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        return proc

    def _detect_wakeword(self, audio_int16):
        """Feed audio to openWakeWord model. Returns model name if triggered."""
        self._oww_model.predict(audio_int16)

        for model_name, scores in self._oww_model.prediction_buffer.items():
            if len(scores) > 0 and scores[-1] >= self.cfg["threshold"]:
                log.info("wake word detected: %s (score=%.3f)", model_name, scores[-1])
                self._oww_model.reset()
                return model_name
        return None

    def _record_speech(self, pw_proc):
        """Record speech until silence or max duration. Returns raw s16le bytes."""
        log.info("recording speech...")
        silence_timeout = self.cfg["silence_timeout"]
        max_bytes = int(self.cfg["max_record_secs"] * SAMPLE_RATE * 2)  # 2 bytes per s16 sample
        silence_threshold = 300  # RMS threshold for silence detection
        chunk_size = CHUNK_SAMPLES * 2  # bytes

        recorded = bytearray()
        last_voice_time = time.monotonic()

        while self.running:
            data = pw_proc.stdout.read(chunk_size)
            if not data:
                break

            recorded.extend(data)
            energy = rms_energy(data)

            if energy > silence_threshold:
                last_voice_time = time.monotonic()

            silence_duration = time.monotonic() - last_voice_time
            if silence_duration >= silence_timeout:
                log.info("silence detected (%.1fs), stopping recording", silence_duration)
                break

            if len(recorded) >= max_bytes:
                log.info("max recording duration reached (%.0fs)", self.cfg["max_record_secs"])
                break

        duration = len(recorded) / (SAMPLE_RATE * 2)
        log.info("recorded %.1fs of audio (%d bytes)", duration, len(recorded))
        return bytes(recorded)

    def _save_wav(self, raw_audio):
        """Save raw s16le audio to a temporary WAV file. Returns path."""
        import wave
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        with wave.open(tmp.name, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(raw_audio)
        return tmp.name

    async def _send_to_gateway(self, transcript):
        """Send transcript to OpenClaw gateway via WebSocket."""
        url = self.cfg["gateway_url"]
        token = self.cfg["gateway_token"]

        if not token:
            log.error("no gateway token configured, cannot send transcript")
            return False

        try:
            headers = {"Authorization": f"Bearer {token}"}
            async with websockets.connect(url, additional_headers=headers) as ws:
                message = {
                    "type": "user_message",
                    "content": transcript,
                    "source": "voice",
                }
                await ws.send(json.dumps(message))
                log.info("sent transcript to gateway: %s", transcript[:100])

                # Wait for ack
                try:
                    response = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    log.debug("gateway response: %s", response[:200] if response else "empty")
                except asyncio.TimeoutError:
                    log.warning("gateway did not ack within 5s")

                return True
        except Exception as e:
            log.error("failed to send to gateway: %s", e)
            return False

    def _notify_state(self, state):
        """Notify ClawPi web server of pipeline state via HTTP."""
        import urllib.request
        url = f"{self.cfg['web_url']}/api/voice/{state}"
        try:
            req = urllib.request.Request(url, method="POST", data=b"")
            urllib.request.urlopen(req, timeout=2)
        except Exception:
            pass  # best-effort

    def run(self):
        """Main pipeline loop."""
        self._init_wakeword()

        log.info("starting audio capture...")
        pw_proc = self._start_pw_record()
        if pw_proc.poll() is not None:
            log.error("pw-record failed to start")
            return 1

        chunk_size = CHUNK_SAMPLES * 2  # bytes per chunk
        log.info("voice pipeline ready — listening for wake word (threshold=%.2f)", self.cfg["threshold"])

        try:
            while self.running:
                data = pw_proc.stdout.read(chunk_size)
                if not data:
                    log.warning("pw-record stream ended")
                    break

                # Convert raw bytes to int16 numpy array for openWakeWord
                audio_int16 = np.frombuffer(data, dtype=np.int16)
                triggered = self._detect_wakeword(audio_int16)

                if triggered:
                    self._notify_state("listening")

                    # Record speech until silence
                    raw_audio = self._record_speech(pw_proc)

                    if len(raw_audio) < SAMPLE_RATE:  # less than 0.5s
                        log.info("recording too short, ignoring")
                        self._notify_state("idle")
                        continue

                    # Save to WAV for whisper-cli
                    wav_path = self._save_wav(raw_audio)
                    self._notify_state("transcribing")

                    try:
                        # Use the existing whisper transcription setup
                        # The CLAWPI_WHISPER_CMD env var points to the wrapper
                        whisper_cmd = os.environ.get("CLAWPI_WHISPER_CMD")
                        if whisper_cmd:
                            result = subprocess.run(
                                [whisper_cmd, wav_path],
                                capture_output=True,
                                text=True,
                                timeout=60,
                            )
                            transcript = result.stdout.strip()
                        else:
                            log.error("CLAWPI_WHISPER_CMD not set")
                            transcript = ""

                        if transcript:
                            log.info("transcript: %s", transcript)
                            asyncio.run(self._send_to_gateway(transcript))
                        else:
                            log.info("empty transcript, nothing to send")
                    except subprocess.TimeoutExpired:
                        log.error("whisper transcription timed out")
                    except Exception as e:
                        log.error("transcription failed: %s", e)
                    finally:
                        os.unlink(wav_path)
                        self._notify_state("idle")

        except KeyboardInterrupt:
            log.info("interrupted")
        finally:
            pw_proc.terminate()
            pw_proc.wait(timeout=5)
            log.info("voice pipeline stopped")

        return 0


def main():
    cfg = get_config()

    level = logging.DEBUG if cfg["debug"] else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
        stream=sys.stderr,
    )

    log.info("voice pipeline starting")
    log.info("gateway: %s", cfg["gateway_url"])
    log.info("threshold: %.2f, silence_timeout: %.1fs, max_record: %.0fs",
             cfg["threshold"], cfg["silence_timeout"], cfg["max_record_secs"])

    pipeline = VoicePipeline(cfg)

    def handle_signal(signum, frame):
        log.info("received signal %d", signum)
        pipeline.running = False

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    sys.exit(pipeline.run())


if __name__ == "__main__":
    main()
