{ pkgs, ... }:
{
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
}
