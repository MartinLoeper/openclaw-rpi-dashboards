{ pkgs, lib, config, ... }:
{
  options.services.clawpi.kiosk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the kiosk specialisation (labwc + greetd auto-login for kiosk user).
        Disable when importing the ClawPi module into an existing system that
        already has its own display manager / compositor.
      '';
    };
  };

  config = lib.mkIf config.services.clawpi.kiosk.enable {
    specialisation.kiosk.configuration = {
      programs.labwc.enable = true;

      # Chrome enterprise policies to disable translation
      programs.chromium = {
        enable = true;
        extraOpts = {
          # Disable translation feature completely
          TranslateEnabled = false;
        };
      };

      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${pkgs.labwc}/bin/labwc";
            user = "kiosk";
          };
          default_session = {
            command = "${pkgs.labwc}/bin/labwc";
            user = "kiosk";
          };
        };
      };
    };
  };
}
