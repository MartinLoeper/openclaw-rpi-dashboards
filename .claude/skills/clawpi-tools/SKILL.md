---
name: clawpi-tools
description: Develop and extend the clawpi-tools OpenClaw plugin — add new agent tools for Pi hardware control, Eww overlays, display, and canvas. Use when the user wants to add, modify, or debug tools in pkgs/clawpi-tools/.
user-invocable: true
---

# ClawPi Tools Plugin Development

Guide for developing the `clawpi-tools` OpenClaw plugin that gives the agent typed tools for controlling the Pi's hardware and display.

## Project structure

```
pkgs/clawpi-tools/
├── openclaw.plugin.json   # Plugin manifest (id, version, config schema)
├── index.ts               # Tool registrations (loaded by gateway via jiti)
└── package.nix            # Nix derivation
```

**Wiring files:**
- `overlays/clawpi.nix` — adds `clawpi-tools` to the Nix package set
- `home/openclaw.nix` — configures `plugins.load.paths` and `plugins.entries`

## How tools work

The gateway loads `index.ts` at startup via jiti (TypeScript runtime — no build step needed). The exported function receives an `api` object and calls `api.registerTool()` for each tool. Tools are then available to the agent during conversations.

### Tool anatomy

```ts
import { Type } from "@sinclair/typebox";

api.registerTool({
  name: "tool_name",                    // unique identifier, used by the agent
  description: "What this tool does.",   // shown to the LLM
  parameters: Type.Object({             // JSON Schema via typebox
    param1: Type.String({ description: "..." }),
    param2: Type.Optional(Type.Number({ description: "...", minimum: 0 })),
  }),
  async execute(_id: string, params: { param1: string; param2?: number }) {
    // _id is a tool call ID (string like "http-123" or "agent-456")
    // params contains the validated parameters
    const result = await doSomething(params.param1);
    return { content: [{ type: "text", text: result }] };
  },
});
```

### Execute signature

```ts
async execute(_id: string, params: T) => { content: ContentBlock[] }
```

- `_id`: tool call ID (string) — usually ignored
- `params`: parsed parameters matching the JSON Schema
- Returns: `{ content: [{ type: "text", text: "..." }] }` — array of content blocks

This matches the built-in OpenClaw plugin convention (see voice-call plugin for reference at `/nix/store/.../openclaw/extensions/voice-call/index.ts` on the Pi).

### Parameter types (typebox)

```ts
Type.String({ description: "..." })
Type.Number({ description: "...", minimum: 0, maximum: 100 })
Type.Boolean({ description: "..." })
Type.Enum(MyEnum, { description: "..." })
Type.Optional(Type.String({ description: "..." }))  // optional param
Type.Union([Type.Literal("on"), Type.Literal("off")])
Type.Array(Type.String())
Type.Object({})  // no parameters
```

### Return values

```ts
// Simple text
return { content: [{ type: "text", text: "Done." }] };

// Multiple content blocks
return { content: [
  { type: "text", text: "Result:" },
  { type: "text", text: JSON.stringify(data, null, 2) },
] };
```

## Running system commands

The plugin includes a `run()` helper that executes commands with the correct NixOS PATH and `XDG_RUNTIME_DIR`:

```ts
const { stdout, stderr } = await run("wpctl", ["status"]);
```

**Important details:**
- The gateway runs as the `kiosk` user — commands execute as kiosk
- `XDG_RUNTIME_DIR` is set to `/run/user/<uid>` for PipeWire/Wayland access
- NixOS system PATH (`/run/current-system/sw/bin`) is prepended since the gateway's Node.js process may not inherit it
- Commands that need the Wayland display must also set `WAYLAND_DISPLAY=wayland-0`

### Adding new system commands

If a tool needs a binary that isn't in the system PATH:
1. Add the package to `home/clawpi.nix` (`home.packages`) or `modules/base.nix` (`environment.systemPackages`)
2. Use the full Nix store path if it's only needed by the plugin: `"/run/current-system/sw/bin/mybinary"`

### Wayland-aware commands

For tools that interact with the Wayland compositor (e.g. display control, screenshots):

