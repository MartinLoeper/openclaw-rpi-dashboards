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

> **Note:** If you are building on a native **aarch64** host (e.g. Apple Silicon with a Linux VM, a Hetzner ARM server, or another Raspberry Pi), no emulation is needed.

### Disk Space

Cross-compiled closures are large. Ensure at least **~20 GB free** in `/nix/store`.

### SSH

An SSH client is required for deploying to the Pi. `ssh-keygen` is used during initial key setup.

### Optional Tools

- **`bmaptool`** — for fast SD card flashing (see `scripts/flash-bmap.sh`)
- **Docker** — for running PinchChat and agent tools (file drop, email relay) on your workstation

## Initial Setup

### 1. Generate SSH Key

```sh
./scripts/setup-ssh.sh
```

This generates an Ed25519 key pair (`id_ed25519_rpi5` in the repo root, gitignored) and prints instructions for copying it to the Pi.

### 2. Flash the SD Card

Build the installer image:

```sh
nix build .#installerImages.rpi5 --show-trace -L
```

Flash it to the SD card:

```sh
# With bmaptool (faster):
./scripts/flash-bmap.sh /dev/sdX

# Or with dd:
./scripts/flash.sh /dev/sdX
```

### 3. First Boot

Insert the SD card, connect Ethernet, and power on the Pi. The system boots into CLI mode by default.

1. Copy your SSH key to the Pi:

   ```sh
   ssh-copy-id -i id_ed25519_rpi5 nixos@openclaw-rpi5.local
   ```

2. Deploy the kiosk specialisation:

   ```sh
   ./scripts/deploy.sh openclaw-rpi5.local --specialisation kiosk
   ```

3. Set up the agent API key (required for AI features):

   ```sh
   ./scripts/setup-agent-auth.sh openclaw-rpi5.local
   ```

4. Retrieve the gateway token:

   ```sh
   ./scripts/gateway-token.sh openclaw-rpi5.local
   ```

## Next Steps

- [Deployment](deployment.md) — ongoing deploy workflow, remote build cache, specialisation switching
- [OpenClaw Integration](openclaw.md) — gateway configuration, agent auth, useful commands
- [Hardware](hardware.md) — hardware components and setup
