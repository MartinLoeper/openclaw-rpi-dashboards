# Telegram Channel

The OpenClaw gateway has built-in Telegram support — it connects to the Telegram Bot API directly, so no separate bridge service is needed. ClawPi exposes NixOS options under `services.clawpi.telegram` that are proxied into the gateway config.

## Setup

### 1. Create the Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts:
   - **Name:** e.g. `ClawPi Dashboard` (display name)
   - **Username:** e.g. `clawpi_dashboard_bot` (must end in `bot`, globally unique)
3. BotFather returns a **bot token** — copy it (format: `123456789:ABCdef...`)
4. Optionally configure via BotFather: `/setdescription`, `/setabouttext`, `/setuserpic`

### 2. Provision the Token

Run the provisioning script to write the token to the Pi:

```sh
./scripts/provision-telegram.sh [host]
```

This writes the token to `/var/lib/clawpi/telegram-bot-token` on the Pi with mode 600 (root-only readable). The token **never** enters the Nix store or NixOS configuration — it stays on disk as a runtime secret.

### 3. Get Your User ID

Message [@userinfobot](https://t.me/userinfobot) on Telegram — it replies with your user ID.

### 4. Enable in NixOS Config

```nix
services.clawpi.telegram = {
  enable = true;
  allowFrom = [ 123456789 ];  # your Telegram user ID
};
```

### 5. Deploy

```sh
./scripts/deploy.sh openclaw-rpi5.local --specialisation kiosk
```

### 6. Verify

```sh
# Check gateway logs (Telegram channel connects at startup)
ssh nixos@openclaw-rpi5.local sudo tail -50 /tmp/openclaw/openclaw-gateway.log
```

Send a message to your bot — the agent should respond!

## Group Chat Support

By default, `requireMentionInGroups` is `true` — the bot only responds when @mentioned in groups. To change this:

```nix
services.clawpi.telegram = {
  enable = true;
  allowFrom = [ 123456789 ];
  requireMentionInGroups = false;  # respond to all messages in groups
};
```

## Architecture

```
Phone (Telegram) → Telegram Bot API → OpenClaw Gateway (on Pi, port 18789) → Agent
                                       ↕
                                  Agent responds
```

The gateway handles Telegram as a native channel:
- **Polls** the Telegram Bot API via long polling (no webhook, no inbound ports needed)
- **Routes** messages to agents based on channel config (DMs, groups, topics)
- **Streams** responses back to Telegram as they're generated
- **Filters** by `allowFrom` — messages from unknown users are ignored

## Security

### Token as File, Not Config

The Telegram bot token is a secret that grants full control of the bot. It is:

- **Stored on disk** at `/var/lib/clawpi/telegram-bot-token` (mode 600)
- **Read by the gateway** at startup from the path specified in `tokenFile`
- **Never in the Nix store** — the config only contains the file path, not the token value

### User ID Allowlist

The `allowFrom` option restricts which Telegram users can interact with the bot. Messages from unrecognized user IDs are ignored.

### No Inbound Ports

Long polling means the Pi only makes outbound HTTPS connections to `api.telegram.org` — no inbound internet access is needed.

## Options Reference

See [docs/clawpi.md](clawpi.md#telegram-channel) for the full options table.

## Troubleshooting

```sh
# Check gateway logs for Telegram channel status
ssh nixos@<host> sudo tail -200 /tmp/openclaw/openclaw-gateway.log

# Look for Telegram-specific messages
ssh nixos@<host> sudo grep -i telegram /tmp/openclaw/openclaw-gateway.log

# Test the token manually
curl -s "https://api.telegram.org/bot<TOKEN>/getMe"

# Check if the gateway is running
ssh nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) systemctl --user status openclaw-gateway"
```
