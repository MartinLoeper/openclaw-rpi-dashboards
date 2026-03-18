{ pkgs, ... }: {
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [ "noatime" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=1min" ];
    };
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  users.users.kiosk = {
    isSystemUser = true;
    group = "kiosk";
    home = "/var/lib/kiosk";
    createHome = true;
    shell = pkgs.bash;
    extraGroups = [ "video" "audio" ];
    linger = true;
  };
  users.groups.kiosk = { };

  environment.systemPackages = with pkgs; [ openclaw-gateway sshpass vim jq ];

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  nix.settings.trusted-users = [ "nixos" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Create /tmp/openclaw for gateway log files (owned by kiosk user).
  # The openclaw-gateway service uses StandardOutput=append:/tmp/openclaw/...
  # and systemd opens the file before ExecStartPre, so the dir must exist early.
  systemd.tmpfiles.rules = [
    "d /tmp/openclaw 0755 kiosk kiosk -"
  ];

  # 1 GB swap file — critical for the 1 GB Pi 4B, helpful everywhere
  swapDevices = [{
    device = "/var/swapfile";
    size = 1024; # MiB
  }];

  security.rtkit.enable = true;

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}
