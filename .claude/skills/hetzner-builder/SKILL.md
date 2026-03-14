---
name: hetzner-builder
description: Spin up a native aarch64 build server on Hetzner Cloud to avoid slow cross-compilation from x86_64. Use when building the NixOS configuration takes too long locally, packages aren't in the binary cache, or you need a native ARM build.
user-invocable: true
---

# Hetzner ARM Builder

Spin up a native aarch64 build server on Hetzner Cloud to avoid slow cross-compilation from x86_64.

## When to use

- Building the NixOS configuration takes too long locally (cross-compiling aarch64 on x86_64)
- Packages aren't in the binary cache (e.g. from a different nixpkgs revision)
- You need a native ARM build for testing

## Create the server

```sh
hcloud server create \
  --name openclaw-builder \
  --type cax21 \
  --image ubuntu-24.04 \
  --location nbg1 \
  --ssh-key "<your-ssh-key-name>"
```

Server types for ARM (`cax` series):

| Type | vCPUs | RAM | Disk | Use case |
|------|-------|-----|------|----------|
| cax11 | 2 | 4 GB | 40 GB | Light builds |
| **cax21** | **4** | **8 GB** | **80 GB** | **Recommended for this project** |
| cax31 | 8 | 16 GB | 160 GB | Parallel builds |
| cax41 | 16 | 32 GB | 320 GB | Heavy builds |

## Set up the server

After the server is created, SSH in and install Nix:

```sh
# 1. Install Nix with daemon mode
ssh root@<server-ip> "curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes"

# 2. Enable flakes and add the RPi binary cache
ssh root@<server-ip> "bash -lc 'mkdir -p ~/.config/nix && echo \"experimental-features = nix-command flakes\" > ~/.config/nix/nix.conf'"
ssh root@<server-ip> "cat >> /etc/nix/nix.conf << 'EOF'
extra-substituters = https://nixos-raspberrypi.cachix.org
extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
EOF
systemctl restart nix-daemon"

# 3. Clone the repo
ssh root@<server-ip> "bash -lc 'git clone https://github.com/MartinLoeper/clawpi.git'"

# 4. Start the build in a tmux session (so it survives SSH disconnects)
#    Always pull latest changes before building!
ssh root@<server-ip> "bash -lc 'cd clawpi && git pull && tmux new-session -d -s build \"nix build .#nixosConfigurations.rpi5.config.system.build.toplevel --show-trace -L 2>&1 | tee /tmp/build.log\"'"
```

### Monitoring the build

When the user asks to stream or view build logs, suggest running this command in their terminal:

```sh
ssh root@<server-ip> "tail -f /tmp/build.log"
```

Other monitoring options:

```sh
# Check latest output (snapshot, not streaming)
ssh root@<server-ip> "tail -30 /tmp/build.log"

# Attach to the tmux session interactively
ssh -t root@<server-ip> "tmux attach -t build"
```

## Using the build server as a local cache

After the build completes on the server, copy the closure to your local store so `nixos-rebuild` can use it without rebuilding:

```sh
# Copy the full closure from the server (uses your SSH keys directly)
REMOTE_PATH="$(ssh root@<server-ip> readlink -f clawpi/result)"
nix copy --from "ssh://root@<server-ip>" "$REMOTE_PATH" --no-check-sigs
```

The deploy script supports this via `REMOTE_CACHE`:

```sh
REMOTE_CACHE=<server-ip> ./scripts/deploy.sh [host] --specialisation kiosk
```

**Note:** `ssh-ng://` substituters don't work because the nix daemon can't access user SSH keys. The deploy script uses `nix copy` instead, which runs as the user and has access to the SSH agent.

## Deploy from the server

After building on the server, copy the closure directly to the Pi:

```sh
# From the build server, copy to Pi
nix-copy-closure --to nixos@<pi-host> $(readlink -f result)

# Then activate on the Pi
ssh nixos@<pi-host> sudo $(readlink -f result)/bin/switch-to-configuration switch
```

## Server lifecycle management

Hetzner bills running servers by the hour. To save costs, **pause (power off) the server** when it is not actively being used for builds or as a remote build cache.

### Check server status

```sh
hcloud server list -o columns=name,status,ipv4
```

### Resume a stopped server

```sh
hcloud server poweron openclaw-builder
```

Wait for the server to come up before using it (takes ~10–30 seconds). Verify with:

```sh
ssh -o ConnectTimeout=5 root@<server-ip> echo ok
```

### Stop (pause) the server

```sh
hcloud server poweroff openclaw-builder
```

A stopped server retains its disk and IP but incurs no compute charges (only minimal storage cost).

### When to ask the user

After a build completes or a deploy finishes that used the server as a remote cache, **ask the user** whether they want to stop the server to save costs. Example prompt:

> The Hetzner build server is still running. Would you like me to stop it to save costs? You can resume it later when needed.

Do **not** stop or delete the server without confirmation — the user may want to keep it running for follow-up builds.

### Tear down (permanent)

If the server is no longer needed at all, delete it:

```sh
hcloud server delete openclaw-builder
```

Only suggest deletion if the user explicitly says they are done with the server for good.

## SSH key management

To grant someone access to the build server:

```sh
# 1. Generate a new SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/<name>-clawpi -C "<name>-clawpi" -N ""

# 2. Upload the public key to Hetzner (for future server creates)
hcloud ssh-key create --name <name>-clawpi --public-key-from-file ~/.ssh/<name>-clawpi.pub

# 3. Add the public key to a running server's authorized_keys
cat ~/.ssh/<name>-clawpi.pub | ssh root@<server-ip> "cat >> ~/.ssh/authorized_keys"
```

**Note:** Hetzner only injects SSH keys at server creation time. To add keys to an already running server, you must append them to `~/.ssh/authorized_keys` manually via SSH (step 3).

## Why this exists

The project uses two different nixpkgs revisions:
- `nixos-raspberrypi` uses a custom nixpkgs fork (with RPi-specific patches)
- `nix-openclaw` uses stock NixOS nixpkgs

Packages from `nix-openclaw`'s nixpkgs (like jemalloc, Node.js dependencies) aren't in the RPi binary cache, so they get built from source. On x86_64, this means slow cross-compilation under QEMU. On a native aarch64 server, these builds run at full speed.
