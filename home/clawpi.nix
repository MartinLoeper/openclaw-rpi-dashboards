{ pkgs, osConfig, lib, ... }:
let
  debugCfg = osConfig.services.clawpi.debug;
  canvasCfg = osConfig.services.clawpi.canvas;
  canvasDir = if canvasCfg.tmpfs then "/tmp/clawpi-canvas" else "/var/lib/kiosk/.openclaw/canvas";
in
{
  home.packages = [
    pkgs.clawpi
    pkgs.eww
    pkgs.grim  # Wayland screenshot tool (captures full compositor output incl. Eww overlays)
  ];

  # Eww daemon — runs independently, clawpi sends updates via the socket
  systemd.user.services.eww = {
    Unit = {
      Description = "Eww widget daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.eww}/bin/eww daemon --config ${pkgs.clawpi}/share/clawpi/eww --no-daemonize";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };

  systemd.user.services.clawpi = {
    Unit = {
      Description = "ClawPi overlay daemon";
      After = [
        "openclaw-gateway.service"
        "eww.service"
        "graphical-session.target"
      ];
      Wants = [
        "openclaw-gateway.service"
        "eww.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.clawpi}/bin/clawpi";
      Restart = "on-failure";
      RestartSec = "5s";
      EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
      Environment = [
        "CLAWPI_GATEWAY_URL=ws://localhost:18789"
        "CLAWPI_EWW_CONFIG=${pkgs.clawpi}/share/clawpi/eww"
        "CLAWPI_WEB_ADDR=:3100"
        "CLAWPI_CANVAS_DIR=${canvasDir}"
      ] ++ lib.optional debugCfg "CLAWPI_DEBUG=1";
    };
  };
}