```ts
async function runWayland(cmd: string, args: string[]) {
  return exec(cmd, args, {
    env: {
      ...process.env,
      PATH: SYSTEM_PATH,
      XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
      WAYLAND_DISPLAY: "wayland-0",
    },
  });
}
```

## Version bumping

**Every time you change `index.ts`**, bump the version in **both**:
1. `openclaw.plugin.json` — the `"version"` field
2. `package.nix` — the `version` attribute

This is required because Nix derives the store path from the version. Without bumping, the Pi will keep the old code.

## Deploy and test cycle

1. Edit `index.ts`
2. Bump version in `openclaw.plugin.json` and `package.nix`
3. `git add pkgs/clawpi-tools/` (Nix needs files tracked to see them)
4. Deploy: `FLAKE_ATTR=rpi5-telegram-debug ./scripts/deploy.sh 192.168.0.64 --specialisation kiosk`
5. Restart gateway: `ssh -i id_ed25519_rpi5 nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) systemctl --user restart openclaw-gateway.service"`
6. Verify plugin loaded: `ssh -i id_ed25519_rpi5 nixos@<host> "sudo -u kiosk XDG_RUNTIME_DIR=/run/user/\$(id -u kiosk) openclaw plugins list"`
7. Test parameterless tools via HTTP API, or test all tools by talking to the agent

### Quick HTTP test (parameterless tools only)

```sh
TOKEN=$(ssh -i id_ed25519_rpi5 nixos@<host> "sudo cat /var/lib/kiosk/.openclaw/gateway-token.env" | grep -oP 'OPENCLAW_GATEWAY_TOKEN=\K.*')
curl -s -X POST http://localhost:18789/tools/invoke \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tool":"<tool_name>","input":{}}'
```

**Limitation:** The HTTP `/tools/invoke` API does not forward parameters — params are always `{}`. Tools with parameters can only be tested by the agent in a conversation.

### Checking logs for errors

```sh
ssh -i id_ed25519_rpi5 nixos@<host> "grep -i 'error\|clawpi-tools' /tmp/openclaw/openclaw-gateway.log | tail -20"
```

## Tool ideas (from docs/ideas.md)

Planned tools to add to this plugin:

| Tool | Category | Description |
|------|----------|-------------|
| `display_power` | Display | Turn HDMI display on/off via wlr-randr or DDC/CI |
| `display_brightness` | Display | Adjust display brightness (if DDC/CI supported) |
| `show_choices` | Eww overlay | Present numbered choice list, return user selection |
| `show_message` | Eww overlay | Show speech bubble overlay with agent message |
| `show_osd` | Eww overlay | Show volume/brightness OSD bar |
| `browser_mode` | Browser | Switch between kiosk (--app) and browse (--start-fullscreen) mode |
| `screenshot` | Display | Take Wayland screenshot via grim |

## Existing tools (current)

| Tool | Parameters | Description |
|------|-----------|-------------|
| `audio_status` | none | List PipeWire sinks/sources via `wpctl status` |
| `audio_get_volume` | none | Get default sink volume |
| `audio_set_volume` | `level: number (0.0–1.0)` | Set default sink volume |
| `audio_test_tone` | `frequency?: number, duration?: number` | Play test sine wave |
| `audio_set_default_sink` | `sink_id: number` | Switch default output by ID |

## Gateway plugin config

The plugin is wired in `home/openclaw.nix`:

```nix
plugins = {
  enabled = true;
  allow = [ "clawpi-tools" ];
  load.paths = [
    "${pkgs.clawpi-tools}/lib/clawpi-tools"
  ];
  entries.clawpi-tools = {
    enabled = true;
    config = {};
  };
};
```

If new tools should be **optional** (not auto-available to the agent), register with `{ optional: true }` and add the tool name to `agents.list[].tools.allow` in the gateway config.

## Reference: built-in plugin source

The gateway's stock plugins are at this path on the Pi (useful for studying patterns):

```
/nix/store/<hash>-openclaw-gateway-unstable-<rev>/lib/openclaw/extensions/
```

Key references:
- `voice-call/index.ts` — best example of `registerTool` with typed params
- `memory-core/index.ts` — factory pattern, multiple tools from one registration
- `lobster/index.ts` — optional tool with sandbox check
