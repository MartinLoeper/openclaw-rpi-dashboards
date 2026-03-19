{ pkgs, lib, ... }: {
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

  hardware.graphics.enable = lib.mkDefault true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  services.avahi = {
    enable = lib.mkDefault true;
    nssmdns4 = lib.mkDefault true;
    publish = {
      enable = lib.mkDefault true;
      addresses = lib.mkDefault true;
    };
  };

  # Create /tmp/openclaw for gateway log files (owned by kiosk user).
  # The openclaw-gateway service uses StandardOutput=append:/tmp/openclaw/...
  # and systemd opens the file before ExecStartPre, so the dir must exist early.
  systemd.tmpfiles.rules = [
    "d /tmp/openclaw 0755 kiosk kiosk -"
  ];

  security.rtkit.enable = true;

  system.stateVersion = lib.mkDefault "25.05";
}
