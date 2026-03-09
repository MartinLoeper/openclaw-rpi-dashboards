{ pkgs, osConfig, lib, ... }:
let
  audioCfg = osConfig.services.clawpi.audio;
  debugCfg = osConfig.services.clawpi.debug;
  tgCfg = osConfig.services.clawpi.telegram;

  whisperModel = pkgs.whisper-model.override { model = audioCfg.model; };

  # JSON snippet to inject tools.media config for whisper-cli transcription.
  # The typed Nix config schema doesn't expose tools.media.models, so we
  # patch openclaw.json via ExecStartPre before the gateway reads it.
  whisperMediaConfig = builtins.toJSON {
    tools.media.audio = {
      enabled = true;
      language = audioCfg.language;
      models = [
        {
          type = "cli";
          command = "${pkgs.whisper-cpp}/bin/whisper-cli";
          args = [
            "-m" "${whisperModel}"
            "-l" audioCfg.language
            "-np"
            "--no-gpu"
            "{{MediaPath}}"
          ];
          timeoutSeconds = audioCfg.timeoutSeconds;
        }
      ];
    };
  };

  whisperMediaConfigFile = pkgs.writeText "openclaw-media-config.json" whisperMediaConfig;

  patchConfigScript = pkgs.writeShellScript "patch-openclaw-audio" ''
    configFile="$HOME/.openclaw/openclaw.json"
    if [ -f "$configFile" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$configFile" "${whisperMediaConfigFile}" > "$configFile.tmp" \
        && ${pkgs.coreutils}/bin/mv "$configFile.tmp" "$configFile"
    fi
  '';

  # Build the channels.telegram attrset only when enabled.
  telegramChannel = lib.mkIf tgCfg.enable {
    tokenFile = tgCfg.tokenFile;
    allowFrom = lib.mkIf (tgCfg.allowFrom != [ ]) tgCfg.allowFrom;
    groups."*".requireMention = tgCfg.requireMentionInGroups;
    replyToMode = lib.mkIf (tgCfg.replyToMode != null) tgCfg.replyToMode;
    reactionLevel = lib.mkIf (tgCfg.reactionLevel != null) tgCfg.reactionLevel;
    reactionNotifications = lib.mkIf (tgCfg.reactionNotifications != null) tgCfg.reactionNotifications;
    ackReaction = lib.mkIf (tgCfg.ackReaction != null) tgCfg.ackReaction;
    actions = lib.mkIf (tgCfg.actions.reactions != null || tgCfg.actions.sendMessage != null || tgCfg.actions.sticker != null) {
      reactions = lib.mkIf (tgCfg.actions.reactions != null) tgCfg.actions.reactions;
      sendMessage = lib.mkIf (tgCfg.actions.sendMessage != null) tgCfg.actions.sendMessage;
      sticker = lib.mkIf (tgCfg.actions.sticker != null) tgCfg.actions.sticker;
    };
    streaming = lib.mkIf (tgCfg.streaming != null) tgCfg.streaming;
    blockStreaming = lib.mkIf (tgCfg.blockStreaming != null) tgCfg.blockStreaming;
  };
in
{
  # The gateway overwrites openclaw.json at runtime, which conflicts with
  # Home Manager's file management. Force overwrite to prevent activation failures.
  home.file.".openclaw/openclaw.json".force = true;

  programs.openclaw = {
    enable = true;
    package = pkgs.openclaw-gateway;
    config = {
      gateway = {
        mode = "local";
      };
      channels.telegram = telegramChannel;
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
      plugins = {
        enabled = true;
        allow = [ "clawpi-tools" "memory-core" ];
        load.paths = [
          "${pkgs.clawpi-tools}/lib/clawpi-tools"
        ];
        entries.clawpi-tools = {
          enabled = true;
          config = {};
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
    Service = {
      EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
    } // lib.optionalAttrs debugCfg {
      Environment = [ "OPENCLAW_VERBOSE=1" ];
    } // lib.optionalAttrs audioCfg.enable {
      ExecStartPre = toString patchConfigScript;
    };
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
