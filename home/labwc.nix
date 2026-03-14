{ pkgs, ... }: {
  xdg.configFile."labwc/autostart" = {
    executable = true;
    text = ''
      # Export WAYLAND_DISPLAY so user services can connect to the compositor
      systemctl --user import-environment WAYLAND_DISPLAY

      # Start the graphical session marker service, which pulls in
      # graphical-session.target and all services that depend on it
      systemctl --user start labwc-session.service

      # Wait for PipeWire socket (HDMI audio)
      socket="/run/user/$(id -u)/pipewire-0"
      for i in $(seq 1 30); do
        [ -e "$socket" ] && break
        sleep 1
      done

      # Chromium kiosk pointing at ClawPi landing page
      ${pkgs.chromium}/bin/chromium \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-session-crashed-bubble \
        --overscroll-history-navigation=1 \
        --remote-debugging-port=9222 \
        --touch-events=enabled \
        --enable-features=TouchpadOverscrollHistoryNavigation \
        --disable-features=Translate \
        http://localhost:3100 &
    '';
  };

  # Marker service that binds to graphical-session.target.
  # Starting this service activates the target (bypasses RefuseManualStart).
  systemd.user.services.labwc-session = {
    Unit = {
      Description = "labwc graphical session";
      BindsTo = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };

  xdg.configFile."labwc/rc.xml".text = ''
    <?xml version="1.0"?>
    <labwc_config>
      <core>
        <gap>0</gap>
      </core>
      <windowRules>
        <windowRule identifier="chromium" matchOnce="true">
          <action name="Maximize" />
          <action name="ToggleDecoration" />
        </windowRule>
      </windowRules>
    </labwc_config>
  '';

  xdg.configFile."labwc/environment".text = ''
    NIXOS_OZONE_WL=1
  '';
}
