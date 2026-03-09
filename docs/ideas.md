# Ideas

## Seeded Agent Personality — ✅ Done

Implemented via `documents/AGENTS.md` which is injected into the agent's system prompt. Contains:
- Hardware identity (RPi 5B, display, audio, mic, browser mode)
- Audio device awareness (call `audio_status` early)
- Canvas workspace instructions (version control, archiving, static files only)
- Browser mode guidance (navigate, don't open new windows)

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

## README: Advertise NixOS + Remote Building

Highlight in the README that we use NixOS for fully reproducible deployments — the exact same system can be built from source by anyone, anywhere. Also advertise the Hetzner ARM remote build infrastructure:

- **NixOS reproducibility** — declarative config, no snowflake setups, rollback to any previous generation
- **Remote ARM builds** — avoid slow cross-compilation on x86_64 by offloading to native aarch64 Hetzner Cloud servers. A dedicated Claude skill (`hetzner-builder`) automates spinning up a build server, building, caching, and tearing down
- **Binary cache integration** — pre-built closures can be copied from the build server to the Pi in seconds

This is a real differentiator vs. Raspberry Pi projects that rely on manual `apt install` and can't reproduce their setup.

## README: Commercial Use Case / PoC Positioning

Position ClawPi as a proof of concept for a new generation of AI-powered smart assistant dashboards. The idea: sell touchscreen appliances to customers who want to build their own operational dashboards for SaaS software that exposes APIs to its data. Instead of building custom UIs, customers just talk to the display and the AI agent builds dashboards on the fly from the SaaS API.

Be upfront that Raspberry Pi hardware is great for prototyping but likely not the right choice for production IoT deployments (reliability, supply chain, enterprise support). We'll add links to proper production-grade hardware platforms (e.g. industrial ARM SBCs, thin clients) once we've evaluated options.

## Node Mode (Remote Gateway)

Currently ClawPi runs in **gateway mode** — the full OpenClaw gateway runs locally on the Pi and the device is self-contained. We could also support a **node mode** where the Pi acts as a thin node that connects to a remote gateway hosted elsewhere (e.g. a VPS on Hetzner/Hostinger, a Kubernetes cluster, a home server).

In node mode the Pi would only run:
- The kiosk browser (labwc + Chromium)
- The ClawPi overlay daemon (eww)
- The `clawpi-tools` plugin (audio, display control)
- A node agent that registers with the remote gateway over WebSocket

The gateway itself — including the AI model orchestration, session management, and channel integrations (Telegram, etc.) — would live on the remote server. This decouples compute from the display device, which enables:

- **Multiple displays, one brain** — several Pi nodes sharing a single gateway, each with its own browser and tools but coordinated by the same agent
- **Stronger hardware for the gateway** — run the gateway on a beefy server with GPU access for local models, while the Pi stays a lightweight display terminal
- **Cloud-hosted gateway** — run on managed infrastructure (k8s, Fly.io, Railway) with proper monitoring, scaling, and uptime guarantees
- **NAT traversal** — node connects outbound to the gateway, so the Pi doesn't need a public IP or port forwarding

**NixOS integration:** Expose as a `services.clawpi.mode` option (`"gateway"` | `"node"`) with a `services.clawpi.remoteGateway.url` for node mode. In gateway mode the config stays as-is. In node mode, skip the local gateway service and point the node agent at the remote URL.

## Local LLM Fallback (Offline Mode)

Support local LLM providers on the home network as a fallback when the internet is unavailable or as a privacy-first default. This would enable "offline" operation where no cloud inference service is needed.

**How it could work:**
- OpenClaw supports configurable model providers. Add a local provider pointing at an OpenAI-compatible API (e.g. Ollama, llama.cpp server, vLLM, LocalAI) running on a machine on the local network (home server, NAS, desktop GPU).
- Configure a provider chain: try Anthropic first, fall back to local if the API is unreachable or rate-limited.
- For fully offline use, set the local provider as the only provider — no internet dependency at all.

**Candidate local inference servers:**
- **Ollama** — easiest setup, supports many models, OpenAI-compatible API
- **llama.cpp server** — lightweight, runs on CPU or GPU, good for ARM (could even run small models on the Pi itself)
- **vLLM** — high-throughput GPU inference, good for a dedicated home server with a GPU
- **LocalAI** — drop-in OpenAI API replacement, supports multiple model backends

**Practical considerations:**
- The Pi 5 itself can run tiny models (e.g. Phi-3 mini, TinyLlama) via llama.cpp but quality will be limited. Better to offload to a more powerful machine on the LAN.
- Pairs well with **Node Mode** — the gateway runs on the beefy server with the GPU, the Pi is just a thin display terminal.
- TTS and STT already run locally (whisper.cpp, KittenTTS) — local LLM would complete the fully-offline stack.
- Network discovery: the local inference server could be discovered via mDNS/Avahi (e.g. `ollama.local:11434`).

**NixOS integration:** Add `services.clawpi.localLLM` options for the inference server URL and model name. Could also package Ollama as a NixOS service on the Pi or a companion machine.

## Project Name

~~Find a proper name for the project.~~ ✅ **Done** — the project is now called **ClawPi**.

## Reliable mDNS / Avahi

mDNS (`openclaw-rpi5.local`) is critical for a good UX — users shouldn't have to find or remember the Pi's IP address. Currently Avahi works most of the time but occasionally fails to resolve, forcing fallback to a raw IP. Investigate and fix:

- **Avahi service stability** — ensure `avahi-daemon` starts early and stays running across specialisation switches and reboots
- **Reflector / network config** — some routers or network setups block mDNS multicast; document known-good configurations
- **Fallback script logic** — `deploy.sh` and other scripts should retry mDNS a few times before failing, or auto-discover the IP via ARP/nmap as a fallback
- **Multiple interfaces** — if the Pi has both Ethernet and Wi-Fi, Avahi should advertise on all active interfaces

## Speech Bubble Overlay via Eww

Use [Eww](https://github.com/elkowar/eww) to overlay brief agent messages directly on screen in a speech bubble style — a lightweight alternative to TTS that costs fewer tokens. The agent writes short, direct status updates or responses to a file/socket, and an Eww widget renders them as a floating bubble on top of the kiosk browser. Cheaper and faster than generating audio, and works well on the small 10" display where brevity is key.

## Choice Picker Overlay via Eww

When the agent needs to disambiguate — multiple search results, several matching links, unclear intent — it should present a numbered/lettered choice list as an Eww overlay in the center of the screen. The user just says "2" or "B" to pick, no need to repeat the full option.

This should be shipped as a **default skill bundle** (or enableable via a NixOS option like `services.openclaw.skills.ui-tools = true`) that gives the agent a `show_choices` tool. The tool takes a list of options, renders the Eww widget, and returns the user's selection. The overlay should be large, readable from a distance, and auto-dismiss after selection or timeout.

Example flow:
1. User: "play that Zuckerberg hearing video"
2. Agent finds 3 matching YouTube results → calls `show_choices`
3. Eww overlay appears: `[1] Bad Lip Reading — "THE ZUCC" [2] Full Senate Hearing [3] Highlights Compilation`
4. User: "1"
5. Agent opens the selected video

This pattern generalizes to any multi-option scenario: "which Wi-Fi network?", "which dashboard?", "which file to send?", etc.

## OSD Overlays via Eww (Volume, Brightness)

Use Eww to show on-screen display (OSD) widgets when the agent adjusts hardware settings — a volume bar when changing speaker volume, a brightness indicator when adjusting the display, etc. Clean, minimal overlays that fade after a few seconds, like a TV remote OSD.

- **Speaker volume** — set a sane default volume (e.g. 50%) applied on every boot via a PipeWire/ALSA startup script. The agent can change volume via `wpctl set-volume` and the current level persists in a config file that the boot script reads. Show an Eww volume bar when changed.
- **Display brightness** — research whether HDMI-connected displays support brightness control at all (DDC/CI via `ddcutil`, or backlight sysfs for DSI panels). If supported, expose it the same way: sane boot default, agent-adjustable, OSD overlay.
- **Boot defaults** — store defaults in a simple file (e.g. `/var/lib/kiosk/.openclaw/hw-defaults.conf`) read by a oneshot systemd service at boot. The agent can update defaults so they survive reboots.

## Virtual Keyboard via Eww

Provide a button (Eww overlay) to open a virtual on-screen keyboard so the user can type directly into the agent's main session on the display. Use cases:

- **Voice fallback** — when STT isn't available, isn't accurate enough, or the environment is too noisy
- **Confidential input** — passwords, API keys, or private messages the user doesn't want to speak aloud
- **Precision** — URLs, code snippets, or exact strings that are hard to dictate

The keyboard widget should float over the kiosk browser, send keystrokes to the active OpenClaw chat session, and dismiss with a tap. Could reuse an existing Wayland virtual keyboard protocol or just POST text to the gateway WebSocket.

## Visual Awareness ("What am I seeing?")

Teach the agent to respond to questions like "what is that?" or "what am I seeing?" by taking a screenshot of the current open tab via CDP and describing what's on screen. This makes the agent visually aware of the display — it can explain dashboards, interpret charts, read error messages, or describe any content shown on the kiosk.

Contextual questions about visible content: "is there anything funny?" — agent snapshots the viewport, reads YouTube comments (or any text on screen), and gives a brief, opinionated summary. Works for any page: "summarize what's on screen", "explain this error", "what does this chart say?", "translate that". The agent becomes a real-time reading companion for the display.

Also enable voice-controlled page navigation: "go down", "scroll up", "click [link text]", "go back". The agent interprets these as browser actions via CDP — scrolling the viewport, clicking elements by their visible text, navigating history. If a command is ambiguous (e.g. multiple links matching "click settings"), the agent should ask the user which one they mean.

Natural language content requests: the agent should understand vague or conversational commands and figure out the right platform and action. Examples:

- "open the legendary Zuckerberg hearing from Bad Lip Reading" → search YouTube, find the video, open it in the browser
- "put on some lo-fi beats" → open a lo-fi YouTube stream or playlist
- "show me the weather" → open a weather dashboard or site for the user's location
- "what's on Hacker News?" → navigate to HN, summarize the front page

The agent uses its world knowledge to resolve what the user means, picks the right site (YouTube, Wikipedia, a news site, etc.), and navigates there via CDP — no need for the user to dictate URLs or platform names.

## Email Relay (send-only, restricted recipient)

Give the agent the ability to email the user — e.g. "email me a summary of this dashboard" or "send me that screenshot". Use `msmtp` (zero-daemon, NixOS-native) to relay through the user's Gmail account with a Gmail App Password.

**Recipient restriction:** msmtp has no built-in filtering, so wrap it with a script that only allows sending to the user's own email address. This prevents abuse if the Pi is compromised — the Gmail credentials can only reach one inbox.

**Security:** msmtp and the Gmail credentials must run under a separate system user (not `kiosk`), exposed to OpenClaw only via a localhost HTTP endpoint or socket. If msmtp ran as the kiosk user, the agent could read the App Password from the process or config file directly. The relay service validates the recipient and the agent only has access to a "send email" API — never the credentials.

**Custom skill with tools:** To make email a first-class agent capability, write a proper OpenClaw skill with a custom tool definition. The skill's `SKILL.md` frontmatter can define a `send_email` tool (with parameters like `subject`, `body`, `attachments`) that calls the relay HTTP endpoint under the hood. This way the agent doesn't need to manually construct `curl` commands — it just invokes the tool naturally. See [Creating Skills — Add Tools](https://docs.openclaw.ai/tools/creating-skills#3-add-tools-optional) for the tool definition format.

## Specialisation Selector (TUI)

Write a `scripts/spec-select.sh` script that lets the user pick the active NixOS specialisation (or base CLI mode) on the device using a nice TUI powered by [gum](https://github.com/charmbracelet/gum). The script SSHs into the Pi, lists available specialisations, presents a `gum choose` menu, activates the selected one via `switch-to-configuration`, and restarts the relevant services (Cage, gateway). This replaces the current manual `readlink -f` + `switch-to-configuration` dance with a single command.

## Browser Mode Switching

Give the agent a tool to restart the kiosk browser in different modes:

- **App mode** (current default) — `--app=URL`, no tabs, no address bar, cleanest look for dashboards and single-page content
- **Browse mode** — drop `--app`, launch with `--start-fullscreen` instead, giving the user a traditional browsing experience with tabs, address bar, and navigation controls

The agent should be able to switch modes on demand ("let me browse freely", "go back to kiosk mode") by restarting Cage with the appropriate Chromium flags. This could be a systemd override or a script that rewrites the Cage `ExecStart` and restarts the service. The mode switch should preserve the current URL so the user doesn't lose their place.

**Important:** In `--app` mode, the agent must use the browser `navigate` action (CDP `Page.navigate`) instead of `open` to change pages. Using `open` spawns a new browser window that stacks on top of the existing app window inside Cage, which is not recoverable without restarting. The seeded agent personality / system prompt should explicitly instruct: "You are in app mode — always navigate, never open new windows."

## Real Fullscreen in Chrome

The current `--kiosk` and `--start-fullscreen` flags don't fully eliminate window decorations inside Cage. Investigate proper fullscreen — possibly via Cage `-d` flag (already added), Chromium `--app` mode, or launching Chromium without a window manager entirely. Goal: zero chrome, zero borders, just content edge-to-edge.

## Dashboard & Diagram Design

Teach the agent to:
- **Datadog dashboards** — design and build monitoring dashboards via the Datadog UI in the kiosk browser, arranging widgets, setting queries, and configuring alerts visually.
- **Excalidraw diagrams** — draw architecture diagrams, flowcharts, and whiteboard sketches directly in Excalidraw running in the kiosk browser, using the browser tool to interact with the canvas.

## Text-to-Speech — ✅ Done

Implemented using ElevenLabs cloud TTS via the `tts_hq` plugin tool in `clawpi-tools`. The agent can speak through the Pi's HDMI audio output. Includes a stop button overlay (Eww) to cancel playback. Configured via `services.clawpi.elevenlabs`.

Local TTS (KittenTTS or Piper) remains an option for offline/low-latency use in the future.

## Audio I/O (Priority: STT first) — ✅ Partially Done

**Speech-to-text:** ✅ Implemented. Whisper.cpp runs locally on the Pi with Groq cloud fallback. Configured via `services.clawpi.audio`. See `docs/speech-to-text.md`.

**Hotword detection:** 🔧 In progress. openWakeWord packaged for NixOS, pipeline orchestrator written, NixOS module created. Needs custom "hey claw" model training and on-device testing. See `docs/voice-pipeline.md`.

**TTS:** ✅ Implemented. ElevenLabs cloud TTS via the `tts_hq` tool, with a stop button overlay (Eww). Configured via `services.clawpi.elevenlabs`.

## Audio Transcription Tool (`audio_transcribe`) — ✅ Done

Implemented as part of the OpenClaw gateway's `tools.media.audio` configuration. Audio transcription is handled by a whisper wrapper script that tries Groq cloud first (if enabled) and falls back to local whisper.cpp. Configured via `services.clawpi.audio` in `modules/clawpi.nix`, wired in `home/openclaw.nix`.

The voice pipeline (hotword → continuous STT) is a separate always-on input channel — see `docs/voice-pipeline.md`.

## File Transfer Channel

Build a small app that opens a channel on the local network between the Pi and the user's laptop, so the agent can easily send files to the user. Use cases:

- "Screenshot that dashboard and send it to me" — agent takes a browser screenshot via CDP and transfers it to the user's machine
- "Record the screen for 30 seconds" — agent captures a screen recording and pushes it over
- "Send me that error log" — agent grabs a file and transfers it

The user can then use these artifacts for social media posts, incident reports in Teams/Slack, documentation, etc. ## CLI Agent Interaction

Write a script to interact with the running OpenClaw agent from the workstation using our AI tooling (e.g. Claude Code). The `openclaw` CLI on the Pi supports `openclaw agent --agent main --message "..."` and `openclaw tui` for sending messages into sessions via the gateway WebSocket.

**Status:** Partially working. The `openclaw agent` command connects to the gateway but auth is tricky — the CLI expects `gateway.remote.token` in config to match the running gateway's token. First attempt also overwrote the config and generated a new `gateway.auth.token`, breaking the running gateway. Needs research into proper CLI→gateway auth flow without clobbering config.

**Simplest approach:** Spawn an SFTP server on the user's laptop pointing at a temp directory. SFTP is installed on most modern Linux distros out of the box, and tools like yazi have excellent SFTP integration for browsing transferred files. The agent on the Pi just `sftp put`s files to the laptop — no custom app needed.

## Display Power Control

Give the agent a tool to turn the connected display on and off (e.g. "turn off the screen", "wake up the display"). Use `wlr-randr` (available under Cage/Wayland) or DDC/CI via `ddcutil` to toggle DPMS / display power state. This enables energy saving, privacy ("blank the screen"), and scheduled display sleep/wake without physically touching the monitor.

- **Wayland route:** `wlr-randr --output <name> --off` / `--on` (Cage supports wlr-output-management)
- **DDC/CI route:** `ddcutil setvcp D6 4` (standby) / `ddcutil setvcp D6 1` (on) — works over HDMI if the monitor supports DDC
- **Expose as OpenClaw tool:** wrap in a skill with a `display_power` tool (`action: "on" | "off" | "toggle"`) so the agent can control it naturally
- **Schedule support:** combine with cron or systemd timers for automatic screen-off at night

## Cachix Binary Cache

Set up a [Cachix](https://www.cachix.org/) cache for the project so community users can pull pre-built aarch64 closures instead of building from source. Cross-compiling on x86_64 under QEMU is painfully slow, and not everyone can (or wants to) spin up a Hetzner ARM builder — even though it costs less than $1 for a full build, it still requires a Hetzner account and SSH setup.

- **CI integration** — push to Cachix from a GitHub Actions workflow on every merge to `master`. Use a native aarch64 runner (GitHub now offers `ubuntu-24.04-arm`) or cross-build with QEMU and cache the result.
- **Flake nixConfig** — add the Cachix cache to `extra-substituters` and `extra-trusted-public-keys` in `flake.nix` so users get cache hits automatically on `nix build` without any manual config.
- **README instructions** — document that builds are cached and should complete in minutes, not hours. This is a key selling point for community adoption: `nix build` just works, no ARM hardware or cloud accounts needed.
- **Cache scope** — cache the full system closure (`nixosConfigurations.rpi5`) and the SD image (`installerImages.rpi5`) so both deploy and first-install paths are fast.

## Developer Machine Prerequisites

~~Document the required setup on the developer's workstation.~~ **Done** — see `docs/getting-started.md`.

## Interaction Channels Overview

ClawPi supports multiple ways to interact with the agent, each suited to different situations:

| Channel | Location | Input | Best For |
|---------|----------|-------|----------|
| **Voice (hotword)** | At the display | Speak "hey claw" + command | Hands-free, quick commands while nearby |
| **PinchChat** | Laptop browser | Type in web UI | Extended sessions, copy-paste, comfortable typing |
| **Gateway direct** | Laptop browser | Type in gateway web UI | Developer access, no Docker needed |
| **Telegram** | Phone (mobile) | Text or voice messages | Remote control from anywhere, on the go |

### Voice (at the display)

The primary hands-free channel. Say the wake word ("hey claw"), speak your command, and the agent acts. See `docs/voice-pipeline.md` for the full design. Requires a USB microphone.

### PinchChat (laptop)

A webchat UI running in Docker on your workstation, connected to the gateway via SSH tunnel. Good for longer interactions where typing is more comfortable. See `docs/deployment.md` for setup.

### Gateway Web UI (laptop)

Open the gateway directly at `http://localhost:18789` (via SSH tunnel). No Docker required — just a browser. Gives full access to the agent session the kiosk display is also connected to.

### Telegram (mobile)

Send text or voice messages from your phone via a Telegram bot. The most convenient remote channel — no SSH, no local network, works from anywhere. Voice messages are transcribed on the Pi using whisper.cpp before being sent to the agent.

## Telegram Bot Integration — ✅ Done

Implemented using the built-in OpenClaw `channels.telegram` — no custom bridge needed. See `docs/telegram.md`.

Give the user a way to interact with the OpenClaw agent from their phone via a Telegram bot. This is the most convenient remote channel — no SSH tunnels, no laptop, just open Telegram and type (or send a voice message).

### Architecture

```
Phone (Telegram) → Telegram Bot API → telegram-bridge service (on Pi) → OpenClaw Gateway (localhost:18789)
                                                                      ↕
                                                              Agent responds
```

A small **telegram-bridge** service runs on the Pi as a systemd service. It polls the Telegram Bot API (long polling, no webhook needed — avoids exposing the Pi to the internet), receives messages, forwards them to the gateway WebSocket, and relays agent responses back to the Telegram chat.

### Setup Guide: Creating the Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts:
   - **Name:** e.g. `ClawPi Dashboard` (display name, can contain spaces)
   - **Username:** e.g. `clawpi_dashboard_bot` (must end in `bot`, globally unique)
3. BotFather returns a **bot token** — copy it (format: `123456789:ABCdef...`)
4. Optionally configure the bot via BotFather:
   - `/setdescription` — e.g. "AI dashboard assistant running on a Raspberry Pi"
   - `/setabouttext` — brief description shown on the bot's profile
   - `/setuserpic` — upload a ClawPi logo
   - `/setcommands` — register slash commands (e.g. `/screenshot`, `/status`)
5. **Get your chat ID:** Send any message to the bot, then open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser. Find your `chat.id` in the JSON response. This restricts the bot to only respond to you.

### NixOS Module Options

The Telegram bridge is configured via a dedicated NixOS module:

```nix
services.clawpi.telegram = {
  enable = true;

  # Bot token from BotFather (stored in a secrets file, not in the Nix store)
  tokenFile = "/var/lib/clawpi/telegram-bot-token";

  # Restrict to specific Telegram chat IDs (security: ignore messages from strangers)
  allowedChatIds = [ 123456789 ];

  # Gateway connection (defaults should work out of the box)
  gateway.url = "ws://localhost:18789";
  gateway.tokenFile = "/var/lib/kiosk/.openclaw/gateway-token.env";

  # Voice message transcription (uses whisper.cpp on the Pi)
  voice = {
    enable = true;
    # whisper model size: "tiny", "base", "small"
    model = "base";
  };
};
```

#### Option reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the Telegram bridge service |
| `tokenFile` | path | — | Path to a file containing the bot token (one line, no newline) |
| `allowedChatIds` | list of int | `[]` | Telegram chat IDs allowed to interact with the bot. Empty = reject all. |
| `gateway.url` | string | `"ws://localhost:18789"` | Gateway WebSocket URL |
| `gateway.tokenFile` | path | `"/var/lib/kiosk/.openclaw/gateway-token.env"` | Path to the gateway auth token file |
| `voice.enable` | bool | `false` | Transcribe incoming Telegram voice messages using whisper.cpp |
| `voice.model` | enum | `"base"` | Whisper model size (`"tiny"`, `"base"`, `"small"`) |

### Voice Message Support

When `voice.enable = true`, the bridge downloads incoming Telegram voice messages (`.ogg`), converts them to WAV via `ffmpeg`, and runs whisper.cpp to produce a text transcript. The transcript is then sent to the agent as a regular text message. This makes it easy to talk to the agent from your phone without typing — just hold the mic button in Telegram and speak.

The whisper model is shared with the voice pipeline module (see `docs/voice-pipeline.md`). If both are enabled, they use the same model files to avoid duplication.

### Security

- **Chat ID allowlist** — the bot ignores messages from any chat ID not in `allowedChatIds`. This is critical: without it, anyone who discovers the bot username can send commands to your agent.
- **Token as file** — the bot token is read from a file at runtime, not embedded in the Nix configuration. This keeps it out of the Nix store (which is world-readable).
- **No webhook** — long polling means the Pi doesn't need to be reachable from the internet. The bridge makes outbound HTTPS connections to the Telegram API only.

### Quick Start

```sh
# 1. Create the bot via @BotFather (see above) and note the token

# 2. Write the token to a file on the Pi
ssh nixos@openclaw-rpi5.local "echo '<bot-token>' | sudo tee /var/lib/clawpi/telegram-bot-token > /dev/null"

# 3. Add to your NixOS config and deploy
#    (set allowedChatIds to your Telegram chat ID)

# 4. Send a message to your bot — the agent responds!
```

## Documentation Site (Docusaurus)

Set up a proper documentation website using [Docusaurus](https://docusaurus.io/) (or a similar static site generator) so new users can get started quickly without reading raw Markdown files in the repo. The site should:

- **Getting started guide** — step-by-step from "I have a Pi" to "agent is running on my display", with screenshots
- **Architecture overview** — visual diagrams of how the pieces fit together (NixOS, OpenClaw, labwc, Chromium, Eww, plugins)
- **Tool reference** — auto-generated or manually maintained docs for all `clawpi-tools` plugin tools (parameters, return values, examples)
- **Configuration reference** — all NixOS module options, specialisations, and flake outputs explained
- **Deployment guide** — local build, remote ARM build (Hetzner), SD image flashing, OTA updates
- **Contributing** — how to add new tools, write skills, extend the kiosk, and submit PRs

Host on GitHub Pages (free, auto-deploys from a `docs` branch or `/docs` folder via GitHub Actions). The current `docs/` Markdown files can serve as the content source — Docusaurus can consume them with minimal restructuring.
