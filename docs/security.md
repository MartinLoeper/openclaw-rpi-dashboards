# Security

## Secrets Management

**Credentials must never be stored in the NixOS configuration or the Nix store.** The Nix store is world-readable — any value embedded in a `.nix` file or interpolated into a derivation is visible to all users on the system.

### How We Handle Secrets

All secrets (API tokens, auth keys) are:

1. **Stored on disk** in files with restrictive permissions (mode 600)
2. **Loaded at runtime** by services via `EnvironmentFile` or `tokenFile` config options
3. **Referenced by path** in config (e.g. `tokenFile = "/var/lib/clawpi/telegram-bot-token"`)

The config only contains the *path* to the secret file, never the secret value itself.

### Provisioning Scripts

Use the scripts in `scripts/` to write secrets to the Pi:

| Secret | Script | Destination |
|--------|--------|-------------|
| Telegram bot token | `scripts/provision-telegram.sh` | `/var/lib/clawpi/telegram-bot-token` |
| Gateway token | Auto-generated on first boot | `/var/lib/kiosk/.openclaw/gateway-token.env` |

### Anti-Patterns (Don't Do This)

```nix
# BAD: Token in the Nix store (world-readable!)
channels.telegram.tokenFile = "123456789:ABCdef...";  # this is the token, not a file path!

# GOOD: Path to a file containing the token
channels.telegram.tokenFile = "/var/lib/clawpi/telegram-bot-token";
```
