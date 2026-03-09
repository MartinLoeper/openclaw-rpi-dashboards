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

## README: Advertise NixOS + Remote Building

Highlight in the README that we use NixOS for fully reproducible deployments — the exact same system can be built from source by anyone, anywhere. Also advertise the Hetzner ARM remote build infrastructure:

- **NixOS reproducibility** — declarative config, no snowflake setups, rollback to any previous generation
- **Remote ARM builds** — avoid slow cross-compilation on x86_64 by offloading to native aarch64 Hetzner Cloud servers. A dedicated Claude skill (`hetzner-builder`) automates spinning up a build server, building, caching, and tearing down
- **Binary cache integration** — pre-built closures can be copied from the build server to the Pi in seconds

This is a real differentiator vs. Raspberry Pi projects that rely on manual `apt install` and can't reproduce their setup.

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
