# Product Vision

## Plug-and-Play AI Dashboard Appliance

A Raspberry Pi 5 with a 10" touchscreen display that serves as a self-contained AI dashboard appliance. No coding required — just plug in, power on, and talk.

## How It Works

1. **OpenClaw gateway** runs on the Pi as a systemd service, serving AI-generated dashboards on `localhost:18789`
2. **Kiosk mode** (Cage + Chromium) displays the dashboard fullscreen on the attached display
3. **Voice wake** ("openclaw", "claude", "computer") triggers on-demand dashboard creation via voice
4. **Talk mode** enables continuous voice conversation for refining and iterating on dashboards
5. **Claude Max** subscription powers the AI backend — no API keys to manage, just a subscription

## Architecture

```
┌─────────────────────────────────────┐
│          Raspberry Pi 5             │
│                                     │
│  ┌───────────┐    ┌──────────────┐  │
│  │   Cage    │───▶│  Chromium    │  │
│  │ (Wayland) │    │ (kiosk mode) │  │
│  └───────────┘    └──────┬───────┘  │
│                          │          │
│                   localhost:18789    │
│                          │          │
│                 ┌────────▼───────┐  │
│                 │   OpenClaw     │  │
│                 │   Gateway      │  │
│                 └────────────────┘  │
└─────────────────────────────────────┘
```

## Future Nodes

- **`voicewake`** — voice wake-word detection node that listens for trigger phrases and activates dashboard creation
- **`talk`** — continuous voice conversation node for refining dashboards through natural speech
