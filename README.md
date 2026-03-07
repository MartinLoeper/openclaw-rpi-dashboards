# openclaw-rpi-dashboards

A Raspberry Pi 5 + 10" touchscreen that acts as a voice-controlled AI dashboard appliance. Say "openclaw", describe what you want, and the [OpenClaw gateway](https://github.com/MartinLoeper/nix-openclaw) builds and displays it — no coding required.

1. **OpenClaw gateway** runs on the Pi, generating dashboards on `localhost:18789`
2. **Kiosk mode** (Cage + Chromium) shows them fullscreen on the wired display
3. **Voice wake** ("openclaw", "claude", "computer") triggers dashboard creation
4. **Talk mode** lets you refine dashboards through continuous conversation
5. **Claude Max** powers the AI — just a subscription, no API keys

See [docs/vision.md](docs/vision.md) for the full product vision and [docs/hardware.md](docs/hardware.md) for the hardware setup.

---

NixOS configuration built on [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

## Prerequisites

Your NixOS host needs aarch64 cross-compilation support:

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

## Initial Setup

### Build the SD image

```sh
./scripts/build.sh
```

### Flash to SD card

Use `flash-bmap.sh` (preferred) — it uses `bmaptool` which is significantly faster than a raw `dd`-style copy:

```sh
./scripts/flash-bmap.sh /dev/sdX
```

Alternatively, `flash.sh` uses [caligula](https://github.com/ifd3f/caligula) for an interactive flashing experience:

```sh
./scripts/flash.sh
```

### Boot the Pi

Insert the SD card and power on. The partition table expands automatically on first boot.

- **Hostname:** `openclaw-rpi5`
- **User:** `nixos` (wheel group, passwordless sudo)
- **SSH:** enabled, root login allowed

### Set a password

The `nixos` user has no password by default. On first boot, attach a keyboard and monitor and set one:

```sh
passwd nixos
```

You will need this password for the SSH key setup in the next step.

## Ongoing Deploys

### mDNS

The Pi runs Avahi and advertises itself as `openclaw-rpi5.local` on the local network. Your workstation also needs mDNS resolution enabled:

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
};
```

### Set up SSH authentication

Before the first deploy, set up key-based SSH auth:

```sh
./scripts/setup-ssh.sh                    # uses default host (openclaw-rpi5.local)
./scripts/setup-ssh.sh 192.168.1.42       # use a specific IP
```

This generates an ed25519 key pair in the repo directory (gitignored) and copies it to the Pi. You will be prompted for the password you set in the previous step.

### Deploy

After SSH is set up, update the running Pi remotely via `nixos-rebuild`:

```sh
./scripts/deploy.sh                       # deploys to openclaw-rpi5.local (mDNS)
./scripts/deploy.sh 192.168.1.42          # deploys to a specific IP
./scripts/deploy.sh myhost -- --dry-run   # pass extra nixos-rebuild flags
```

This builds the system locally and copies the closure to the Pi over SSH. The generational bootloader (`"kernel"`) supports rollback to previous configurations.

## Flake Structure

| Config | Builder | Purpose |
|--------|---------|---------|
| `nixosConfigurations.rpi5` | `nixosSystemFull` | Remote deploys via `nixos-rebuild` |
| `nixosConfigurations.rpi5-installer` | `nixosInstaller` | Flashable SD card images |

Both share the same system configuration. `nixosSystemFull` includes RPi-optimized package overlays (FFmpeg, Kodi, VLC, libcamera, etc.) globally.

The [OpenClaw gateway](https://github.com/MartinLoeper/nix-openclaw) runs as a systemd service (`openclaw-gateway.service`) on port 18789, serving AI-generated dashboards. It is included in both configurations via `commonModules`. See [docs/openclaw.md](docs/openclaw.md) for details.

### Kiosk Specialisation

A `kiosk` specialisation is available that launches Cage (Wayland kiosk compositor) + Chromium in fullscreen mode, auto-logged in as the `kiosk` system user. The base system remains CLI-only by default.

```sh
# Activate kiosk mode at runtime
sudo /run/current-system/specialisation/kiosk/bin/switch-to-configuration switch

# Return to CLI mode
sudo /run/current-system/bin/switch-to-configuration switch

# Deploy directly into kiosk mode
./scripts/deploy.sh -- --specialisation kiosk
```

See [docs/canvas.md](docs/canvas.md) for the full design rationale.

## Documentation

Additional design docs and integration guides live in [`docs/`](docs/).
