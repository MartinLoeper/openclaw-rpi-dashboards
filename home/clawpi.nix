{ pkgs, osConfig, lib, ... }:
let
  debugCfg = osConfig.services.clawpi.debug;
  canvasCfg = osConfig.services.clawpi.canvas;
  canvasDir = if canvasCfg.tmpfs then "/tmp/clawpi-canvas" else "/var/lib/kiosk/.openclaw/canvas";
  canvasArchiveDir = "/var/lib/kiosk/.openclaw/canvas-archive";
in
{
  home.packages = [
    pkgs.clawpi
    pkgs.quickshell
    pkgs.grim  # Wayland screenshot tool
  ];

  # Quickshell border animation — reads /run/user/1000/clawpi-state.json
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell border animation";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.quickshell}/bin/quickshell -p ${pkgs.clawpi}/share/clawpi/quickshell";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };

  systemd.user.services.clawpi = {
    Unit = {
      Description = "ClawPi overlay daemon";
      After = [
        "openclaw-gateway.service"
        "quickshell.service"
        "graphical-session.target"
      ];
      Wants = [
        "openclaw-gateway.service"
        "quickshell.service"
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
        "CLAWPI_STATE_FILE=/run/user/1000/clawpi-state.json"
        "CLAWPI_WEB_ADDR=:3100"
        "CLAWPI_CANVAS_DIR=${canvasDir}"
        "CLAWPI_CANVAS_ARCHIVE_DIR=${canvasArchiveDir}"
      ] ++ lib.optional debugCfg "CLAWPI_DEBUG=1";
    };
  };
}
