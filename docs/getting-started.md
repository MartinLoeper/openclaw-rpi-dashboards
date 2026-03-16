# Getting Started

## Prerequisites

### Nix

A working [Nix](https://nixos.org/) installation with **flakes** enabled is the only hard requirement. This project has been tested on a NixOS build host, but any Linux distribution with the Nix package manager installed will work (including Ubuntu, Fedora, Arch, etc.).

Required Nix configuration (in `nix.conf` or via NixOS options):

```
experimental-features = nix-command flakes
```

### aarch64 Emulation (x86_64 hosts only)

If your build machine is **x86_64**, you need QEMU binfmt registration to cross-compile for the Pi's aarch64 architecture:

**NixOS:**

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

**Other distros:** install `qemu-user-static` and register aarch64 via binfmt_misc. See [NixOS Wiki — Cross Compiling](https://nixos.wiki/wiki/Cross_Compiling) for details.

> **Note:** If you are building on a native **aarch64** host (e.g. Apple Silicon with a Linux VM, a Hetzner ARM server, or another Raspberry Pi), no emulation is needed. Building on a Hetzner ARM server is recommended to avoid slow QEMU cross-compilation — see [Deployment](deployment.md) for details.

### Disk Space

Cross-compiled closures are large. Ensure at least **~20 GB free** in `/nix/store`.

### SSH

An SSH client is required for deploying to the Pi. `ssh-keygen` is used during initial key setup.

### mDNS Resolution

The Pi advertises itself via Avahi (`openclaw-rpi5.local` or `openclaw-rpi4.local`). Your workstation also needs mDNS resolution to find it:

**NixOS:**

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
};
```

**Other distros:** install `avahi-daemon` and `nss-mdns`, and add `mdns4_minimal [NOTFOUND=return]` to the `hosts` line in `/etc/nsswitch.conf`.

### Optional Tools

- **`bmaptool`** — for fast SD card flashing (see `scripts/flash-bmap.sh`)
- **Docker** — for running PinchChat and agent tools (file drop, email relay) on your workstation

## Initial Setup

### 1. Flash the SD Card

Build the installer image. Use `rpi5` for Raspberry Pi 5 or `rpi4` for Raspberry Pi 4B:

```sh
nix build .#installerImages.rpi5 --show-trace -L
# or for Pi 4B:
nix build .#installerImages.rpi4 --show-trace -L
```

Flash it to the SD card:

```sh
# With bmaptool (faster):
./scripts/flash-bmap.sh /dev/sdX

# Or with dd:
./scripts/flash.sh /dev/sdX
```

### 2. First Boot

Insert the SD card, connect Ethernet, and power on the Pi. The partition table expands automatically on first boot. The system boots into CLI mode by default.

| | Pi 5 | Pi 4B |
|---|---|---|
| **Hostname** | `openclaw-rpi5` | `openclaw-rpi4` |
| **User** | `nixos` (wheel, passwordless sudo) | `nixos` (wheel, passwordless sudo) |
| **SSH** | enabled, root login allowed | enabled, root login allowed |

Set a password for the `nixos` user (needed to copy the SSH key in the next step):

```sh
# On the Pi (attach a keyboard and monitor)
passwd nixos
```

### 3. Set Up SSH

Generate a deploy key and copy it to the Pi:

```sh
./scripts/setup-ssh.sh [hostname]
# e.g. ./scripts/setup-ssh.sh openclaw-rpi4.local
# defaults to openclaw-rpi5.local if omitted
```

This generates an Ed25519 key pair (`id_ed25519_rpi5` in the repo root, gitignored) and copies it to the Pi via `ssh-copy-id`. You will be prompted for the `nixos` password set in the previous step.

### 4. Deploy

Deploy the kiosk specialisation. Set `FLAKE_ATTR=rpi4` for a Pi 4B:

```sh
./scripts/deploy.sh openclaw-rpi5.local --specialisation kiosk
# or for Pi 4B:
FLAKE_ATTR=rpi4 ./scripts/deploy.sh openclaw-rpi4.local --specialisation kiosk
```

### 5. Set Up Agent Auth

```sh
./scripts/setup-agent-auth.sh openclaw-rpi5.local
```

### 6. Retrieve the Gateway Token

```sh
./scripts/gateway-token.sh openclaw-rpi5.local
```

## Next Steps

- [Deployment](deployment.md) — ongoing deploy workflow, remote build cache, specialisation switching
- [OpenClaw Integration](openclaw.md) — gateway configuration, agent auth, useful commands
- [Hardware](hardware.md) — hardware components and setup
