# Ideas

## Seeded Agent Personality

Inject hardware-aware context into the agent's system prompt so it understands its physical environment and capabilities. Example:

> You are running on a Raspberry Pi 5B with a 10-inch display attached directly. You are able to control the Chromium browser which is opened in kiosk mode on it. Your job is to assist the user in controlling that browser — navigating pages, interacting with web apps, displaying dashboards, and anything else visible on the screen.

This makes the agent aware of its embodiment and encourages it to proactively use the browser tool rather than just answering questions abstractly.

## Attached Hardware

Describe peripherals connected to the Pi so the agent knows what it can interact with:

- **Display:** <!-- e.g. Waveshare 10.1" IPS, 1280x800, HDMI -->
- **Audio:** HDMI audio output via PipeWire
- **Camera:** <!-- e.g. RPi Camera Module v3 -->
- **Sensors:** <!-- e.g. BME280 temperature/humidity, PIR motion -->
- **GPIO devices:** <!-- e.g. relay module on GPIO 17, LED strip on GPIO 18 -->
- **USB devices:** <!-- e.g. USB microphone, Zigbee dongle -->

This inventory can be injected into the agent prompt alongside the personality so it knows what tools and peripherals are available beyond the browser.

## README Tagline

Add a catchy tagline to the README that sells the vision, something like:

> "How Amazon Alexa should have been designed — an open-source, AI-powered smart display that actually understands you."

Position the project as a truly intelligent home assistant: not a canned voice skill platform, but a real AI agent with eyes (display + browser), ears (mic), voice (speakers), and hands (GPIO/peripherals) — running on your own hardware with full control.

## Speech Bubble Overlay via Eww

Use [Eww](https://github.com/elkowar/eww) to overlay brief agent messages directly on screen in a speech bubble style — a lightweight alternative to TTS that costs fewer tokens. The agent writes short, direct status updates or responses to a file/socket, and an Eww widget renders them as a floating bubble on top of the kiosk browser. Cheaper and faster than generating audio, and works well on the small 10" display where brevity is key.

## Real Fullscreen in Chrome

The current `--kiosk` and `--start-fullscreen` flags don't fully eliminate window decorations inside Cage. Investigate proper fullscreen — possibly via Cage `-d` flag (already added), Chromium `--app` mode, or launching Chromium without a window manager entirely. Goal: zero chrome, zero borders, just content edge-to-edge.

## Dashboard & Diagram Design

Teach the agent to:
- **Datadog dashboards** — design and build monitoring dashboards via the Datadog UI in the kiosk browser, arranging widgets, setting queries, and configuring alerts visually.
- **Excalidraw diagrams** — draw architecture diagrams, flowcharts, and whiteboard sketches directly in Excalidraw running in the kiosk browser, using the browser tool to interact with the canvas.

## Audio I/O (Priority: STT first)

**Speech-to-text is the top priority.** The user is far more comfortable speaking aloud than typing, and can easily read agent responses on the display — so TTS is nice-to-have but not critical.

- **STT (high priority):** Run Whisper (or whisper.cpp for ARM efficiency) locally on the Pi to transcribe user speech into text for the agent. Needs a USB microphone and a wake-word or push-to-talk trigger.
- **Hotword detection (research needed):** Would be awesome to have an always-on wake word (e.g. "Hey OpenClaw") so the user can just speak without pressing a button. Needs research — running Whisper continuously on an RPi 5 may be too heavy. Alternatives: lightweight hotword engines like openWakeWord, Porcupine, or Snowboy for the trigger, then hand off to Whisper for the actual transcription.
- **TTS (lower priority):** Agent responses can be displayed on screen (via Eww overlay or browser). Audio output via PipeWire is available for when TTS is added later.
- Tools: `pw-record`/`pw-play`, whisper.cpp, browser Web Audio APIs.

## File Transfer Channel

Build a small app that opens a channel on the local network between the Pi and the user's laptop, so the agent can easily send files to the user. Use cases:

- "Screenshot that dashboard and send it to me" — agent takes a browser screenshot via CDP and transfers it to the user's machine
- "Record the screen for 30 seconds" — agent captures a screen recording and pushes it over
- "Send me that error log" — agent grabs a file and transfers it

The user can then use these artifacts for social media posts, incident reports in Teams/Slack, documentation, etc. Could be a simple HTTP file server on the Pi with mDNS discovery, or a WebSocket-based drop channel that pushes files to a lightweight client running on the laptop.
