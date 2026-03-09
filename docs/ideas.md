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

## Dashboard & Diagram Design

Teach the agent to:
- **Datadog dashboards** — design and build monitoring dashboards via the Datadog UI in the kiosk browser, arranging widgets, setting queries, and configuring alerts visually.
- **Excalidraw diagrams** — draw architecture diagrams, flowcharts, and whiteboard sketches directly in Excalidraw running in the kiosk browser, using the browser tool to interact with the canvas.

## Audio I/O

Teach the agent to use the microphone and speakers attached to the Pi via PipeWire. This enables voice interaction, playing audio feedback, text-to-speech, or listening for voice commands. The agent should know how to use tools like `arecord`/`aplay`, `pw-play`/`pw-record`, or browser Web Audio APIs to capture and produce sound.
