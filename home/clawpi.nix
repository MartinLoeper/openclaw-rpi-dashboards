{ pkgs, ... }: {
  home.packages = [
    pkgs.clawpi
    pkgs.eww
  ];

  systemd.user.services.clawpi = {
    Unit = {
      Description = "ClawPi overlay daemon";
      After = [
        "openclaw-gateway.service"
        "graphical-session.target"
      ];
      Wants = [ "openclaw-gateway.service" ];
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
      ];
    };
  };
}
