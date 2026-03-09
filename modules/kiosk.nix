{ pkgs, ... }:
let
  waitForPipewire = pkgs.writeShellScript "wait-for-pipewire" ''
    uid=$(id -u kiosk)
    socket="/run/user/$uid/pipewire-0"
    for i in $(seq 1 30); do
      [ -e "$socket" ] && exit 0
      sleep 1
    done
    echo "Warning: PipeWire socket not found after 30s, continuing anyway"
  '';
in
{
  specialisation.kiosk.configuration = {
    systemd.services."cage-tty1".serviceConfig.ExecStartPre = [ waitForPipewire ];

    services.cage = {
      enable = true;
      user = "kiosk";
      extraArguments = [ "-d" ];
      program = "${pkgs.chromium}/bin/chromium --kiosk --start-fullscreen --no-first-run --disable-infobars --noerrdialogs --disable-session-crashed-bubble --disable-pinch --overscroll-history-navigation=0 --remote-debugging-port=9222 https://excalidraw.com";
      environment.NIXOS_OZONE_WL = "1";
    };
  };
}
