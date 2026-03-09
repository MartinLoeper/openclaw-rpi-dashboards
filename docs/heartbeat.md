# Heartbeat

The OpenClaw gateway runs a periodic heartbeat that triggers an agent turn at a fixed interval. This is useful for autonomous monitoring, scheduled tasks, or periodic status checks.

## Default Configuration

The gateway ships with a built-in default (no explicit config needed):

| Property | Default | Description |
|----------|---------|-------------|
| `enabled` | `true` | Heartbeat is on by default |
| `every` | `30m` | Fires every 30 minutes |
| `prompt` | See below | The message sent to the agent |
| `target` | `none` | Result is not forwarded to any channel (silent) |
| `ackMaxChars` | `300` | Max characters in the heartbeat acknowledgement |

Default prompt:

> Read HEARTBEAT.md if it exists (workspace context). Follow it strictly. Do not infer or repeat old tasks from prior chats. If nothing needs attention, reply HEARTBEAT_OK.

## HEARTBEAT.md

Place a `HEARTBEAT.md` file in the agent's workspace directory (`~/.openclaw/workspace/`) to give the agent instructions for each heartbeat turn. If the file doesn't exist, the agent simply replies `HEARTBEAT_OK`.

Example `HEARTBEAT.md`:

```markdown
# Heartbeat Tasks

- Check the current temperature and report if it exceeds 70°C.
- If there are unread Telegram messages older than 1 hour, summarize them.
```

## Target Channels

The `target` field controls where heartbeat results are delivered:

| Value | Behaviour |
|-------|-----------|
| `none` | Silent — agent runs but result is not sent anywhere |
| `telegram` | Result is sent to the Telegram channel |
| `all` | Result is broadcast to all configured channels |

With the default `target: none`, heartbeats run invisibly. Change it to `telegram` if you want the agent to proactively message you.

## Nix Configuration

The heartbeat is not currently exposed as a typed NixOS option. To customise it, add an `agents` block to the openclaw config in `home/openclaw.nix`:

```nix
programs.openclaw.config = {
  agents.main.heartbeat = {
    enabled = true;
    every = "15m";
    target = "telegram";
  };
  # ... rest of config
};
```

## Observing Heartbeats

Heartbeat events appear in the gateway log:

```sh
ssh nixos@<host> "grep heartbeat /tmp/openclaw/openclaw-gateway.log"
```

The health payload in WebSocket events also includes heartbeat timing:

```json
"heartbeat": {
  "enabled": true,
  "every": "30m",
  "everyMs": 1800000
}
```
