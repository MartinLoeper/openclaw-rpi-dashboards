# Changelog

## 0.10.2

- Show red "Recording..." overlay (top right) while `audio_transcribe` is recording
- Overlay hides when recording stops (before transcription begins)

## 0.10.1

- `audio_transcribe` now uses the shared whisper wrapper (Groq first, local whisper.cpp fallback)
- Removed `language` parameter — language is handled by the wrapper config
- Wrapper also handles format conversion (ffmpeg) automatically

## 0.10.0

- Add `canvas_folder` tool — get workspace path and usage instructions
- Add `canvas_open` tool — navigate kiosk browser to canvas content via CDP
- Add `canvas_close` tool — navigate back to landing page
- Add `canvas_archive` tool — archive current project with dedup naming
- Add `canvas_list_archive` tool — list all archived canvas projects
- Add `canvas_restore` tool — restore archived project with auto-archive of current

## 0.9.0

- Add `screen_record_start` tool — start Wayland screen recording via wf-recorder
- Add `screen_record_stop` tool — stop recording and return file path/size
- Only one recording at a time; start returns error if already recording
- Supports MP4/MKV/WebM containers and optional audio capture

## 0.8.0

- Add `tts_stop` tool — stop audio playback by killing pw-play
- `audio_play` now shows Eww stop button during playback and hides it when done
- Go backend: add `/api/tts/playing`, `/api/tts/stop`, `/api/tts/stopped` endpoints
- Eww: add `tts-stop-overlay` window with stop button in bottom-right corner

## 0.7.1

- Note in `tts_hq` description that the default voice speaks Schwäbisch

## 0.7.0

- Add `tts_hq_voices` tool — search and list ElevenLabs voices by name, type, or labels

## 0.6.1

- Add debug logging to `tts_hq` tool (request, response headers, errors) behind `OPENCLAW_LOG_LEVEL=debug`

## 0.6.0

- Add `tts_hq` tool — high-quality text-to-speech via ElevenLabs API
- Uses native fetch, no SDK dependency

## 0.5.2

- Add volume calibration note to `audio_play` description

## 0.5.1

- Steer agent to use `tts` + `audio_play` for voice responses
- Agent responds with speech when user says "tell me", "talk to me", etc.
- Support persistent "always speak" mode until user says stop

## 0.5.0

- Add `audio_play` tool — play audio files through speakers via `pw-play`
- Auto-converts MP3/OGG/FLAC to WAV via ffmpeg
- Integrates with built-in `tts` tool for spoken responses

## 0.4.0

- Add `audio_transcribe` tool — record + transcribe via whisper.cpp
- Reads whisper model/language config from gateway's `openclaw.json`
- Optional language override, auto-detect by default

## 0.3.2

- Make `audio_record` duration optional (default 5s), guide agent to ask user

## 0.3.1

- Fix `audio_record` SIGTERM handling (was erroring on kill)

## 0.3.0

- Add `audio_get_input_volume` — get default source (mic) volume
- Add `audio_set_input_volume` — set default source (mic) volume
- Add `audio_set_default_source` — switch default audio input by source ID
- Add `audio_record` — record from mic for N seconds via `pw-record`

## 0.2.1

- Fix `grim` not found: add Home Manager profile bin to plugin PATH

## 0.2.0

- Add `screenshot_display` tool — full Wayland compositor screenshot via grim
- Add `screenshot_browser` tool — browser viewport screenshot via CDP
- Split into file-per-category: `audio.ts`, `screenshot.ts`, `helpers.ts`

## 0.1.2

- Clean up debug logging, use canonical execute signature

## 0.1.0

- Initial release
- Add `audio_status` — list PipeWire sinks/sources
- Add `audio_get_volume` — get default sink volume
- Add `audio_set_volume` — set default sink volume
- Add `audio_test_tone` — play test sine wave via speaker-test
- Add `audio_set_default_sink` — switch default output by sink ID
