{ pkgs, ... }: {
  programs.openclaw = {
    enable = true;
    package = pkgs.openclaw-gateway;
    config = {
      gateway = {
        mode = "local";
      };
      browser = {
        attachOnly = true;
        defaultProfile = "kiosk";
        profiles = {
          kiosk = {
            cdpUrl = "http://127.0.0.1:9222";
            driver = "clawd";
            color = "#FF4500";
          };
        };
      };
    };
  };

  systemd.user.services.openclaw-gateway-token = {
    Unit.Description = "Generate OpenClaw gateway token";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "gen-openclaw-token" ''
        tokenFile="$HOME/.openclaw/gateway-token.env"
        mkdir -p "$HOME/.openclaw"
        if [ ! -f "$tokenFile" ]; then
          echo "OPENCLAW_GATEWAY_TOKEN=$(${pkgs.openssl}/bin/openssl rand -hex 32)" > "$tokenFile"
          chmod 600 "$tokenFile"
        fi
      '');
    };
  };

  systemd.user.services.openclaw-gateway = {
    Unit = {
      After = [ "openclaw-gateway-token.service" ];
      Requires = [ "openclaw-gateway-token.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service.EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
  };

  # The HM openclaw module generates the gateway unit without [Install],
  # so our Install.WantedBy above doesn't take effect. Work around by
  # creating a helper service that is properly enabled and starts the gateway.
  systemd.user.services.openclaw-gateway-start = {
    Unit = {
      Description = "Start OpenClaw gateway";
      Wants = [ "openclaw-gateway.service" ];
      After = [ "openclaw-gateway-token.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "start-openclaw-gateway" ''
        ${pkgs.systemd}/bin/systemctl --user start openclaw-gateway.service
      '');
    };
  };
}
