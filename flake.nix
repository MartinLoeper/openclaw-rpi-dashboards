{
  description = "ClawPi — AI-powered smart display appliance for Raspberry Pi 5";

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    nix-openclaw.url = "github:MartinLoeper/nix-openclaw/main";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nix-openclaw/nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixos-raspberrypi, nix-openclaw, home-manager, ... }:
    let
      commonModules = [
        {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
          ];
        }
        {
          nixpkgs.overlays = [
            nix-openclaw.overlays.default
            (import ./overlays/openclaw-gateway-fix.nix)
            (import ./overlays/clawpi.nix)
          ];
        }
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.kiosk = {
            imports = [
              nix-openclaw.homeManagerModules.openclaw
              ./home/openclaw.nix
              ./home/clawpi.nix
            ];
            home.stateVersion = "25.05";
          };
        }
        ./modules/base.nix
        ./modules/kiosk.nix
      ];

      commonArgs = {
        specialArgs = { inherit nixos-raspberrypi; };
        modules = commonModules;
      };
    in
    {
      # For ongoing deploys via nixos-rebuild (./deploy.sh)
      nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystem commonArgs;

      # For building flashable SD images (./build.sh)
      nixosConfigurations.rpi5-installer = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = commonArgs.specialArgs;
        modules = commonArgs.modules ++ [
          nixos-raspberrypi.nixosModules.sd-image
          "${nixos-raspberrypi.inputs.nixpkgs}/nixos/modules/profiles/installation-device.nix"
          {
            boot.swraid.enable = nixos-raspberrypi.inputs.nixpkgs.lib.mkForce false;
            installer.cloneConfig = false;
          }
        ];
      };

      installerImages.rpi5 =
        self.nixosConfigurations.rpi5-installer.config.system.build.sdImage;
    };
}
