{ pkgs, ... }: {
  programs.openclaw = {
    enable = true;
    excludeTools = [ "uv" ];
    config = {
      gateway = {
        mode = "local";
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
    Service = {
      EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
      ExecStartPre = toString (pkgs.writeShellScript "ensure-openclaw-log-dir" ''
        mkdir -p /tmp/openclaw
      '');
    };
  };
}
