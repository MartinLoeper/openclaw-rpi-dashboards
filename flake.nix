{
  description = "Minimal bootable NixOS for Raspberry Pi 5";

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
  };

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixos-raspberrypi, ... }:
    let
      commonModules = [
        {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
          ];
        }
        ({ ... }: {
          boot.loader.raspberry-pi.bootloader = "kernel";

          networking.hostName = "openclaw-rpi5";

          users.users.nixos = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };

          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "yes";
          };

          security.sudo.wheelNeedsPassword = false;

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
