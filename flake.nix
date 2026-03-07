{
  description = "Minimal bootable NixOS for Raspberry Pi 5";

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    nix-openclaw.url = "github:MartinLoeper/nix-openclaw/main";
  };

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixos-raspberrypi, nix-openclaw, ... }:
    let
      commonModules = [
        {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
          ];
        }
        nix-openclaw.nixosModules.openclaw-gateway
        {
          nixpkgs.overlays = [
            nix-openclaw.overlays.default
            (final: prev: {
              sdl3 = prev.sdl3.overrideAttrs (old: {
                doCheck = false;
              });
            })
          ];
          services.openclaw-gateway.enable = true;
        }
        ({ pkgs, ... }: {
          boot.loader.raspberry-pi.bootloader = "kernel";

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

          networking.hostName = "openclaw-rpi5";

          users.users.nixos = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };

          users.users.kiosk = {
            isSystemUser = true;
            group = "kiosk";
            home = "/var/lib/kiosk";
            createHome = true;
            extraGroups = [ "video" ];
          };
          users.groups.kiosk = { };

          hardware.graphics.enable = true;

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

          security.sudo.wheelNeedsPassword = false;

          specialisation.kiosk.configuration = {
            services.cage = {
              enable = true;
              user = "kiosk";
              program = "${pkgs.chromium}/bin/chromium --kiosk --no-first-run --disable-infobars --noerrdialogs --disable-session-crashed-bubble --disable-pinch --overscroll-history-navigation=0 http://localhost:18789";
              environment.NIXOS_OZONE_WL = "1";
            };
          };

          system.stateVersion = "25.05";
        })
      ];

      commonArgs = {
        specialArgs = { inherit nixos-raspberrypi; };
        modules = commonModules;
      };
    in
    {
      # For ongoing deploys via nixos-rebuild (./deploy.sh)
      nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystemFull commonArgs;

      # For building flashable SD images (./build.sh)
      nixosConfigurations.rpi5-installer = nixos-raspberrypi.lib.nixosInstaller commonArgs;

      installerImages.rpi5 =
        self.nixosConfigurations.rpi5-installer.config.system.build.sdImage;
    };
}
